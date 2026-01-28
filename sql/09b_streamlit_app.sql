-- ============================================================================
-- STREAMLIT APP DEPLOYMENT - Native Streamlit in Snowflake
-- ============================================================================
-- 
-- This script creates the native Streamlit application in Snowflake.
-- PREREQUISITE: Run 09a_streamlit_ddl.sql first
-- PREREQUISITE: Upload app.py to the STREAMLIT_STAGE
--
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE SEM_DEV;
USE SCHEMA SEM_DEV.STREAMLIT;
USE WAREHOUSE ANALYTICS_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- CREATE STREAMLIT APP
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE STREAMLIT DCA_DEMO_APP
    ROOT_LOCATION = '@SEM_DEV.STREAMLIT.STREAMLIT_STAGE'
    MAIN_FILE = 'app.py'
    QUERY_WAREHOUSE = ANALYTICS_WH
    COMMENT = 'Snowflake Data Cloud Architecture Demo - Multi-Source System Support';

-- ═══════════════════════════════════════════════════════════════════════════
-- GRANT ACCESS TO ROLES
-- ═══════════════════════════════════════════════════════════════════════════

GRANT USAGE ON STREAMLIT DCA_DEMO_APP TO ROLE DATA_ADMIN;
GRANT USAGE ON STREAMLIT DCA_DEMO_APP TO ROLE DATA_STEWARD;
GRANT USAGE ON STREAMLIT DCA_DEMO_APP TO ROLE DATA_ENGINEER;
GRANT USAGE ON STREAMLIT DCA_DEMO_APP TO ROLE ANALYST;
GRANT USAGE ON STREAMLIT DCA_DEMO_APP TO ROLE MANAGER;
GRANT USAGE ON STREAMLIT DCA_DEMO_APP TO ROLE VIEWER;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

SELECT '✓ Streamlit App Created' AS STATUS;

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
