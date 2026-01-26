-- ============================================================================
-- STREAMLIT APPLICATION - Multi-Source System Demo
-- ============================================================================
-- 
-- This script deploys the Streamlit in Snowflake (SiS) application.
-- The app provides:
--   1. Source System Explorer - Browse data from SAP, Salesforce, FHIR, etc.
--   2. Cortex Analyst Interface - Natural language queries
--   3. Governance Dashboard - RBAC and masking demonstration
--   4. Contract Health Monitor - Data quality tracking
--   5. Data Product Catalog - Self-service discovery
--
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE SEM_DEV;
USE SCHEMA SEM_DEV.STREAMLIT;
USE WAREHOUSE ANALYTICS_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- CREATE STAGE FOR STREAMLIT APP
-- ═══════════════════════════════════════════════════════════════════════════

CREATE STAGE IF NOT EXISTS STREAMLIT_STAGE
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Stage for Streamlit application files';

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPER VIEWS FOR STREAMLIT APP
-- ═══════════════════════════════════════════════════════════════════════════

-- View: Available Source Systems
CREATE OR REPLACE VIEW SEM_DEV.STREAMLIT.VW_SOURCE_SYSTEMS AS
SELECT 
    TABLE_SCHEMA AS SOURCE_SYSTEM,
    COUNT(*) AS TABLE_COUNT,
    SUM(ROW_COUNT) AS TOTAL_ROWS
FROM RAW_DEV.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA NOT IN ('INFORMATION_SCHEMA', 'STAGING')
  AND TABLE_TYPE = 'BASE TABLE'
  AND TABLE_NAME NOT LIKE '%_TEMPLATE'
GROUP BY TABLE_SCHEMA
ORDER BY SOURCE_SYSTEM;

-- View: Source System Tables
CREATE OR REPLACE VIEW SEM_DEV.STREAMLIT.VW_SOURCE_TABLES AS
SELECT 
    TABLE_SCHEMA AS SOURCE_SYSTEM,
    TABLE_NAME,
    ROW_COUNT,
    CREATED AS CREATED_AT,
    LAST_ALTERED AS LAST_MODIFIED
FROM RAW_DEV.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA NOT IN ('INFORMATION_SCHEMA', 'STAGING')
  AND TABLE_TYPE = 'BASE TABLE'
  AND TABLE_NAME NOT LIKE '%_TEMPLATE'
ORDER BY TABLE_SCHEMA, TABLE_NAME;

-- View: Curated Layer Objects
CREATE OR REPLACE VIEW SEM_DEV.STREAMLIT.VW_CURATED_OBJECTS AS
SELECT 
    TABLE_SCHEMA,
    TABLE_NAME,
    CASE 
        WHEN TABLE_NAME LIKE 'DIM_%' THEN 'DIMENSION'
        WHEN TABLE_NAME LIKE 'FACT_%' THEN 'FACT'
        WHEN TABLE_NAME LIKE 'AGG_%' THEN 'AGGREGATE'
        ELSE 'OTHER'
    END AS OBJECT_TYPE,
    ROW_COUNT,
    CREATED AS CREATED_AT
FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
WHERE TABLE_TYPE IN ('BASE TABLE', 'DYNAMIC TABLE')
ORDER BY TABLE_SCHEMA, OBJECT_TYPE, TABLE_NAME;

-- View: Contract Health Summary
CREATE OR REPLACE VIEW SEM_DEV.STREAMLIT.VW_CONTRACT_STATUS AS
SELECT 
    SOURCE_SYSTEM,
    COUNT(*) AS TOTAL_CONTRACTS,
    SUM(CASE WHEN HEALTH_STATUS = 'HEALTHY' THEN 1 ELSE 0 END) AS HEALTHY,
    SUM(CASE WHEN HEALTH_STATUS = 'SLA_DEGRADED' THEN 1 ELSE 0 END) AS SLA_ISSUES,
    SUM(CASE WHEN HEALTH_STATUS = 'QUALITY_ISSUES' THEN 1 ELSE 0 END) AS QUALITY_ISSUES,
    SUM(CASE WHEN HEALTH_STATUS = 'CRITICAL' THEN 1 ELSE 0 END) AS CRITICAL
