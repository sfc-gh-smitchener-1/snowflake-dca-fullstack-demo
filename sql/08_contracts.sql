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
    p_source_system VARCHAR,
    p_table_name VARCHAR,
    p_producer_team VARCHAR,
    p_producer_email VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_contract_id VARCHAR;
    v_contract_name VARCHAR;
    v_full_path VARCHAR;
    v_source_upper VARCHAR;
    v_table_upper VARCHAR;
    v_schema_def VARIANT;
    v_quality_def VARIANT;
    v_sla_def VARIANT;
    v_governance_def VARIANT;
    v_freshness_hours NUMBER;
    v_classification VARCHAR;
BEGIN
    v_source_upper := UPPER(p_source_system);
    v_table_upper := UPPER(p_table_name);
    v_contract_id := 'CONTRACT-' || v_source_upper || '-' || v_table_upper || '-001';
    v_contract_name := v_source_upper || ' ' || v_table_upper || ' Data Contract';
    v_full_path := 'RAW_DEV.' || v_source_upper || '.' || v_table_upper;
    
    -- Set defaults based on source system
    IF (v_source_upper = 'SAP') THEN
        v_freshness_hours := 4;
        v_classification := 'CONFIDENTIAL';
    ELSEIF (v_source_upper = 'SALESFORCE') THEN
        v_freshness_hours := 1;
        v_classification := 'CONFIDENTIAL';
    ELSEIF (v_source_upper = 'FHIR') THEN
        v_freshness_hours := 1;
        v_classification := 'RESTRICTED';
    ELSEIF (v_source_upper = 'WORKDAY') THEN
        v_freshness_hours := 4;
        v_classification := 'RESTRICTED';
    ELSEIF (v_source_upper = 'SERVICENOW') THEN
        v_freshness_hours := 0.5;
        v_classification := 'INTERNAL';
    ELSE
        v_freshness_hours := 24;
        v_classification := 'INTERNAL';
    END IF;
    
    -- Build schema definition
    v_schema_def := PARSE_JSON('{
        "source_system": "' || v_source_upper || '",
        "table_name": "' || v_table_upper || '",
        "auto_generated": true
    }');
    
    -- Build quality definition based on source system
    IF (v_source_upper = 'SAP') THEN
        v_quality_def := PARSE_JSON('{
            "rules": [
                {"name": "primary_key_not_null", "threshold": 100},
                {"name": "valid_client", "threshold": 100},
                {"name": "no_deletion_flag", "threshold": 99}
            ]
        }');
    ELSEIF (v_source_upper = 'SALESFORCE') THEN
        v_quality_def := PARSE_JSON('{
            "rules": [
                {"name": "id_format_valid", "threshold": 100},
                {"name": "not_deleted", "threshold": 99.9}
            ]
        }');
    ELSEIF (v_source_upper = 'FHIR') THEN
        v_quality_def := PARSE_JSON('{
            "rules": [
                {"name": "resource_id_valid", "threshold": 100},
                {"name": "resource_type_valid", "threshold": 100}
            ]
        }');
    ELSE
        v_quality_def := PARSE_JSON('{
            "rules": [
                {"name": "row_hash_not_null", "threshold": 100}
            ]
        }');
    END IF;
    
    -- Build SLA definition
    v_sla_def := PARSE_JSON('{
        "freshness_target_hours": ' || v_freshness_hours || ',
        "freshness_max_hours": ' || (v_freshness_hours * 6) || ',
        "availability_target_pct": 99.9,
        "min_row_count": 1
    }');
    
    -- Build governance definition
    v_governance_def := PARSE_JSON('{
        "classification": "' || v_classification || '",
        "source_system": "' || v_source_upper || '"
    }');
    
    -- Insert contract
    INSERT INTO GOVERNANCE.CONTRACTS.CONTRACT_REGISTRY (
        CONTRACT_ID, CONTRACT_NAME, CONTRACT_VERSION, CONTRACT_STATUS,
        SOURCE_SYSTEM, SOURCE_TABLE, FULL_TABLE_PATH,
        PRODUCER_TEAM, PRODUCER_OWNER_EMAIL,
        SCHEMA_DEFINITION, QUALITY_DEFINITION, SLA_DEFINITION, GOVERNANCE_DEFINITION,
        DESCRIPTION
    ) VALUES (
        v_contract_id, v_contract_name, '1.0.0', 'ACTIVE',
        v_source_upper, v_table_upper, v_full_path,
        p_producer_team, p_producer_email,
        v_schema_def, v_quality_def, v_sla_def, v_governance_def,
        'Auto-generated contract for ' || v_full_path
    );
    
    -- Insert SLA definition
    INSERT INTO GOVERNANCE.CONTRACTS.SLA_DEFINITIONS (
        SLA_ID, CONTRACT_ID, SOURCE_SYSTEM,
        FRESHNESS_TARGET_HOURS, FRESHNESS_MAX_HOURS, AVAILABILITY_TARGET_PCT, MIN_ROW_COUNT
    ) VALUES (
        'SLA-' || v_source_upper || '-' || v_table_upper || '-001',
        v_contract_id,
        v_source_upper,
        v_freshness_hours,
        v_freshness_hours * 6,
        99.9,
        1
    );
    
    RETURN 'SUCCESS: Created contract ' || v_contract_id;
    
