-- ============================================================================
-- CLEANUP SCRIPT - Complete Demo Teardown
-- ============================================================================
-- 
-- WARNING: This script removes ALL demo objects including:
--   - Databases (GOVERNANCE, RAW_DEV, CURATED_DEV, SEM_DEV)
--   - Warehouses (INGEST_WH, TRANSFORM_WH, ANALYTICS_WH, AI_WH)
--   - Roles (DATA_ADMIN, DATA_ENGINEER, DATA_STEWARD, etc.)
--   - Shares (SALES_ANALYTICS_SHARE, etc.)
--
-- RUN AS: ACCOUNTADMIN
-- ============================================================================

-- Confirm before running
SELECT 'WARNING: This will delete ALL demo objects!' AS MESSAGE;
SELECT 'Run each section manually to confirm.' AS INSTRUCTION;

-- ═══════════════════════════════════════════════════════════════════════════
-- UNCOMMENT AND RUN SECTIONS INDIVIDUALLY
-- ═══════════════════════════════════════════════════════════════════════════

USE ROLE ACCOUNTADMIN;

-- -----------------------------------------------------------------------------
-- DROP SHARES
-- -----------------------------------------------------------------------------
/*
DROP SHARE IF EXISTS SALES_ANALYTICS_SHARE;
DROP SHARE IF EXISTS OPERATIONS_ANALYTICS_SHARE;
*/

-- -----------------------------------------------------------------------------
-- DROP DATABASES
-- -----------------------------------------------------------------------------
/*
DROP DATABASE IF EXISTS SEM_DEV;
DROP DATABASE IF EXISTS CURATED_DEV;
DROP DATABASE IF EXISTS RAW_DEV;
DROP DATABASE IF EXISTS GOVERNANCE;
*/

-- -----------------------------------------------------------------------------
-- DROP WAREHOUSES
-- -----------------------------------------------------------------------------
/*
DROP WAREHOUSE IF EXISTS INGEST_WH;
DROP WAREHOUSE IF EXISTS TRANSFORM_WH;
DROP WAREHOUSE IF EXISTS ANALYTICS_WH;
DROP WAREHOUSE IF EXISTS AI_WH;
*/

-- -----------------------------------------------------------------------------
-- DROP ROLES (in reverse hierarchy order)
-- -----------------------------------------------------------------------------
/*
DROP ROLE IF EXISTS EXTERNAL_PARTNER;
DROP ROLE IF EXISTS VIEWER;
DROP ROLE IF EXISTS AUDITOR;
DROP ROLE IF EXISTS MANAGER;
DROP ROLE IF EXISTS ANALYST;
DROP ROLE IF EXISTS AI_AGENT;
DROP ROLE IF EXISTS ML_ENGINEER;
DROP ROLE IF EXISTS PII_VIEWER;
DROP ROLE IF EXISTS DATA_STEWARD;
DROP ROLE IF EXISTS DATA_ENGINEER;
DROP ROLE IF EXISTS DATA_ADMIN;
*/

-- -----------------------------------------------------------------------------
-- VERIFICATION
-- -----------------------------------------------------------------------------

SELECT '✓ Cleanup complete (if sections were uncommented)' AS STATUS;
