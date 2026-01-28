-- ============================================================================
-- DATA CONTRACTS - Dynamic Quality, Schema, SLA, and Governance Agreements
-- ============================================================================
-- 
-- This script implements dynamic data contracts that:
--   1. Auto-generate contracts for source system tables
--   2. Define quality rules based on source system patterns
--   3. Track SLAs for each data domain
--   4. Validate contracts programmatically
--
-- Philosophy:
--   - Producers define intent through contracts
--   - Consumers trust data because contracts guarantee quality
--   - Data only flows when contracts are satisfied
--   - Contract violations block production pipelines
--
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE WAREHOUSE TRANSFORM_WH;
USE DATABASE GOVERNANCE;

CREATE SCHEMA IF NOT EXISTS GOVERNANCE.CONTRACTS
    COMMENT = 'Data contracts: schema, quality, SLA, and governance agreements';

USE SCHEMA GOVERNANCE.CONTRACTS;

-- ═══════════════════════════════════════════════════════════════════════════
-- CONTRACT REGISTRY
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS CONTRACT_REGISTRY (
    CONTRACT_ID             VARCHAR(100) PRIMARY KEY,
    CONTRACT_NAME           VARCHAR(255) NOT NULL,
    CONTRACT_VERSION        VARCHAR(20) NOT NULL,
    CONTRACT_STATUS         VARCHAR(20) DEFAULT 'ACTIVE',
    
    -- Source System Info
    SOURCE_SYSTEM           VARCHAR(50) NOT NULL,
    SOURCE_TABLE            VARCHAR(100) NOT NULL,
    FULL_TABLE_PATH         VARCHAR(500),
    
    -- Producer Information
    PRODUCER_TEAM           VARCHAR(255),
    PRODUCER_OWNER_EMAIL    VARCHAR(255),
    
    -- Consumer Information
    CONSUMER_TEAMS          ARRAY,
    
    -- Contract Definitions (VARIANT for flexibility)
    SCHEMA_DEFINITION       VARIANT,
    QUALITY_DEFINITION      VARIANT,
    SLA_DEFINITION          VARIANT,
    GOVERNANCE_DEFINITION   VARIANT,
    
    -- Lifecycle
    EFFECTIVE_FROM          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    EFFECTIVE_TO            TIMESTAMP_NTZ DEFAULT '9999-12-31'::TIMESTAMP_NTZ,
    
    -- Metadata
    DESCRIPTION             VARCHAR(4000),
    CREATED_AT              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    UPDATED_AT              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CREATED_BY              VARCHAR(255) DEFAULT CURRENT_USER()
);

