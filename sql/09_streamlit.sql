-- ============================================================================
-- STREAMLIT DEPLOYMENT - DDL and App Creation
-- ============================================================================
-- 
-- This script creates the complete Streamlit deployment:
--   1. Helper views for source system exploration
--   2. Configuration tables
--   3. Stored procedures for data access
--   4. Stage for Streamlit files
--   5. Native Streamlit application
--
-- PREREQUISITE: Upload app.py to the STREAMLIT_STAGE (see instructions at end)
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE SEM_DEV;
USE WAREHOUSE ANALYTICS_WH;

-- Create schema if not exists
CREATE SCHEMA IF NOT EXISTS SEM_DEV.STREAMLIT
    COMMENT = 'Schema for Streamlit application objects';

USE SCHEMA SEM_DEV.STREAMLIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 1: CREATE STAGE FOR STREAMLIT APP
-- ═══════════════════════════════════════════════════════════════════════════

CREATE STAGE IF NOT EXISTS STREAMLIT_STAGE
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Stage for Streamlit application files';

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 2: HELPER VIEWS FOR STREAMLIT APP
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

-- View: Semantic Views Available
CREATE OR REPLACE VIEW SEM_DEV.STREAMLIT.VW_SEMANTIC_VIEWS AS
SELECT 
    TABLE_SCHEMA AS SOURCE_SYSTEM,
    TABLE_NAME AS VIEW_NAME,
    COMMENT AS DESCRIPTION,
    CREATED AS CREATED_AT
FROM SEM_DEV.INFORMATION_SCHEMA.VIEWS
WHERE TABLE_SCHEMA NOT IN ('INFORMATION_SCHEMA', 'STREAMLIT', 'CONFIG')
ORDER BY TABLE_SCHEMA, TABLE_NAME;

