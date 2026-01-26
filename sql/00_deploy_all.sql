-- ============================================================================
-- MASTER DEPLOYMENT ORCHESTRATOR
-- ============================================================================
-- 
-- This script deploys the complete Snowflake DCA demo in sequence.
-- Run this script AS ACCOUNTADMIN for the initial setup.
--
-- Deployment Order:
--   1. 01_setup.sql      - Roles, warehouses, databases, tags
--   2. 03_raw_layer.sql  - RAW tables with SCD Type 2
--   3. 04_load_data.sql  - Load synthetic data (or generate)
--   4. 05_curated_layer.sql - Dynamic Tables
--   5. 06_semantic_layer.sql - Semantic Views
--   6. 07_governance.sql - Masking and row access policies
--   7. 08_observability.sql - Monitoring views
--   8. 09_streamlit_app.sql - Streamlit deployment
--   9. 10_marketplace.sql - Data products
--
-- PREREQUISITES:
--   - ACCOUNTADMIN role access
--   - Cortex enabled on the account
--   - Git integration (if using Git-based deployment)
--
-- ============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- PRE-FLIGHT CHECK
-- ═══════════════════════════════════════════════════════════════════════════

USE ROLE ACCOUNTADMIN;

SELECT 
    '=== SNOWFLAKE DCA FULL STACK DEMO ===' AS DEPLOYMENT_START,
    CURRENT_TIMESTAMP() AS TIMESTAMP,
    CURRENT_ACCOUNT() AS ACCOUNT,
    CURRENT_USER() AS DEPLOYING_USER;

-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 1: INITIAL SETUP
-- ═══════════════════════════════════════════════════════════════════════════

-- 'Step 1: Running 01_setup.sql - Roles, warehouses, databases, tags...';

-- If running from Git repository:
-- EXECUTE IMMEDIATE FROM @dca_demo_repo/branches/main/sql/01_setup.sql;

-- If running scripts individually, ensure 01_setup.sql has been run

-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 2: RAW LAYER
-- ═══════════════════════════════════════════════════════════════════════════

-- 'Step 2: Running 03_raw_layer.sql - RAW tables with SCD Type 2...';

-- EXECUTE IMMEDIATE FROM @dca_demo_repo/branches/main/sql/03_raw_layer.sql;

-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 3: LOAD DATA
-- ═══════════════════════════════════════════════════════════════════════════

-- 'Step 3: Running 04_load_data.sql - Loading synthetic data...';

-- EXECUTE IMMEDIATE FROM @dca_demo_repo/branches/main/sql/04_load_data.sql;

-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 4: CURATED LAYER
-- ═══════════════════════════════════════════════════════════════════════════

-- 'Step 4: Running 05_curated_layer.sql - Dynamic Tables...';

-- EXECUTE IMMEDIATE FROM @dca_demo_repo/branches/main/sql/05_curated_layer.sql;

-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 5: SEMANTIC LAYER
-- ═══════════════════════════════════════════════════════════════════════════

-- 'Step 5: Running 06_semantic_layer.sql - Semantic Views...';

-- EXECUTE IMMEDIATE FROM @dca_demo_repo/branches/main/sql/06_semantic_layer.sql;

-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 6: GOVERNANCE POLICIES
-- ═══════════════════════════════════════════════════════════════════════════

-- 'Step 6: Running 07_governance.sql - Masking and row access...';

-- EXECUTE IMMEDIATE FROM @dca_demo_repo/branches/main/sql/07_governance.sql;

-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 7: MARKETPLACE
-- ═══════════════════════════════════════════════════════════════════════════

-- 'Step 7: Running 10_marketplace.sql - Data products...';

-- EXECUTE IMMEDIATE FROM @dca_demo_repo/branches/main/sql/10_marketplace.sql;

-- ═══════════════════════════════════════════════════════════════════════════
-- DEPLOYMENT COMPLETE
-- ═══════════════════════════════════════════════════════════════════════════

SELECT 
    '=== DEPLOYMENT COMPLETE ===' AS STATUS,
    CURRENT_TIMESTAMP() AS COMPLETED_AT;

SELECT 
    'Next Steps:' AS INFO,
    '1. Generate synthetic data: python tools/data_generator.py --output data' AS STEP_1,
    '2. Upload to stage: PUT file://data/*.csv @RAW_DEV.STAGING.DATA_STAGE' AS STEP_2,
    '3. Load data: Run sql/04_load_data.sql' AS STEP_3,
    '4. Launch Streamlit: Navigate to Projects > Streamlit' AS STEP_4;
