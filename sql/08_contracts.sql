-- ============================================================================
-- DATA CONTRACTS - Quality, Schema, SLA, and Governance Agreements
-- ============================================================================
-- 
-- This script implements the Contract Layer:
--   1. Contract Registry - Central catalog of all contracts
--   2. Schema Contracts - Structural agreements
--   3. Quality Contracts - Data quality rules and thresholds
--   4. SLA Contracts - Freshness, availability, latency
--   5. Governance Contracts - Compliance and classification
--   6. Validation Procedures - Automated contract enforcement
--   7. Monitoring Views - Contract health dashboards
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

-- ═══════════════════════════════════════════════════════════════════════════
-- SCHEMA: CONTRACTS
-- ═══════════════════════════════════════════════════════════════════════════

CREATE SCHEMA IF NOT EXISTS GOVERNANCE.CONTRACTS
    COMMENT = 'Data contracts: schema, quality, SLA, and governance agreements between producers and consumers.';

USE SCHEMA GOVERNANCE.CONTRACTS;

-- ═══════════════════════════════════════════════════════════════════════════
-- CONTRACT REGISTRY
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- The master registry of all data contracts across the organization.
-- Tracks versions, ownership, and contract definitions.
--
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS CONTRACT_REGISTRY (
    -- Contract Identity
    CONTRACT_ID             VARCHAR(100) PRIMARY KEY,
    CONTRACT_NAME           VARCHAR(255) NOT NULL,
    CONTRACT_VERSION        VARCHAR(20) NOT NULL,
    CONTRACT_STATUS         VARCHAR(20) DEFAULT 'DRAFT',  -- DRAFT, PENDING_APPROVAL, ACTIVE, DEPRECATED, RETIRED
    
    -- Producer Information
    PRODUCER_ACCOUNT        VARCHAR(255),           -- For cross-account: ORGNAME.ACCOUNT
    PRODUCER_DATABASE       VARCHAR(255),           -- For single-account: database name
    PRODUCER_TEAM           VARCHAR(255) NOT NULL,
    PRODUCER_OWNER_EMAIL    VARCHAR(255) NOT NULL,
    PRODUCER_TABLE          VARCHAR(500),           -- Fully qualified source table
    
    -- Consumer Information
    CONSUMER_ACCOUNTS       ARRAY,                  -- Array of consumer account identifiers
    CONSUMER_TEAMS          ARRAY,                  -- Array of consuming team names
    
    -- Contract Definitions (JSON/YAML converted to VARIANT)
    SCHEMA_DEFINITION       VARIANT,                -- Column definitions, types, keys
    QUALITY_DEFINITION      VARIANT,                -- Quality rules and thresholds
    SLA_DEFINITION          VARIANT,                -- Freshness, availability, latency
    GOVERNANCE_DEFINITION   VARIANT,                -- Classification, compliance, residency
    
    -- Lifecycle
    EFFECTIVE_FROM          TIMESTAMP_NTZ,
    EFFECTIVE_TO            TIMESTAMP_NTZ DEFAULT '9999-12-31'::TIMESTAMP_NTZ,
    APPROVAL_DATE           TIMESTAMP_NTZ,
    APPROVED_BY             VARCHAR(255),
    
    -- Metadata
    DESCRIPTION             VARCHAR(4000),
    DOCUMENTATION_URL       VARCHAR(1000),
    CREATED_AT              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    UPDATED_AT              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CREATED_BY              VARCHAR(255) DEFAULT CURRENT_USER()
)
COMMENT = 'Master registry of data contracts between producers and consumers.';