-- View: Contract Health Summary (with fallback if contracts not created)
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

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 3: STREAMLIT APP CONFIGURATION TABLE
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS SEM_DEV.STREAMLIT.APP_CONFIG (
    CONFIG_KEY          VARCHAR(100) PRIMARY KEY,
    CONFIG_VALUE        VARIANT,
    DESCRIPTION         VARCHAR(500),
    UPDATED_AT          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Insert default configuration using INSERT...SELECT for PARSE_JSON
INSERT INTO SEM_DEV.STREAMLIT.APP_CONFIG (CONFIG_KEY, CONFIG_VALUE, DESCRIPTION)
SELECT 'SOURCE_SYSTEMS', PARSE_JSON('["SAP", "SALESFORCE", "ORACLE", "FHIR", "WORKDAY", "SERVICENOW"]'), 'Supported source systems'
WHERE NOT EXISTS (SELECT 1 FROM SEM_DEV.STREAMLIT.APP_CONFIG WHERE CONFIG_KEY = 'SOURCE_SYSTEMS');

INSERT INTO SEM_DEV.STREAMLIT.APP_CONFIG (CONFIG_KEY, CONFIG_VALUE, DESCRIPTION)
SELECT 'DEFAULT_PAGE', PARSE_JSON('"Source Explorer"'), 'Default landing page'
WHERE NOT EXISTS (SELECT 1 FROM SEM_DEV.STREAMLIT.APP_CONFIG WHERE CONFIG_KEY = 'DEFAULT_PAGE');

INSERT INTO SEM_DEV.STREAMLIT.APP_CONFIG (CONFIG_KEY, CONFIG_VALUE, DESCRIPTION)
SELECT 'CORTEX_MODEL', PARSE_JSON('"claude-3-5-sonnet"'), 'Cortex Analyst model to use'
WHERE NOT EXISTS (SELECT 1 FROM SEM_DEV.STREAMLIT.APP_CONFIG WHERE CONFIG_KEY = 'CORTEX_MODEL');

INSERT INTO SEM_DEV.STREAMLIT.APP_CONFIG (CONFIG_KEY, CONFIG_VALUE, DESCRIPTION)
SELECT 'DEMO_ROLES', PARSE_JSON('["DATA_ADMIN", "DATA_ENGINEER", "ANALYST", "MANAGER", "VIEWER", "EXTERNAL_PARTNER"]'), 'Roles for RBAC demo'
WHERE NOT EXISTS (SELECT 1 FROM SEM_DEV.STREAMLIT.APP_CONFIG WHERE CONFIG_KEY = 'DEMO_ROLES');

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 4: STREAMLIT APP PROCEDURES (for interactive features)
-- ═══════════════════════════════════════════════════════════════════════════

-- Procedure to sample data from any source system table
CREATE OR REPLACE PROCEDURE SEM_DEV.STREAMLIT.SAMPLE_SOURCE_DATA(
    P_SOURCE_SYSTEM VARCHAR,
    P_TABLE_NAME VARCHAR
)
RETURNS VARIANT
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    try {
        var sql = "SELECT OBJECT_CONSTRUCT(*) AS data FROM RAW_DEV." + 
                  P_SOURCE_SYSTEM.toUpperCase() + "." + P_TABLE_NAME.toUpperCase() + 
                  " LIMIT 100";
        
        var stmt = snowflake.createStatement({sqlText: sql});
        var rs = stmt.execute();
        
        var results = [];
        while (rs.next()) {
            results.push(rs.getColumnValue(1));
        }
        
        return {success: true, row_count: results.length, data: results};
    } catch (err) {
        return {success: false, error: err.message};
    }
$$;

-- Procedure to get table schema
CREATE OR REPLACE PROCEDURE SEM_DEV.STREAMLIT.GET_TABLE_SCHEMA(
    P_SOURCE_SYSTEM VARCHAR,
    P_TABLE_NAME VARCHAR
)
RETURNS VARIANT
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    try {
        var sql = "SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE " +
                  "FROM RAW_DEV.INFORMATION_SCHEMA.COLUMNS " +
                  "WHERE TABLE_SCHEMA = '" + P_SOURCE_SYSTEM.toUpperCase() + "' " +
                  "AND TABLE_NAME = '" + P_TABLE_NAME.toUpperCase() + "' " +
                  "ORDER BY ORDINAL_POSITION";
        
        var stmt = snowflake.createStatement({sqlText: sql});
        var rs = stmt.execute();
        
        var columns = [];
        while (rs.next()) {
            columns.push({
                column_name: rs.getColumnValue(1),
                data_type: rs.getColumnValue(2),
                is_nullable: rs.getColumnValue(3)
            });
        }
        
        return {success: true, column_count: columns.length, columns: columns};
    } catch (err) {
        return {success: false, error: err.message};
    }
$$;

-- Procedure to get curated layer stats
CREATE OR REPLACE PROCEDURE SEM_DEV.STREAMLIT.GET_CURATED_STATS(
    P_SOURCE_SYSTEM VARCHAR
)
RETURNS VARIANT
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    try {
        var sql = "SELECT TABLE_NAME, ROW_COUNT " +
                  "FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES " +
                  "WHERE TABLE_SCHEMA = '" + P_SOURCE_SYSTEM.toUpperCase() + "' " +
                  "AND TABLE_TYPE IN ('BASE TABLE', 'DYNAMIC TABLE')";
        
        var stmt = snowflake.createStatement({sqlText: sql});
        var rs = stmt.execute();
        
        var tables = [];
        var totalRows = 0;
        while (rs.next()) {
            var rowCount = rs.getColumnValue(2) || 0;
            tables.push({
                table_name: rs.getColumnValue(1),
                row_count: rowCount
            });
            totalRows += rowCount;
        }
        
        return {
            success: true, 
            source_system: P_SOURCE_SYSTEM.toUpperCase(),
            table_count: tables.length, 
            total_rows: totalRows,
            tables: tables
        };
    } catch (err) {
        return {success: false, error: err.message};
    }
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 5: CREATE STREAMLIT APP
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE STREAMLIT DCA_DEMO_APP
    ROOT_LOCATION = '@SEM_DEV.STREAMLIT.STREAMLIT_STAGE'
    MAIN_FILE = 'app.py'
    QUERY_WAREHOUSE = ANALYTICS_WH
    COMMENT = 'Snowflake Data Cloud Architecture Demo - Multi-Source System Support';

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 6: GRANTS
-- ═══════════════════════════════════════════════════════════════════════════

-- Grant schema access
GRANT USAGE ON SCHEMA SEM_DEV.STREAMLIT TO ROLE DATA_ADMIN;
GRANT USAGE ON SCHEMA SEM_DEV.STREAMLIT TO ROLE DATA_ENGINEER;
GRANT USAGE ON SCHEMA SEM_DEV.STREAMLIT TO ROLE DATA_STEWARD;
GRANT USAGE ON SCHEMA SEM_DEV.STREAMLIT TO ROLE ANALYST;
GRANT USAGE ON SCHEMA SEM_DEV.STREAMLIT TO ROLE MANAGER;
GRANT USAGE ON SCHEMA SEM_DEV.STREAMLIT TO ROLE VIEWER;

-- Grant view access
GRANT SELECT ON ALL VIEWS IN SCHEMA SEM_DEV.STREAMLIT TO ROLE DATA_ADMIN;
GRANT SELECT ON ALL VIEWS IN SCHEMA SEM_DEV.STREAMLIT TO ROLE DATA_ENGINEER;
GRANT SELECT ON ALL VIEWS IN SCHEMA SEM_DEV.STREAMLIT TO ROLE DATA_STEWARD;
GRANT SELECT ON ALL VIEWS IN SCHEMA SEM_DEV.STREAMLIT TO ROLE ANALYST;
GRANT SELECT ON ALL VIEWS IN SCHEMA SEM_DEV.STREAMLIT TO ROLE MANAGER;
GRANT SELECT ON ALL VIEWS IN SCHEMA SEM_DEV.STREAMLIT TO ROLE VIEWER;

-- Grant table access
GRANT SELECT ON ALL TABLES IN SCHEMA SEM_DEV.STREAMLIT TO ROLE DATA_ADMIN;
GRANT SELECT ON ALL TABLES IN SCHEMA SEM_DEV.STREAMLIT TO ROLE ANALYST;

-- Grant procedure access
GRANT USAGE ON PROCEDURE SEM_DEV.STREAMLIT.SAMPLE_SOURCE_DATA(VARCHAR, VARCHAR) TO ROLE ANALYST;
GRANT USAGE ON PROCEDURE SEM_DEV.STREAMLIT.GET_TABLE_SCHEMA(VARCHAR, VARCHAR) TO ROLE ANALYST;
GRANT USAGE ON PROCEDURE SEM_DEV.STREAMLIT.GET_CURATED_STATS(VARCHAR) TO ROLE ANALYST;

-- Grant Streamlit app access to roles
GRANT USAGE ON STREAMLIT DCA_DEMO_APP TO ROLE DATA_ADMIN;
GRANT USAGE ON STREAMLIT DCA_DEMO_APP TO ROLE DATA_STEWARD;
GRANT USAGE ON STREAMLIT DCA_DEMO_APP TO ROLE DATA_ENGINEER;
GRANT USAGE ON STREAMLIT DCA_DEMO_APP TO ROLE ANALYST;
GRANT USAGE ON STREAMLIT DCA_DEMO_APP TO ROLE MANAGER;
GRANT USAGE ON STREAMLIT DCA_DEMO_APP TO ROLE VIEWER;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

SELECT '✓ Streamlit Deployment Complete' AS STATUS;

SHOW STREAMLITS IN SCHEMA SEM_DEV.STREAMLIT;

SELECT 
    'App Features:' AS INFO,
    '1. Source System Explorer (SAP, Salesforce, Oracle, FHIR, Workday, ServiceNow)' AS FEATURE_1,
    '2. Dynamic Table/Schema Viewer' AS FEATURE_2,
    '3. Cortex Analyst Interface' AS FEATURE_3,
    '4. RBAC Demo with Role Switching' AS FEATURE_4,
    '5. Contract Health Dashboard' AS FEATURE_5;

-- ═══════════════════════════════════════════════════════════════════════════
-- UPLOAD INSTRUCTIONS
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- To upload the Streamlit app files:
--
-- 1. From SnowSQL or Snowflake UI:
--    PUT file://streamlit/app.py @SEM_DEV.STREAMLIT.STREAMLIT_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
--
-- 2. If you have additional files (environment.yml, pages/, etc.):
--    PUT file://streamlit/environment.yml @SEM_DEV.STREAMLIT.STREAMLIT_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
--    PUT file://streamlit/pages/*.py @SEM_DEV.STREAMLIT.STREAMLIT_STAGE/pages/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
--
-- 3. Verify files are uploaded:
--    LIST @SEM_DEV.STREAMLIT.STREAMLIT_STAGE;
--
-- 4. Access the app:
--    - Navigate to Snowsight > Projects > Streamlit
--    - Or use the direct URL from SHOW STREAMLITS output
--
-- ═══════════════════════════════════════════════════════════════════════════
