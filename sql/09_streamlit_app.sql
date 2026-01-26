-- ============================================================================
-- STREAMLIT APPLICATION DEPLOYMENT
-- ============================================================================
-- 
-- This script deploys the Streamlit in Snowflake (SiS) application.
-- The app provides:
--   1. Executive Dashboard
--   2. Cortex Analyst interface
--   3. Governance/RBAC demonstration
--   4. Data Product discovery
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
-- CREATE STREAMLIT APP
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- Note: The app.py file should be uploaded to the stage first:
-- PUT file://streamlit/app.py @SEM_DEV.STREAMLIT.STREAMLIT_STAGE AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
--
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE STREAMLIT DCA_DEMO_APP
    ROOT_LOCATION = '@SEM_DEV.STREAMLIT.STREAMLIT_STAGE'
    MAIN_FILE = 'app.py'
    QUERY_WAREHOUSE = ANALYTICS_WH
    COMMENT = 'Snowflake Data Cloud Architecture Demo Application';

-- Grant access to the Streamlit app
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
    'To access the app:' AS INFO,
    '1. Navigate to Projects > Streamlit in Snowsight' AS STEP_1,
    '2. Select DCA_DEMO_APP' AS STEP_2,
    '3. Switch roles in the sidebar to see RBAC in action' AS STEP_3;
