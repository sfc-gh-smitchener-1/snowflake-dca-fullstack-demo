-- ============================================================================
-- DATA CONTRACTS ON SNOWFLAKE HORIZON — 00 SETUP
-- ============================================================================
--
-- Creates the Horizon-native data-contract enforcement layer. Unlike the basic
-- GOVERNANCE.CONTRACTS schema (sql/08_contracts.sql), this layer composes real
-- Horizon primitives — Data Metric Functions, object tags, ACCOUNT_USAGE
-- lineage, and Alerts — into an enforceable contract with BLOCK vs ALERT gates.
--
-- Schema created:  GOVERNANCE.DATA_CONTRACTS
--
-- Design principle (see README.md):
--   A contract = producer's enforceable promise. The registry stores INTENT;
--   Horizon primitives provide ENFORCEMENT + EVIDENCE. This schema binds them.
--
-- Contract dimensions:
--   1. Schema   → INFORMATION_SCHEMA fingerprint + drift detection + tags
--   2. Quality  → Data Metric Functions (system + custom)
--   3. SLA      → FRESHNESS / ROW_COUNT DMFs + Alerts
--   4. Lineage  → OBJECT_DEPENDENCIES + ACCESS_HISTORY + Horizon Context
--   5. Access   → tag-driven masking / row access policies (references 07_governance.sql)
--
-- RUN AS: a role that can create schemas in GOVERNANCE and (for DMFs)
--         hold DATA_METRIC_USER / EXECUTE DATA METRIC FUNCTION. In this demo we
--         use DATA_ADMIN and grant the serverless DMF privileges from ACCOUNTADMIN.
-- ============================================================================

USE ROLE DATA_ADMIN;
USE WAREHOUSE TRANSFORM_WH;
USE DATABASE GOVERNANCE;

-- ----------------------------------------------------------------------------
-- Schema
-- ----------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS GOVERNANCE.DATA_CONTRACTS
    COMMENT = 'Horizon-native data contract enforcement: schema drift, DMF-backed quality, '
           || 'SLA/freshness alerts, cross-platform lineage assertions, and BLOCK/ALERT gates.';

USE SCHEMA GOVERNANCE.DATA_CONTRACTS;

-- ----------------------------------------------------------------------------
-- Contract-binding TAGS
-- These are the Horizon-native binding between physical objects and contracts.
-- Tags survive renames, propagate, and are queryable via ACCOUNT_USAGE.TAG_REFERENCES.
-- ----------------------------------------------------------------------------

-- Which contract governs this object
CREATE TAG IF NOT EXISTS TAG_CONTRACT_ID
    COMMENT = 'Binds a database object to a contract in DATA_CONTRACTS.CONTRACT_REGISTRY.';

-- The contract version currently applied to the object
CREATE TAG IF NOT EXISTS TAG_CONTRACT_VERSION
    COMMENT = 'Semantic version of the contract applied to this object (e.g. 1.0.0).';

-- Schema stability class — governs how breaking changes are handled
CREATE TAG IF NOT EXISTS TAG_SCHEMA_STABILITY
    ALLOWED_VALUES 'STABLE', 'EVOLVING', 'DEPRECATED'
    COMMENT = 'STABLE = no breaking changes without version bump; EVOLVING = additive changes allowed; DEPRECATED = scheduled for removal.';

-- Enforcement mode for the contract on this object
CREATE TAG IF NOT EXISTS TAG_CONTRACT_ENFORCEMENT
    ALLOWED_VALUES 'BLOCK', 'ALERT', 'MONITOR'
    COMMENT = 'BLOCK = fail pipeline on breach; ALERT = notify but pass; MONITOR = record only.';

-- ----------------------------------------------------------------------------
-- Grants for consuming roles (read access to contract state)
-- ----------------------------------------------------------------------------
GRANT USAGE ON SCHEMA GOVERNANCE.DATA_CONTRACTS TO ROLE DATA_STEWARD;
GRANT USAGE ON SCHEMA GOVERNANCE.DATA_CONTRACTS TO ROLE DATA_ENGINEER;

-- AUDITOR role exists in the base demo (sql/08_contracts.sql grants to it).
-- Guard with a conditional-free grant; if the role is absent, comment the next line.
GRANT USAGE ON SCHEMA GOVERNANCE.DATA_CONTRACTS TO ROLE AUDITOR;

-- ----------------------------------------------------------------------------
-- Serverless DMF prerequisites (run once, as ACCOUNTADMIN)
-- ----------------------------------------------------------------------------
-- Data Metric Functions run on serverless compute and require the executing
-- role to hold EXECUTE DATA METRIC FUNCTION and, for scheduling, the object
-- owner needs USAGE on the DMF. The demo grants these to DATA_ADMIN.
--
-- Uncomment and run these as ACCOUNTADMIN before deploying 02_dmf_library.sql:
--
--   USE ROLE ACCOUNTADMIN;
--   GRANT EXECUTE DATA METRIC FUNCTION ON ACCOUNT TO ROLE DATA_ADMIN;
--   GRANT DATABASE ROLE SNOWFLAKE.DATA_METRIC_USER TO ROLE DATA_ADMIN;
--   GRANT APPLICATION ROLE SNOWFLAKE.DATA_QUALITY_MONITORING_VIEWER TO ROLE DATA_ADMIN;
--   -- For freshness/row-count on ACCOUNT_USAGE:
--   GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE DATA_ADMIN;
--
-- ----------------------------------------------------------------------------

SELECT '✓ GOVERNANCE.DATA_CONTRACTS schema + binding tags created' AS STATUS;