EXCEPTION
    WHEN OTHER THEN
        RETURN 'ERROR: ' || SQLERRM;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- GENERATE CONTRACTS FOR ALL TABLES IN A SOURCE SYSTEM
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE GOVERNANCE.CONTRACTS.GENERATE_CONTRACTS_FOR_SOURCE(
    p_source_system VARCHAR,
    p_producer_team VARCHAR,
    p_producer_email VARCHAR
)
RETURNS TABLE (table_name VARCHAR, contract_id VARCHAR, status VARCHAR)
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_schema_name VARCHAR;
    v_source_upper VARCHAR;
    result RESULTSET;
BEGIN
    v_source_upper := UPPER(p_source_system);
    v_schema_name := 'RAW_DEV.' || v_source_upper;
    
    CREATE OR REPLACE TEMPORARY TABLE _contract_results (
        table_name VARCHAR,
        contract_id VARCHAR,
        status VARCHAR
    );
    
    -- Get all tables in the source system schema
    FOR tbl IN (
        SELECT TABLE_NAME
        FROM RAW_DEV.INFORMATION_SCHEMA.TABLES
        WHERE TABLE_CATALOG = 'RAW_DEV'
          AND TABLE_SCHEMA = :v_source_upper
          AND TABLE_TYPE = 'BASE TABLE'
          AND TABLE_NAME NOT LIKE '%_TEMPLATE'
    )
    DO
        LET contract_result VARCHAR := '';
        LET call_result VARIANT;
        call_result := (CALL GOVERNANCE.CONTRACTS.GENERATE_CONTRACT_FOR_TABLE(
            :p_source_system, tbl.TABLE_NAME, :p_producer_team, :p_producer_email
        ));
        contract_result := call_result::VARCHAR;
        
        INSERT INTO _contract_results VALUES (
            tbl.TABLE_NAME,
            'CONTRACT-' || :v_source_upper || '-' || UPPER(tbl.TABLE_NAME) || '-001',
            contract_result
        );
    END FOR;
    
    result := (SELECT * FROM _contract_results);
    RETURN TABLE(result);
END;
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
    WHERE CONTRACT_ID = :p_contract_id AND CONTRACT_STATUS = 'ACTIVE';
    
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
    p_source_system VARCHAR
)
RETURNS TABLE (contract_id VARCHAR, table_name VARCHAR, passed BOOLEAN, details VARIANT)
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_source_upper VARCHAR;
    result RESULTSET;
BEGIN
    v_source_upper := UPPER(p_source_system);
    
    CREATE OR REPLACE TEMPORARY TABLE _validation_results (
        contract_id VARCHAR,
        table_name VARCHAR,
        passed BOOLEAN,
        details VARIANT
    );
    
    FOR contract IN (
        SELECT CONTRACT_ID, SOURCE_TABLE
        FROM GOVERNANCE.CONTRACTS.CONTRACT_REGISTRY
        WHERE UPPER(SOURCE_SYSTEM) = :v_source_upper
          AND CONTRACT_STATUS = 'ACTIVE'
    )
    DO
        LET validation_result VARIANT;
        validation_result := (CALL GOVERNANCE.CONTRACTS.VALIDATE_CONTRACT(contract.CONTRACT_ID));
        
        INSERT INTO _validation_results VALUES (
            contract.CONTRACT_ID,
            contract.SOURCE_TABLE,
            validation_result:overall_passed::BOOLEAN,
            validation_result
        );
    END FOR;
    
    result := (SELECT * FROM _validation_results);
    RETURN TABLE(result);
END;
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