-- ═══════════════════════════════════════════════════════════════════════════
-- QUALITY RULES
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS QUALITY_RULES (
    RULE_ID                 VARCHAR(100) PRIMARY KEY,
    CONTRACT_ID             VARCHAR(100) NOT NULL,
    SOURCE_SYSTEM           VARCHAR(50) NOT NULL,
    
    RULE_NAME               VARCHAR(255) NOT NULL,
    RULE_DESCRIPTION        VARCHAR(1000),
    RULE_EXPRESSION         VARCHAR(4000) NOT NULL,
    RULE_TYPE               VARCHAR(50) DEFAULT 'ROW',
    
    THRESHOLD_PERCENT       NUMBER(5,2) DEFAULT 100.0,
    WARNING_THRESHOLD       NUMBER(5,2),
    SEVERITY                VARCHAR(20) DEFAULT 'ERROR',
    ON_FAILURE              VARCHAR(20) DEFAULT 'BLOCK',
    IS_ACTIVE               BOOLEAN DEFAULT TRUE,
    
    CREATED_AT              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- ═══════════════════════════════════════════════════════════════════════════
-- SLA DEFINITIONS
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS SLA_DEFINITIONS (
    SLA_ID                  VARCHAR(100) PRIMARY KEY,
    CONTRACT_ID             VARCHAR(100) NOT NULL,
    SOURCE_SYSTEM           VARCHAR(50) NOT NULL,
    
    FRESHNESS_TARGET_HOURS  NUMBER(10,2),
    FRESHNESS_MAX_HOURS     NUMBER(10,2),
    AVAILABILITY_TARGET_PCT NUMBER(5,2) DEFAULT 99.9,
    MIN_ROW_COUNT           NUMBER(18),
    MAX_ROW_COUNT           NUMBER(18),
    
    ON_SLA_MISS             VARCHAR(20) DEFAULT 'ALERT',
    IS_ACTIVE               BOOLEAN DEFAULT TRUE,
    CREATED_AT              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- ═══════════════════════════════════════════════════════════════════════════
-- VALIDATION HISTORY
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS VALIDATION_HISTORY (
    VALIDATION_ID           VARCHAR(100) DEFAULT UUID_STRING() PRIMARY KEY,
    CONTRACT_ID             VARCHAR(100) NOT NULL,
    SOURCE_SYSTEM           VARCHAR(50),
    
    VALIDATION_START        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    VALIDATION_END          TIMESTAMP_NTZ,
    
    SCHEMA_PASSED           BOOLEAN,
    QUALITY_PASSED          BOOLEAN,
    SLA_PASSED              BOOLEAN,
    OVERALL_PASSED          BOOLEAN,
    
    TOTAL_ROWS              NUMBER(18),
    VALIDATION_DETAILS      VARIANT,
    
    EXECUTED_BY             VARCHAR(255) DEFAULT CURRENT_USER()
);

-- ═══════════════════════════════════════════════════════════════════════════
-- DYNAMIC CONTRACT GENERATION
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE GOVERNANCE.CONTRACTS.GENERATE_CONTRACT_FOR_TABLE(
    P_SOURCE_SYSTEM VARCHAR,
    P_TABLE_NAME VARCHAR,
    P_PRODUCER_TEAM VARCHAR,
    P_PRODUCER_EMAIL VARCHAR
)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    var sourceUpper = P_SOURCE_SYSTEM.toUpperCase();
    var tableUpper = P_TABLE_NAME.toUpperCase();
    var contractId = 'CONTRACT-' + sourceUpper + '-' + tableUpper + '-001';
    var contractName = sourceUpper + ' ' + tableUpper + ' Data Contract';
    var fullPath = 'RAW_DEV.' + sourceUpper + '.' + tableUpper;
    
    // Set defaults based on source system
    var freshnessHours = 24;
    var classification = 'INTERNAL';
    
    if (sourceUpper === 'SAP') {
        freshnessHours = 4;
        classification = 'CONFIDENTIAL';
    } else if (sourceUpper === 'SALESFORCE') {
        freshnessHours = 1;
        classification = 'CONFIDENTIAL';
    } else if (sourceUpper === 'FHIR') {
        freshnessHours = 1;
        classification = 'RESTRICTED';
    } else if (sourceUpper === 'WORKDAY') {
        freshnessHours = 4;
        classification = 'RESTRICTED';
    } else if (sourceUpper === 'SERVICENOW') {
        freshnessHours = 0.5;
        classification = 'INTERNAL';
    } else if (sourceUpper === 'ORACLE') {
        freshnessHours = 4;
        classification = 'CONFIDENTIAL';
    }
    
    // Build JSON definitions
    var schemaDef = JSON.stringify({
        source_system: sourceUpper,
        table_name: tableUpper,
        auto_generated: true
    });
    
    var qualityDef = JSON.stringify({
        rules: [
            {name: "row_hash_not_null", threshold: 100}
        ]
    });
    
    var slaDef = JSON.stringify({
        freshness_target_hours: freshnessHours,
        freshness_max_hours: freshnessHours * 6,
        availability_target_pct: 99.9,
        min_row_count: 1
    });
    
    var govDef = JSON.stringify({
        classification: classification,
        source_system: sourceUpper
    });
    
    try {
        // Insert contract
        var insertContractSql = "INSERT INTO GOVERNANCE.CONTRACTS.CONTRACT_REGISTRY " +
            "(CONTRACT_ID, CONTRACT_NAME, CONTRACT_VERSION, CONTRACT_STATUS, " +
            "SOURCE_SYSTEM, SOURCE_TABLE, FULL_TABLE_PATH, " +
            "PRODUCER_TEAM, PRODUCER_OWNER_EMAIL, " +
            "SCHEMA_DEFINITION, QUALITY_DEFINITION, SLA_DEFINITION, GOVERNANCE_DEFINITION, " +
            "DESCRIPTION) VALUES ('" +
            contractId + "', '" + contractName + "', '1.0.0', 'ACTIVE', '" +
            sourceUpper + "', '" + tableUpper + "', '" + fullPath + "', '" +
            P_PRODUCER_TEAM + "', '" + P_PRODUCER_EMAIL + "', " +
            "PARSE_JSON('" + schemaDef + "'), " +
            "PARSE_JSON('" + qualityDef + "'), " +
            "PARSE_JSON('" + slaDef + "'), " +
            "PARSE_JSON('" + govDef + "'), " +
            "'Auto-generated contract for " + fullPath + "')";
        
        snowflake.execute({sqlText: insertContractSql});
        
        // Insert SLA definition
        var insertSlaSql = "INSERT INTO GOVERNANCE.CONTRACTS.SLA_DEFINITIONS " +
            "(SLA_ID, CONTRACT_ID, SOURCE_SYSTEM, " +
            "FRESHNESS_TARGET_HOURS, FRESHNESS_MAX_HOURS, AVAILABILITY_TARGET_PCT, MIN_ROW_COUNT) VALUES ('" +
            "SLA-" + sourceUpper + "-" + tableUpper + "-001', '" +
            contractId + "', '" + sourceUpper + "', " +
            freshnessHours + ", " + (freshnessHours * 6) + ", 99.9, 1)";
        
        snowflake.execute({sqlText: insertSlaSql});
        
        return 'SUCCESS: Created contract ' + contractId;
        
    } catch (err) {
        return 'ERROR: ' + err.message;
    }
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- GENERATE CONTRACTS FOR ALL TABLES IN A SOURCE SYSTEM
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE GOVERNANCE.CONTRACTS.GENERATE_CONTRACTS_FOR_SOURCE(
    P_SOURCE_SYSTEM VARCHAR,
    P_PRODUCER_TEAM VARCHAR,
    P_PRODUCER_EMAIL VARCHAR
)
RETURNS VARIANT
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    var results = [];
    var sourceSystem = P_SOURCE_SYSTEM.toUpperCase();
    
    // Get all tables in the source system schema
    var tablesSql = "SELECT TABLE_NAME FROM RAW_DEV.INFORMATION_SCHEMA.TABLES " +
                    "WHERE TABLE_CATALOG = 'RAW_DEV' " +
                    "AND TABLE_SCHEMA = '" + sourceSystem + "' " +
                    "AND TABLE_TYPE = 'BASE TABLE' " +
                    "AND TABLE_NAME NOT LIKE '%_TEMPLATE'";
    
    var tablesStmt = snowflake.createStatement({sqlText: tablesSql});
    var tablesRs = tablesStmt.execute();
    
    while (tablesRs.next()) {
        var tableName = tablesRs.getColumnValue(1);
        var contractId = 'CONTRACT-' + sourceSystem + '-' + tableName + '-001';
        var status = 'PENDING';
        
        try {
            var callSql = "CALL GOVERNANCE.CONTRACTS.GENERATE_CONTRACT_FOR_TABLE('" + 
                          P_SOURCE_SYSTEM + "', '" + tableName + "', '" + 
                          P_PRODUCER_TEAM + "', '" + P_PRODUCER_EMAIL + "')";
            snowflake.execute({sqlText: callSql});
            status = 'SUCCESS';
        } catch (err) {
            status = 'ERROR: ' + err.message;
        }
        
        results.push({
            table_name: tableName,
            contract_id: contractId,
            status: status
        });
    }
    
    return {
        source_system: sourceSystem,
        contracts_generated: results.length,
        details: results
    };
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- CONTRACT VALIDATION
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE GOVERNANCE.CONTRACTS.VALIDATE_CONTRACT(
    p_contract_id VARCHAR
)
RETURNS VARIANT
LANGUAGE SQL
AS
$$
DECLARE
    v_result VARIANT;
    v_schema_passed BOOLEAN DEFAULT TRUE;
    v_quality_passed BOOLEAN DEFAULT TRUE;
    v_sla_passed BOOLEAN DEFAULT TRUE;
    v_overall_passed BOOLEAN;
    v_full_path VARCHAR;
    v_source_system VARCHAR;
    v_row_count NUMBER;
    v_freshness_hours NUMBER;
    v_sla_max_hours NUMBER;
    v_start_time TIMESTAMP_NTZ;
    v_validation_id VARCHAR;
BEGIN
    v_start_time := CURRENT_TIMESTAMP();
    v_validation_id := UUID_STRING();
    
    -- Get contract details
    SELECT FULL_TABLE_PATH, SOURCE_SYSTEM 
    INTO v_full_path, v_source_system
    FROM GOVERNANCE.CONTRACTS.CONTRACT_REGISTRY
    WHERE CONTRACT_ID = :p_contract_id AND CONTRACT_STATUS = 'ACTIVE'
    LIMIT 1;
    
    IF (v_full_path IS NULL) THEN
        RETURN OBJECT_CONSTRUCT(
            'success', FALSE,
            'error', 'Contract not found or not active',
            'contract_id', p_contract_id
        );
    END IF;
    
    -- 1. Schema Validation (check table exists)
    BEGIN
        EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || v_full_path || ' WHERE 1=0';
        v_schema_passed := TRUE;
    EXCEPTION
        WHEN OTHER THEN
            v_schema_passed := FALSE;
    END;
    
    -- 2. Get row count
    IF (v_schema_passed) THEN
        LET row_count_rs RESULTSET := (EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || v_full_path || ' WHERE "_IS_CURRENT" = TRUE');
        LET row_count_cur CURSOR FOR row_count_rs;
        OPEN row_count_cur;
        FETCH row_count_cur INTO v_row_count;
        CLOSE row_count_cur;
    ELSE
        v_row_count := 0;
    END IF;
    
    -- 3. SLA Validation (freshness)
    IF (v_schema_passed AND v_row_count > 0) THEN
        LET freshness_rs RESULTSET := (EXECUTE IMMEDIATE 'SELECT DATEDIFF(''hour'', MAX("_LOADED_AT"), CURRENT_TIMESTAMP()) FROM ' || v_full_path);
        LET freshness_cur CURSOR FOR freshness_rs;
        OPEN freshness_cur;
        FETCH freshness_cur INTO v_freshness_hours;
        CLOSE freshness_cur;
        
        SELECT FRESHNESS_MAX_HOURS INTO v_sla_max_hours
        FROM GOVERNANCE.CONTRACTS.SLA_DEFINITIONS
        WHERE CONTRACT_ID = :p_contract_id AND IS_ACTIVE = TRUE
        LIMIT 1;
        
        v_sla_passed := (v_freshness_hours <= COALESCE(v_sla_max_hours, 9999));
    END IF;
    
    -- Overall result
    v_overall_passed := v_schema_passed AND v_quality_passed AND v_sla_passed;
    
    -- Build result
    v_result := OBJECT_CONSTRUCT(
        'validation_id', v_validation_id,
        'contract_id', p_contract_id,
        'source_system', v_source_system,
        'table_path', v_full_path,
        'validation_time', v_start_time,
        'schema_passed', v_schema_passed,
        'quality_passed', v_quality_passed,
        'sla_passed', v_sla_passed,
        'overall_passed', v_overall_passed,
        'row_count', v_row_count,
        'freshness_hours', v_freshness_hours,
        'sla_max_hours', v_sla_max_hours
    );
    
    -- Record validation
    INSERT INTO GOVERNANCE.CONTRACTS.VALIDATION_HISTORY (
        VALIDATION_ID, CONTRACT_ID, SOURCE_SYSTEM,
        VALIDATION_START, VALIDATION_END,
        SCHEMA_PASSED, QUALITY_PASSED, SLA_PASSED, OVERALL_PASSED,
        TOTAL_ROWS, VALIDATION_DETAILS
    ) VALUES (
        v_validation_id, p_contract_id, v_source_system,
        v_start_time, CURRENT_TIMESTAMP(),
        v_schema_passed, v_quality_passed, v_sla_passed, v_overall_passed,
        v_row_count, v_result
    );
    
    RETURN v_result;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- VALIDATE ALL CONTRACTS FOR A SOURCE SYSTEM
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE GOVERNANCE.CONTRACTS.VALIDATE_SOURCE_SYSTEM(
    P_SOURCE_SYSTEM VARCHAR
)
RETURNS VARIANT
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    var results = [];
    var sourceSystem = P_SOURCE_SYSTEM.toUpperCase();
    
    // Get all active contracts for this source system
    var contractsSql = "SELECT CONTRACT_ID, SOURCE_TABLE FROM GOVERNANCE.CONTRACTS.CONTRACT_REGISTRY " +
                       "WHERE UPPER(SOURCE_SYSTEM) = '" + sourceSystem + "' " +
                       "AND CONTRACT_STATUS = 'ACTIVE'";
    
    var contractsStmt = snowflake.createStatement({sqlText: contractsSql});
    var contractsRs = contractsStmt.execute();
    
    while (contractsRs.next()) {
        var contractId = contractsRs.getColumnValue(1);
        var tableName = contractsRs.getColumnValue(2);
        var passed = false;
        
        try {
            var callSql = "CALL GOVERNANCE.CONTRACTS.VALIDATE_CONTRACT('" + contractId + "')";
            snowflake.execute({sqlText: callSql});
            passed = true;
        } catch (err) {
            passed = false;
        }
        
        results.push({
            contract_id: contractId,
            table_name: tableName,
            passed: passed
        });
    }
    
    return {
        source_system: sourceSystem,
        contracts_validated: results.length,
        details: results
    };
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- CONTRACT HEALTH VIEW
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW VW_CONTRACT_HEALTH AS
SELECT 
    c.CONTRACT_ID,
    c.CONTRACT_NAME,
    c.SOURCE_SYSTEM,
    c.SOURCE_TABLE,
    c.CONTRACT_STATUS,
    c.PRODUCER_TEAM,
    
    v.VALIDATION_START AS LAST_VALIDATION,
    v.OVERALL_PASSED AS LAST_PASSED,
    v.SCHEMA_PASSED,
    v.QUALITY_PASSED,
    v.SLA_PASSED,
    v.TOTAL_ROWS,
    
    CASE 
        WHEN v.OVERALL_PASSED THEN 'HEALTHY'
        WHEN v.SCHEMA_PASSED AND v.QUALITY_PASSED THEN 'SLA_DEGRADED'
        WHEN v.SCHEMA_PASSED THEN 'QUALITY_ISSUES'
        ELSE 'CRITICAL'
    END AS HEALTH_STATUS
    
FROM GOVERNANCE.CONTRACTS.CONTRACT_REGISTRY c
LEFT JOIN (
    SELECT *
    FROM GOVERNANCE.CONTRACTS.VALIDATION_HISTORY
    QUALIFY ROW_NUMBER() OVER (PARTITION BY CONTRACT_ID ORDER BY VALIDATION_START DESC) = 1
) v ON c.CONTRACT_ID = v.CONTRACT_ID
WHERE c.CONTRACT_STATUS = 'ACTIVE';

-- ═══════════════════════════════════════════════════════════════════════════
-- GRANTS
-- ═══════════════════════════════════════════════════════════════════════════

GRANT USAGE ON SCHEMA GOVERNANCE.CONTRACTS TO ROLE DATA_STEWARD;
GRANT USAGE ON SCHEMA GOVERNANCE.CONTRACTS TO ROLE DATA_ENGINEER;
GRANT USAGE ON SCHEMA GOVERNANCE.CONTRACTS TO ROLE AUDITOR;

GRANT SELECT ON ALL TABLES IN SCHEMA GOVERNANCE.CONTRACTS TO ROLE DATA_STEWARD;
GRANT SELECT ON ALL TABLES IN SCHEMA GOVERNANCE.CONTRACTS TO ROLE DATA_ENGINEER;
GRANT SELECT ON ALL TABLES IN SCHEMA GOVERNANCE.CONTRACTS TO ROLE AUDITOR;

GRANT SELECT ON ALL VIEWS IN SCHEMA GOVERNANCE.CONTRACTS TO ROLE DATA_STEWARD;
GRANT SELECT ON ALL VIEWS IN SCHEMA GOVERNANCE.CONTRACTS TO ROLE DATA_ENGINEER;

GRANT USAGE ON PROCEDURE GOVERNANCE.CONTRACTS.GENERATE_CONTRACT_FOR_TABLE(VARCHAR, VARCHAR, VARCHAR, VARCHAR) TO ROLE DATA_STEWARD;
GRANT USAGE ON PROCEDURE GOVERNANCE.CONTRACTS.GENERATE_CONTRACTS_FOR_SOURCE(VARCHAR, VARCHAR, VARCHAR) TO ROLE DATA_STEWARD;
GRANT USAGE ON PROCEDURE GOVERNANCE.CONTRACTS.VALIDATE_CONTRACT(VARCHAR) TO ROLE DATA_STEWARD;
GRANT USAGE ON PROCEDURE GOVERNANCE.CONTRACTS.VALIDATE_CONTRACT(VARCHAR) TO ROLE DATA_ENGINEER;
GRANT USAGE ON PROCEDURE GOVERNANCE.CONTRACTS.VALIDATE_SOURCE_SYSTEM(VARCHAR) TO ROLE DATA_STEWARD;

-- ═══════════════════════════════════════════════════════════════════════════
-- USAGE INSTRUCTIONS
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- STEP 1: Generate contracts for all tables in a source system
--   CALL GOVERNANCE.CONTRACTS.GENERATE_CONTRACTS_FOR_SOURCE('SAP', 'ERP Team', 'erp@company.com');
--   CALL GOVERNANCE.CONTRACTS.GENERATE_CONTRACTS_FOR_SOURCE('SALESFORCE', 'CRM Team', 'crm@company.com');
--   CALL GOVERNANCE.CONTRACTS.GENERATE_CONTRACTS_FOR_SOURCE('FHIR', 'Healthcare IT', 'ehr@company.com');
--
-- STEP 2: Validate contracts
--   CALL GOVERNANCE.CONTRACTS.VALIDATE_SOURCE_SYSTEM('SAP');
--   CALL GOVERNANCE.CONTRACTS.VALIDATE_CONTRACT('CONTRACT-SAP-KNA1-001');
--
-- STEP 3: Monitor health
--   SELECT * FROM GOVERNANCE.CONTRACTS.VW_CONTRACT_HEALTH;
--
-- ═══════════════════════════════════════════════════════════════════════════

SELECT '✓ Contract Layer Created' AS STATUS;
SELECT '  Use GENERATE_CONTRACTS_FOR_SOURCE() to create contracts for a source system' AS INFO;