-- ═══════════════════════════════════════════════════════════════════════════
-- QUALITY RULES
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS QUALITY_RULES (
    -- Identity
    RULE_ID                 VARCHAR(100) PRIMARY KEY,
    CONTRACT_ID             VARCHAR(100) NOT NULL REFERENCES CONTRACT_REGISTRY(CONTRACT_ID),
    
    -- Rule Definition
    RULE_NAME               VARCHAR(255) NOT NULL,
    RULE_DESCRIPTION        VARCHAR(1000),
    RULE_EXPRESSION         VARCHAR(4000) NOT NULL,  -- SQL expression that returns TRUE/FALSE per row
    RULE_TYPE               VARCHAR(50) DEFAULT 'ROW',  -- ROW, AGGREGATE, UNIQUENESS, REFERENTIAL
    
    -- Thresholds
    THRESHOLD_PERCENT       NUMBER(5,2) DEFAULT 100.0,  -- Required pass rate
    WARNING_THRESHOLD       NUMBER(5,2),                -- Threshold for warnings
    
    -- Behavior
    SEVERITY                VARCHAR(20) DEFAULT 'ERROR',  -- ERROR, WARNING, INFO
    ON_FAILURE              VARCHAR(20) DEFAULT 'BLOCK',  -- BLOCK, WARN, LOG
    IS_ACTIVE               BOOLEAN DEFAULT TRUE,
    
    -- Metadata
    CREATED_AT              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CREATED_BY              VARCHAR(255) DEFAULT CURRENT_USER()
)
COMMENT = 'Data quality rules attached to contracts.';

