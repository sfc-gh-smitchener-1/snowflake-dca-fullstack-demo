-- ============================================================================
-- GIT INTEGRATION - Connect Repository to Snowflake
-- ============================================================================
-- 
-- This script sets up Git integration for automated deployments.
-- Once configured, changes pushed to the repository are automatically
-- available in Snowflake.
--
-- RUN AS: ACCOUNTADMIN
-- ============================================================================

USE ROLE ACCOUNTADMIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 1: CREATE API INTEGRATION FOR GIT
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- This integration allows Snowflake to communicate with GitHub.
-- Modify the API_ALLOWED_PREFIXES for your Git provider.
--
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE API INTEGRATION git_api_integration
    API_PROVIDER = git_https_api
    API_ALLOWED_PREFIXES = (
        'https://github.com/',
        'https://gitlab.com/',
        'https://bitbucket.org/'
    )
    ENABLED = TRUE
    COMMENT = 'API integration for Git repository access';

-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 2: CREATE SECRET FOR AUTHENTICATION (if private repo)
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- For private repositories, create a secret with a Personal Access Token.
-- Uncomment and modify the following if using a private repository.
--
-- ═══════════════════════════════════════════════════════════════════════════

/*
CREATE OR REPLACE SECRET git_secret
    TYPE = password
    USERNAME = 'your-github-username'
    PASSWORD = 'your-personal-access-token'
    COMMENT = 'GitHub authentication for private repository access';
*/

-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 3: CREATE GIT REPOSITORY
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- Connect to the repository containing the demo code.
-- Update ORIGIN to point to your repository URL.
--
-- ═══════════════════════════════════════════════════════════════════════════

USE DATABASE GOVERNANCE;
CREATE SCHEMA IF NOT EXISTS GIT;
USE SCHEMA GOVERNANCE.GIT;

-- For public repository:
CREATE OR REPLACE GIT REPOSITORY dca_fullstack_demo
    API_INTEGRATION = git_api_integration
    ORIGIN = 'https://github.com/YOUR_ORG/snowflake-dca-fullstack-demo.git'
    COMMENT = 'Snowflake DCA Full Stack Demo repository';

-- For private repository (uncomment and use this instead):
/*
CREATE OR REPLACE GIT REPOSITORY dca_fullstack_demo
    API_INTEGRATION = git_api_integration
    GIT_CREDENTIALS = git_secret
    ORIGIN = 'https://github.com/YOUR_ORG/snowflake-dca-fullstack-demo.git'
    COMMENT = 'Snowflake DCA Full Stack Demo repository (private)';
*/

-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 4: FETCH AND VERIFY
-- ═══════════════════════════════════════════════════════════════════════════

-- Fetch latest from remote
ALTER GIT REPOSITORY dca_fullstack_demo FETCH;

-- Show branches
SHOW GIT BRANCHES IN dca_fullstack_demo;

-- List files in main branch
LIST @dca_fullstack_demo/branches/main/;

-- List SQL files
LIST @dca_fullstack_demo/branches/main/sql/;

-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 5: EXECUTE SCRIPTS FROM REPOSITORY
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- Execute deployment scripts directly from the repository.
-- This enables GitOps-style deployments.
--
-- ═══════════════════════════════════════════════════════════════════════════

-- Example: Deploy complete demo
-- EXECUTE IMMEDIATE FROM @dca_fullstack_demo/branches/main/sql/00_deploy_all.sql;

-- Example: Deploy individual scripts
-- EXECUTE IMMEDIATE FROM @dca_fullstack_demo/branches/main/sql/01_setup.sql;
-- EXECUTE IMMEDIATE FROM @dca_fullstack_demo/branches/main/sql/03_raw_layer.sql;
-- EXECUTE IMMEDIATE FROM @dca_fullstack_demo/branches/main/sql/05_curated_layer.sql;

-- ═══════════════════════════════════════════════════════════════════════════
-- OPTIONAL: CREATE TASK FOR AUTO-SYNC
-- ═══════════════════════════════════════════════════════════════════════════
-- 
-- Create a scheduled task to periodically fetch from Git.
--
-- ═══════════════════════════════════════════════════════════════════════════

/*
CREATE OR REPLACE TASK git_sync_task
    WAREHOUSE = TRANSFORM_WH
    SCHEDULE = 'USING CRON 0 * * * * UTC'  -- Every hour
AS
    ALTER GIT REPOSITORY GOVERNANCE.GIT.dca_fullstack_demo FETCH;

ALTER TASK git_sync_task RESUME;
*/

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

SELECT '✓ Git Integration Configured' AS STATUS;

SHOW GIT REPOSITORIES IN SCHEMA GOVERNANCE.GIT;

SELECT 
    'To deploy from Git:' AS INFO,
    'EXECUTE IMMEDIATE FROM @dca_fullstack_demo/branches/main/sql/00_deploy_all.sql;' AS COMMAND;