FROM GOVERNANCE.CONTRACTS.VW_CONTRACT_HEALTH
GROUP BY SOURCE_SYSTEM
ORDER BY SOURCE_SYSTEM;

-- View: Role Access Summary
CREATE OR REPLACE VIEW SEM_DEV.STREAMLIT.VW_ROLE_ACCESS AS
SELECT 
    GRANTEE AS ROLE_NAME,
    COUNT(DISTINCT OBJECT_NAME) AS ACCESSIBLE_OBJECTS,
    LISTAGG(DISTINCT PRIVILEGE, ', ') WITHIN GROUP (ORDER BY PRIVILEGE) AS PRIVILEGES
FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES
WHERE DELETED_ON IS NULL
  AND GRANTED_ON IN ('TABLE', 'VIEW', 'DYNAMIC_TABLE')
  AND GRANTEE IN ('DATA_ADMIN', 'DATA_ENGINEER', 'DATA_STEWARD', 'ANALYST', 'MANAGER', 'VIEWER')
GROUP BY GRANTEE
ORDER BY ROLE_NAME;

-- ═══════════════════════════════════════════════════════════════════════════
-- STREAMLIT APP CONFIGURATION TABLE
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS SEM_DEV.STREAMLIT.APP_CONFIG (
    CONFIG_KEY          VARCHAR(100) PRIMARY KEY,
    CONFIG_VALUE        VARIANT,
    DESCRIPTION         VARCHAR(500),
    UPDATED_AT          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Insert default configuration
INSERT INTO SEM_DEV.STREAMLIT.APP_CONFIG (CONFIG_KEY, CONFIG_VALUE, DESCRIPTION) VALUES
    ('SOURCE_SYSTEMS', PARSE_JSON('["SAP", "SALESFORCE", "ORACLE", "FHIR", "WORKDAY", "SERVICENOW"]'), 'Supported source systems'),
    ('DEFAULT_PAGE', PARSE_JSON('"Source Explorer"'), 'Default landing page'),
    ('CORTEX_MODEL', PARSE_JSON('"claude-3-5-sonnet"'), 'Cortex Analyst model to use'),
    ('DEMO_ROLES', PARSE_JSON('["DATA_ADMIN", "DATA_ENGINEER", "ANALYST", "MANAGER", "VIEWER", "EXTERNAL_PARTNER"]'), 'Roles for RBAC demo')
ON CONFLICT (CONFIG_KEY) DO NOTHING;

-- ═══════════════════════════════════════════════════════════════════════════
-- CREATE STREAMLIT APP
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE STREAMLIT DCA_DEMO_APP
    ROOT_LOCATION = '@SEM_DEV.STREAMLIT.STREAMLIT_STAGE'
    MAIN_FILE = 'app.py'
    QUERY_WAREHOUSE = ANALYTICS_WH
    COMMENT = 'Snowflake Data Cloud Architecture Demo - Multi-Source System Support';

-- Grant access to roles
GRANT USAGE ON STREAMLIT DCA_DEMO_APP TO ROLE DATA_ADMIN;
GRANT USAGE ON STREAMLIT DCA_DEMO_APP TO ROLE DATA_STEWARD;
GRANT USAGE ON STREAMLIT DCA_DEMO_APP TO ROLE DATA_ENGINEER;
GRANT USAGE ON STREAMLIT DCA_DEMO_APP TO ROLE ANALYST;
GRANT USAGE ON STREAMLIT DCA_DEMO_APP TO ROLE MANAGER;
GRANT USAGE ON STREAMLIT DCA_DEMO_APP TO ROLE VIEWER;

-- Grant access to helper views
GRANT SELECT ON ALL VIEWS IN SCHEMA SEM_DEV.STREAMLIT TO ROLE DATA_ADMIN;
GRANT SELECT ON ALL VIEWS IN SCHEMA SEM_DEV.STREAMLIT TO ROLE DATA_ENGINEER;
GRANT SELECT ON ALL VIEWS IN SCHEMA SEM_DEV.STREAMLIT TO ROLE ANALYST;
GRANT SELECT ON ALL VIEWS IN SCHEMA SEM_DEV.STREAMLIT TO ROLE MANAGER;
GRANT SELECT ON ALL VIEWS IN SCHEMA SEM_DEV.STREAMLIT TO ROLE VIEWER;

-- ═══════════════════════════════════════════════════════════════════════════
-- STREAMLIT APP PROCEDURES (for interactive features)
-- ═══════════════════════════════════════════════════════════════════════════

-- Procedure to sample data from any source system table
CREATE OR REPLACE PROCEDURE SEM_DEV.STREAMLIT.SAMPLE_SOURCE_DATA(
    p_source_system VARCHAR,
    p_table_name VARCHAR,
    p_limit NUMBER DEFAULT 100
)
RETURNS TABLE (data VARIANT)
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_sql VARCHAR;
    result RESULTSET;
BEGIN
    v_sql := 'SELECT OBJECT_CONSTRUCT(*) AS data FROM RAW_DEV.' || 
             UPPER(p_source_system) || '.' || UPPER(p_table_name) || 
             ' LIMIT ' || p_limit::VARCHAR;
    
    result := (EXECUTE IMMEDIATE v_sql);
    RETURN TABLE(result);
EXCEPTION
    WHEN OTHER THEN
        CREATE OR REPLACE TEMPORARY TABLE _error_result (data VARIANT);
        INSERT INTO _error_result VALUES (OBJECT_CONSTRUCT('error', SQLERRM));
        RETURN TABLE(SELECT * FROM _error_result);
END;
$$;

-- Procedure to get table schema
CREATE OR REPLACE PROCEDURE SEM_DEV.STREAMLIT.GET_TABLE_SCHEMA(
    p_source_system VARCHAR,
    p_table_name VARCHAR
)
RETURNS TABLE (column_name VARCHAR, data_type VARCHAR, is_nullable VARCHAR)
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    result RESULTSET;
BEGIN
    result := (
        SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE
        FROM RAW_DEV.INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = UPPER(p_source_system)
          AND TABLE_NAME = UPPER(p_table_name)
        ORDER BY ORDINAL_POSITION
    );
    RETURN TABLE(result);
END;
$$;

-- Procedure to run Cortex Analyst query
CREATE OR REPLACE PROCEDURE SEM_DEV.STREAMLIT.RUN_CORTEX_QUERY(
    p_semantic_view VARCHAR,
    p_question VARCHAR
)
RETURNS TABLE (answer VARCHAR, sql_query VARCHAR)
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    result RESULTSET;
BEGIN
    -- Note: This is a placeholder - actual Cortex Analyst integration
    -- would use SNOWFLAKE.CORTEX.COMPLETE or similar
    result := (
        SELECT 
            'Cortex Analyst would process: ' || p_question AS answer,
            'SELECT * FROM ' || p_semantic_view || ' LIMIT 10' AS sql_query
    );
    RETURN TABLE(result);
END;
$$;

-- Grant procedure access
GRANT USAGE ON PROCEDURE SEM_DEV.STREAMLIT.SAMPLE_SOURCE_DATA(VARCHAR, VARCHAR, NUMBER) TO ROLE ANALYST;
GRANT USAGE ON PROCEDURE SEM_DEV.STREAMLIT.GET_TABLE_SCHEMA(VARCHAR, VARCHAR) TO ROLE ANALYST;
GRANT USAGE ON PROCEDURE SEM_DEV.STREAMLIT.RUN_CORTEX_QUERY(VARCHAR, VARCHAR) TO ROLE ANALYST;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

SELECT '✓ Streamlit App Created' AS STATUS;

SHOW STREAMLITS IN SCHEMA SEM_DEV.STREAMLIT;

SELECT 
    'App Features:' AS INFO,
    '1. Source System Explorer (SAP, Salesforce, FHIR, Workday, ServiceNow)' AS FEATURE_1,
    '2. Dynamic Table/Schema Viewer' AS FEATURE_2,
    '3. Cortex Analyst Interface' AS FEATURE_3,
    '4. RBAC Demo with Role Switching' AS FEATURE_4,
    '5. Contract Health Dashboard' AS FEATURE_5;

SELECT 
    'Upload app.py to stage:' AS STEP_1,
    'PUT file://streamlit/app.py @SEM_DEV.STREAMLIT.STREAMLIT_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;' AS COMMAND;