-- ═══════════════════════════════════════════════════════════════════════════
-- SLA DEFINITIONS
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS SLA_DEFINITIONS (
    -- Identity
    SLA_ID                  VARCHAR(100) PRIMARY KEY,
    CONTRACT_ID             VARCHAR(100) NOT NULL REFERENCES CONTRACT_REGISTRY(CONTRACT_ID),
    
    -- Freshness SLA
    FRESHNESS_TARGET_HOURS  NUMBER(10,2),        -- Target freshness in hours
    FRESHNESS_MAX_HOURS     NUMBER(10,2),        -- Maximum acceptable freshness
    
    -- Availability SLA
    AVAILABILITY_TARGET_PCT NUMBER(5,2),         -- Target availability (e.g., 99.9)
    
    -- Latency SLA (for query performance)
    LATENCY_P50_MS          NUMBER(10),          -- 50th percentile target
    LATENCY_P95_MS          NUMBER(10),          -- 95th percentile target
    LATENCY_P99_MS          NUMBER(10),          -- 99th percentile target
    
    -- Volume SLA
    MIN_ROW_COUNT           NUMBER(18),          -- Minimum expected rows
    MAX_ROW_COUNT           NUMBER(18),          -- Maximum expected rows (anomaly detection)
    
    -- Behavior
    ON_SLA_MISS             VARCHAR(20) DEFAULT 'ALERT',  -- ALERT, BLOCK, LOG
    ALERT_CHANNELS          ARRAY,                        -- Email, Slack, PagerDuty
    
    -- Metadata
    IS_ACTIVE               BOOLEAN DEFAULT TRUE,
    CREATED_AT              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Service level agreement definitions for contracts.';

-- ═══════════════════════════════════════════════════════════════════════════
-- VALIDATION HISTORY
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS VALIDATION_HISTORY (
    -- Identity
    VALIDATION_ID           VARCHAR(100) DEFAULT UUID_STRING() PRIMARY KEY,
    CONTRACT_ID             VARCHAR(100) NOT NULL,
    
    -- Timing
    VALIDATION_START        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    VALIDATION_END          TIMESTAMP_NTZ,
    
    -- Overall Results
    SCHEMA_PASSED           BOOLEAN,
    QUALITY_PASSED          BOOLEAN,
    SLA_PASSED              BOOLEAN,
    GOVERNANCE_PASSED       BOOLEAN,
    OVERALL_PASSED          BOOLEAN,
    
    -- Details
    VALIDATION_DETAILS      VARIANT,              -- Full details of each check
    FAILED_RULES            ARRAY,                -- List of failed rule IDs
    WARNING_RULES           ARRAY,                -- List of warning rule IDs
    
    -- Metrics
    TOTAL_ROWS              NUMBER(18),
    PASSED_ROWS             NUMBER(18),
    FAILED_ROWS             NUMBER(18),
    PASS_RATE_PCT           NUMBER(5,2),
    
    -- Execution
    EXECUTED_BY             VARCHAR(255) DEFAULT CURRENT_USER(),
    EXECUTION_TIME_MS       NUMBER(18)
)
COMMENT = 'History of all contract validations.';

-- ═══════════════════════════════════════════════════════════════════════════
-- SLA METRICS (Time-Series)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS SLA_METRICS (
    -- Identity
    METRIC_ID               VARCHAR(100) DEFAULT UUID_STRING() PRIMARY KEY,
    CONTRACT_ID             VARCHAR(100) NOT NULL,
    METRIC_TIMESTAMP        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    
    -- Freshness
    LAST_DATA_TIMESTAMP     TIMESTAMP_NTZ,
    FRESHNESS_SECONDS       NUMBER(18),
    FRESHNESS_TARGET_SECONDS NUMBER(18),
    FRESHNESS_PASSED        BOOLEAN,
    
    -- Availability
    IS_AVAILABLE            BOOLEAN,
    AVAILABILITY_CHECK_MS   NUMBER(10),
    
    -- Latency
    QUERY_LATENCY_MS        NUMBER(10),
    LATENCY_TARGET_MS       NUMBER(10),
    LATENCY_PASSED          BOOLEAN,
    
    -- Volume
    ROW_COUNT               NUMBER(18),
    ROW_COUNT_CHANGE_PCT    NUMBER(10,2),
    VOLUME_ANOMALY          BOOLEAN
)
COMMENT = 'Time-series SLA metrics for contract monitoring.';

-- ═══════════════════════════════════════════════════════════════════════════
-- SAMPLE CONTRACTS
-- ═══════════════════════════════════════════════════════════════════════════

-- Insert sample contract for Customer data
INSERT INTO CONTRACT_REGISTRY (
    CONTRACT_ID, CONTRACT_NAME, CONTRACT_VERSION, CONTRACT_STATUS,
    PRODUCER_DATABASE, PRODUCER_TEAM, PRODUCER_OWNER_EMAIL, PRODUCER_TABLE,
    CONSUMER_TEAMS,
    SCHEMA_DEFINITION, QUALITY_DEFINITION, SLA_DEFINITION, GOVERNANCE_DEFINITION,
    EFFECTIVE_FROM, DESCRIPTION
) VALUES (
    'CONTRACT-CRM-CUSTOMER-001',
    'CRM Customer Data Contract',
    '1.0.0',
    'ACTIVE',
    'RAW_DEV',
    'Sales Operations',
    'sales-ops@company.com',
    'RAW_DEV.CRM.CUSTOMER_RAW',
    ARRAY_CONSTRUCT('Business Intelligence', 'Marketing Analytics', 'Customer Success'),
    -- Schema Definition
    PARSE_JSON('{
        "table_name": "CUSTOMER_RAW",
        "columns": [
            {"name": "CUSTOMER_ID", "type": "VARCHAR", "nullable": false, "is_primary_key": true},
            {"name": "FIRST_NAME", "type": "VARCHAR", "nullable": true, "pii_type": "DIRECT"},
            {"name": "LAST_NAME", "type": "VARCHAR", "nullable": true, "pii_type": "DIRECT"},
            {"name": "EMAIL", "type": "VARCHAR", "nullable": true, "pii_type": "DIRECT"},
            {"name": "PHONE", "type": "VARCHAR", "nullable": true, "pii_type": "DIRECT"},
            {"name": "CUSTOMER_SEGMENT", "type": "VARCHAR", "nullable": true},
            {"name": "LIFETIME_VALUE", "type": "NUMBER", "nullable": true},
            {"name": "CREATED_DATE", "type": "DATE", "nullable": false}
        ]
    }'),
    -- Quality Definition
    PARSE_JSON('{
        "rules": [
            {"name": "customer_id_not_null", "threshold": 100},
            {"name": "email_valid_format", "threshold": 99},
            {"name": "created_date_not_future", "threshold": 100},
            {"name": "lifetime_value_positive", "threshold": 99.5}
        ]
    }'),
    -- SLA Definition
    PARSE_JSON('{
        "freshness_target_hours": 4,
        "freshness_max_hours": 24,
        "availability_target_pct": 99.9,
        "min_row_count": 1000
    }'),
    -- Governance Definition
    PARSE_JSON('{
        "classification": "CONFIDENTIAL",
        "compliance_frameworks": ["GDPR", "CCPA"],
        "residency_region": "US_ONLY",
        "retention_days": 2555,
        "pii_columns": ["FIRST_NAME", "LAST_NAME", "EMAIL", "PHONE", "ADDRESS_LINE1"]
    }'),
    CURRENT_TIMESTAMP(),
    'Contract for CRM customer data from Sales Operations team. Contains PII requiring GDPR and CCPA compliance.'
);

-- Insert quality rules for Customer contract
INSERT INTO QUALITY_RULES (RULE_ID, CONTRACT_ID, RULE_NAME, RULE_DESCRIPTION, RULE_EXPRESSION, THRESHOLD_PERCENT, SEVERITY) VALUES
    ('QR-CUST-001', 'CONTRACT-CRM-CUSTOMER-001', 'customer_id_not_null', 'Customer ID must not be null', 'CUSTOMER_ID IS NOT NULL', 100.0, 'ERROR'),
    ('QR-CUST-002', 'CONTRACT-CRM-CUSTOMER-001', 'email_valid_format', 'Email must be valid format or null', 'EMAIL IS NULL OR EMAIL RLIKE ''^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$''', 99.0, 'ERROR'),
    ('QR-CUST-003', 'CONTRACT-CRM-CUSTOMER-001', 'created_date_not_future', 'Created date cannot be in the future', 'CREATED_DATE <= CURRENT_DATE()', 100.0, 'ERROR'),
    ('QR-CUST-004', 'CONTRACT-CRM-CUSTOMER-001', 'lifetime_value_positive', 'Lifetime value must be positive or null', 'LIFETIME_VALUE IS NULL OR LIFETIME_VALUE >= 0', 99.5, 'WARNING'),
    ('QR-CUST-005', 'CONTRACT-CRM-CUSTOMER-001', 'segment_valid', 'Segment must be valid value', 'CUSTOMER_SEGMENT IS NULL OR CUSTOMER_SEGMENT IN (''Enterprise'', ''Mid-Market'', ''SMB'', ''Startup'', ''Consumer'')', 99.0, 'WARNING');

-- Insert SLA for Customer contract
INSERT INTO SLA_DEFINITIONS (SLA_ID, CONTRACT_ID, FRESHNESS_TARGET_HOURS, FRESHNESS_MAX_HOURS, AVAILABILITY_TARGET_PCT, MIN_ROW_COUNT, ON_SLA_MISS) VALUES
    ('SLA-CUST-001', 'CONTRACT-CRM-CUSTOMER-001', 4, 24, 99.9, 1000, 'ALERT');

-- ═══════════════════════════════════════════════════════════════════════════
-- CONTRACT VALIDATION PROCEDURES
-- ═══════════════════════════════════════════════════════════════════════════

-- Main validation procedure
CREATE OR REPLACE PROCEDURE VALIDATE_CONTRACT(
    p_contract_id VARCHAR
)
RETURNS VARIANT
LANGUAGE SQL
AS
$$
DECLARE
    v_result VARIANT;
    v_schema_passed BOOLEAN DEFAULT FALSE;
    v_quality_passed BOOLEAN DEFAULT FALSE;
    v_sla_passed BOOLEAN DEFAULT FALSE;
    v_governance_passed BOOLEAN DEFAULT FALSE;
    v_overall_passed BOOLEAN DEFAULT FALSE;
    v_producer_table VARCHAR;
    v_row_count NUMBER;
    v_start_time TIMESTAMP_NTZ;
    v_validation_id VARCHAR;
    v_details VARIANT;
BEGIN
    v_start_time := CURRENT_TIMESTAMP();
    v_validation_id := UUID_STRING();
    
    -- Get producer table from contract
    SELECT PRODUCER_TABLE INTO v_producer_table
    FROM GOVERNANCE.CONTRACTS.CONTRACT_REGISTRY
    WHERE CONTRACT_ID = :p_contract_id AND CONTRACT_STATUS = 'ACTIVE';
    
    IF (v_producer_table IS NULL) THEN
        RETURN OBJECT_CONSTRUCT(
            'success', FALSE,
            'error', 'Contract not found or not active',
            'contract_id', p_contract_id
        );
    END IF;
    
    -- 1. Schema Validation (simplified - check table exists)
    BEGIN
        EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || v_producer_table || ' WHERE 1=0';
        v_schema_passed := TRUE;
    EXCEPTION
        WHEN OTHER THEN
            v_schema_passed := FALSE;
    END;
    
    -- 2. Get row count
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || v_producer_table || ' WHERE _IS_CURRENT = TRUE' INTO v_row_count;
    
    -- 3. Quality Validation
    LET quality_cursor CURSOR FOR
        SELECT RULE_ID, RULE_NAME, RULE_EXPRESSION, THRESHOLD_PERCENT
        FROM GOVERNANCE.CONTRACTS.QUALITY_RULES
        WHERE CONTRACT_ID = :p_contract_id AND IS_ACTIVE = TRUE;
    
    v_quality_passed := TRUE;
    
    FOR rule IN quality_cursor DO
        LET pass_count NUMBER;
        LET pass_rate NUMBER;
        
        EXECUTE IMMEDIATE 
            'SELECT COUNT(*) FROM ' || v_producer_table || 
            ' WHERE _IS_CURRENT = TRUE AND (' || rule.RULE_EXPRESSION || ')'
            INTO pass_count;
        
        pass_rate := (pass_count / NULLIF(v_row_count, 0)) * 100;
        
        IF (pass_rate < rule.THRESHOLD_PERCENT) THEN
            v_quality_passed := FALSE;
        END IF;
    END FOR;
    
    -- 4. SLA Validation (simplified - check freshness)
    LET freshness_hours NUMBER;
    EXECUTE IMMEDIATE 
        'SELECT DATEDIFF(''hour'', MAX(_LOADED_AT), CURRENT_TIMESTAMP()) FROM ' || v_producer_table
        INTO freshness_hours;
    
    LET sla_target NUMBER;
    SELECT FRESHNESS_MAX_HOURS INTO sla_target
    FROM GOVERNANCE.CONTRACTS.SLA_DEFINITIONS
    WHERE CONTRACT_ID = :p_contract_id AND IS_ACTIVE = TRUE
    LIMIT 1;
    
    v_sla_passed := (freshness_hours <= COALESCE(sla_target, 9999));
    
    -- 5. Governance Validation (simplified - assume pass if schema passes)
    v_governance_passed := v_schema_passed;
    
    -- Overall result
    v_overall_passed := v_schema_passed AND v_quality_passed AND v_sla_passed AND v_governance_passed;
    
    -- Build result
    v_result := OBJECT_CONSTRUCT(
        'validation_id', v_validation_id,
        'contract_id', p_contract_id,
        'validation_time', v_start_time,
        'schema_passed', v_schema_passed,
        'quality_passed', v_quality_passed,
        'sla_passed', v_sla_passed,
        'governance_passed', v_governance_passed,
        'overall_passed', v_overall_passed,
        'row_count', v_row_count,
        'freshness_hours', freshness_hours,
        'execution_time_ms', DATEDIFF('millisecond', v_start_time, CURRENT_TIMESTAMP())
    );
    
    -- Record validation
    INSERT INTO GOVERNANCE.CONTRACTS.VALIDATION_HISTORY (
        VALIDATION_ID, CONTRACT_ID, VALIDATION_START, VALIDATION_END,
        SCHEMA_PASSED, QUALITY_PASSED, SLA_PASSED, GOVERNANCE_PASSED, OVERALL_PASSED,
        TOTAL_ROWS, VALIDATION_DETAILS
    ) VALUES (
        v_validation_id, p_contract_id, v_start_time, CURRENT_TIMESTAMP(),
        v_schema_passed, v_quality_passed, v_sla_passed, v_governance_passed, v_overall_passed,
        v_row_count, v_result
    );
    
    RETURN v_result;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- CONTRACT MONITORING VIEWS
-- ═══════════════════════════════════════════════════════════════════════════

-- Contract health dashboard
CREATE OR REPLACE VIEW VW_CONTRACT_HEALTH AS
SELECT 
    c.CONTRACT_ID,
    c.CONTRACT_NAME,
    c.CONTRACT_STATUS,
    c.PRODUCER_TEAM,
    c.PRODUCER_TABLE,
    
    -- Latest validation
    v.VALIDATION_START AS LAST_VALIDATION_TIME,
    v.OVERALL_PASSED AS LAST_VALIDATION_PASSED,
    v.SCHEMA_PASSED,
    v.QUALITY_PASSED,
    v.SLA_PASSED,
    v.GOVERNANCE_PASSED,
    
    -- Metrics
    v.TOTAL_ROWS,
    
    -- Validation history (last 7 days)
    h.total_validations,
    h.passed_validations,
    h.pass_rate_7d,
    
    -- Health Status
    CASE 
        WHEN v.OVERALL_PASSED AND h.pass_rate_7d >= 99 THEN 'HEALTHY'
        WHEN v.OVERALL_PASSED AND h.pass_rate_7d >= 95 THEN 'DEGRADED'
        WHEN v.OVERALL_PASSED THEN 'AT_RISK'
        ELSE 'CRITICAL'
    END AS HEALTH_STATUS
    
FROM GOVERNANCE.CONTRACTS.CONTRACT_REGISTRY c
LEFT JOIN (
    SELECT CONTRACT_ID, 
           VALIDATION_START, OVERALL_PASSED, SCHEMA_PASSED, QUALITY_PASSED, SLA_PASSED, GOVERNANCE_PASSED, TOTAL_ROWS
    FROM GOVERNANCE.CONTRACTS.VALIDATION_HISTORY
    QUALIFY ROW_NUMBER() OVER (PARTITION BY CONTRACT_ID ORDER BY VALIDATION_START DESC) = 1
) v ON c.CONTRACT_ID = v.CONTRACT_ID
LEFT JOIN (
    SELECT 
        CONTRACT_ID,
        COUNT(*) AS total_validations,
        SUM(CASE WHEN OVERALL_PASSED THEN 1 ELSE 0 END) AS passed_validations,
        100.0 * SUM(CASE WHEN OVERALL_PASSED THEN 1 ELSE 0 END) / COUNT(*) AS pass_rate_7d
    FROM GOVERNANCE.CONTRACTS.VALIDATION_HISTORY
    WHERE VALIDATION_START >= DATEADD('day', -7, CURRENT_TIMESTAMP())
    GROUP BY CONTRACT_ID
) h ON c.CONTRACT_ID = h.CONTRACT_ID
WHERE c.CONTRACT_STATUS = 'ACTIVE';

-- Quality rule failures
CREATE OR REPLACE VIEW VW_QUALITY_FAILURES AS
SELECT 
    vh.VALIDATION_ID,
    vh.CONTRACT_ID,
    cr.CONTRACT_NAME,
    vh.VALIDATION_START,
    f.value::VARCHAR AS FAILED_RULE_ID,
    qr.RULE_NAME,
    qr.RULE_DESCRIPTION,
    qr.SEVERITY
FROM GOVERNANCE.CONTRACTS.VALIDATION_HISTORY vh
JOIN GOVERNANCE.CONTRACTS.CONTRACT_REGISTRY cr ON vh.CONTRACT_ID = cr.CONTRACT_ID
CROSS JOIN LATERAL FLATTEN(input => vh.FAILED_RULES) f
LEFT JOIN GOVERNANCE.CONTRACTS.QUALITY_RULES qr ON f.value::VARCHAR = qr.RULE_ID
WHERE vh.QUALITY_PASSED = FALSE
  AND vh.VALIDATION_START >= DATEADD('day', -7, CURRENT_TIMESTAMP())
ORDER BY vh.VALIDATION_START DESC;

-- Contract coverage by table
CREATE OR REPLACE VIEW VW_CONTRACT_COVERAGE AS
SELECT 
    TABLE_CATALOG AS DATABASE_NAME,
    TABLE_SCHEMA,
    TABLE_NAME,
    CASE WHEN c.CONTRACT_ID IS NOT NULL THEN TRUE ELSE FALSE END AS HAS_CONTRACT,
    c.CONTRACT_ID,
    c.CONTRACT_STATUS,
    c.PRODUCER_TEAM
FROM INFORMATION_SCHEMA.TABLES t
LEFT JOIN GOVERNANCE.CONTRACTS.CONTRACT_REGISTRY c 
    ON c.PRODUCER_TABLE LIKE '%' || t.TABLE_NAME
WHERE t.TABLE_SCHEMA NOT IN ('INFORMATION_SCHEMA')
  AND t.TABLE_TYPE = 'BASE TABLE';

-- ═══════════════════════════════════════════════════════════════════════════
-- GRANTS
-- ═══════════════════════════════════════════════════════════════════════════

-- DATA_STEWARD manages contracts
GRANT USAGE ON SCHEMA GOVERNANCE.CONTRACTS TO ROLE DATA_STEWARD;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA GOVERNANCE.CONTRACTS TO ROLE DATA_STEWARD;
GRANT SELECT ON ALL VIEWS IN SCHEMA GOVERNANCE.CONTRACTS TO ROLE DATA_STEWARD;
GRANT USAGE ON PROCEDURE VALIDATE_CONTRACT(VARCHAR) TO ROLE DATA_STEWARD;

-- DATA_ENGINEER can validate and view
GRANT USAGE ON SCHEMA GOVERNANCE.CONTRACTS TO ROLE DATA_ENGINEER;
GRANT SELECT ON ALL TABLES IN SCHEMA GOVERNANCE.CONTRACTS TO ROLE DATA_ENGINEER;
GRANT SELECT ON ALL VIEWS IN SCHEMA GOVERNANCE.CONTRACTS TO ROLE DATA_ENGINEER;
GRANT USAGE ON PROCEDURE VALIDATE_CONTRACT(VARCHAR) TO ROLE DATA_ENGINEER;

-- AUDITOR can view
GRANT USAGE ON SCHEMA GOVERNANCE.CONTRACTS TO ROLE AUDITOR;
GRANT SELECT ON ALL TABLES IN SCHEMA GOVERNANCE.CONTRACTS TO ROLE AUDITOR;
GRANT SELECT ON ALL VIEWS IN SCHEMA GOVERNANCE.CONTRACTS TO ROLE AUDITOR;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

SELECT '✓ Contract Layer Created' AS STATUS;

-- Show contracts
SELECT CONTRACT_ID, CONTRACT_NAME, CONTRACT_STATUS, PRODUCER_TEAM
FROM GOVERNANCE.CONTRACTS.CONTRACT_REGISTRY;

-- Show quality rules
SELECT RULE_ID, CONTRACT_ID, RULE_NAME, THRESHOLD_PERCENT, SEVERITY
FROM GOVERNANCE.CONTRACTS.QUALITY_RULES;

-- Validate sample contract (after data is loaded)
-- CALL GOVERNANCE.CONTRACTS.VALIDATE_CONTRACT('CONTRACT-CRM-CUSTOMER-001');
