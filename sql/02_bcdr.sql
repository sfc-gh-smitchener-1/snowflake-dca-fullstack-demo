-- ============================================================================
-- BCDR LITE — BUSINESS CONTINUITY & DISASTER RECOVERY
-- ============================================================================
--
-- Establishes cross-region replication and client-redirect failover for
-- all objects created by the DCA fullstack demo (sql/ + Streamlit).
--
-- TOPOLOGY
--   Primary   : SNOW_BCDR_PRIMARY  (OAB74379)  AWS us-west-2
--   Secondary : SNOW_BCDR_SECONDARY (OZC55031) AWS us-east-1
--   Org       : SFSENORTHAMERICA
--
-- OBJECTS REPLICATED
--   Databases : GOVERNANCE, RAW_DEV, CURATED_DEV, SEM_DEV
--               (SEM_DEV.STREAMLIT is covered as part of SEM_DEV)
--   Git repo  : GOVERNANCE.LINEAGE.DCA_FULLSTACK_DEMO_REPO
--   Roles/WHs : Already covered by ICEBERG_BCDR_ACCOUNT_FG — no new group needed
--   Connection: DCA_DEMO_CONNECTION (client redirect for transparent failover)
--
-- EXISTING FAILOVER GROUPS (not modified, except account FG integration types)
--   ICEBERG_BCDR_ACCOUNT_FG — PARAMETERS, ROLES, USERS, WAREHOUSES,
--                              NETWORK POLICIES, INTEGRATIONS (10 min)
--   ICEBERG_BCDR_DB_FG      — Iceberg databases only (10 min)
--
-- SCRIPT STRUCTURE
--   PART 1  : PRIMARY  — Pre-flight verification
--   PART 2  : PRIMARY  — Git Repository
--   PART 3  : PRIMARY  — Extend account failover group (add GIT_REPOSITORIES)
--   PART 4  : PRIMARY  — DCA database failover group
--   PART 5  : PRIMARY  — Client-redirect Connection
--   PART 6  : SECONDARY — Replica failover group
--   PART 7  : SECONDARY — Replica Connection + initial refresh
--   PART 8  : BOTH     — Validation queries
--   PART 9  : BOTH     — Failover / Failback runbook (commented)
--
-- RUN AS: ACCOUNTADMIN on each account
-- CONNECTIONS: SNOW_BCDR_PRIMARY (Parts 1–5), SNOW_BCDR_SECONDARY (Parts 6–7)
-- PREREQ: 01_setup.sql must have been run on SNOW_BCDR_PRIMARY
--
-- ============================================================================


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 1 — PRIMARY ACCOUNT — PRE-FLIGHT VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════
-- Run as: ACCOUNTADMIN on SNOW_BCDR_PRIMARY

USE ROLE ACCOUNTADMIN;
USE DATABASE GOVERNANCE;
-- Verify we are on the correct account before making any changes.
-- Expected: ACCOUNT = OAB74379 | REGION = AWS_US_WEST_2 | ORG = SFSENORTHAMERICA
SELECT
    CURRENT_ACCOUNT()           AS ACCOUNT,
    CURRENT_REGION()            AS REGION,
    CURRENT_ORGANIZATION_NAME() AS ORG,
    CURRENT_USER()              AS DEPLOYING_USER,
    CURRENT_TIMESTAMP()         AS DEPLOYED_AT;

-- Verify prerequisite databases exist (created by 01_setup.sql)
SELECT
    DATABASE_NAME,
    DATABASE_OWNER,
    COMMENT
FROM INFORMATION_SCHEMA.DATABASES
WHERE DATABASE_NAME IN ('GOVERNANCE', 'RAW_DEV', 'CURATED_DEV', 'SEM_DEV')
ORDER BY DATABASE_NAME;

-- Verify prerequisite integration exists
SHOW API INTEGRATIONS LIKE 'GIT_API';


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 2 — PRIMARY ACCOUNT — GIT REPOSITORY
-- ═══════════════════════════════════════════════════════════════════════════
-- Creates the Snowflake Git Repository object that tracks the demo source
-- repo. Placed in GOVERNANCE.LINEAGE so it is replicated with the GOVERNANCE
-- database via DCA_BCDR_DB_FG (no separate integration step required).

USE DATABASE GOVERNANCE;
USE SCHEMA   GOVERNANCE.LINEAGE;

CREATE GIT REPOSITORY IF NOT EXISTS GOVERNANCE.LINEAGE.DCA_FULLSTACK_DEMO_REPO
    API_INTEGRATION = GIT_API
    ORIGIN          = 'https://github.com/sfc-gh-smitchener-1/snowflake-dca-fullstack-demo.git'
    COMMENT         = 'Source repository for the DCA fullstack demo — replicated via DCA_BCDR_DB_FG';

-- Fetch latest refs to verify connectivity
ALTER GIT REPOSITORY GOVERNANCE.LINEAGE.DCA_FULLSTACK_DEMO_REPO FETCH;

-- Show branches to confirm connection is healthy
SHOW GIT BRANCHES IN GIT REPOSITORY GOVERNANCE.LINEAGE.DCA_FULLSTACK_DEMO_REPO;


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 3 — SECONDARY ACCOUNT — GIT API INTEGRATION PREREQUISITE
-- ═══════════════════════════════════════════════════════════════════════════
-- The GIT REPOSITORY object replicates as a database-level object with the
-- GOVERNANCE database via DCA_BCDR_DB_FG — no account-level integration
-- replication is needed for that.
--
-- However, for Git Repository objects to be functional on the secondary
-- after failover, a GIT_API integration must exist there. Each account
-- manages its own Git credentials, so create it directly on the secondary
-- rather than replicating from primary.
--
-- Run this block on SNOW_BCDR_SECONDARY before the initial refresh:
--
--   USE ROLE ACCOUNTADMIN;
--   CREATE API INTEGRATION IF NOT EXISTS GIT_API
--       API_PROVIDER     = git_https_api
--       API_ALLOWED_PREFIXES = ('https://github.com/sfc-gh-smitchener-1/')
--       ENABLED          = TRUE
--       COMMENT          = 'Git API integration for DCA fullstack demo repo';
--
-- If the secondary already has a compatible GIT_API integration this step
-- can be skipped. Verify with: SHOW API INTEGRATIONS LIKE 'GIT_API';


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 4 — PRIMARY ACCOUNT — DCA DATABASE FAILOVER GROUP
-- ═══════════════════════════════════════════════════════════════════════════
-- Creates a dedicated failover group for the four DCA demo databases.
-- GOVERNANCE.LINEAGE.DCA_FULLSTACK_DEMO_REPO is a database object within
-- GOVERNANCE and is replicated automatically as part of that database.
--
-- Replication schedule is aligned with the existing Iceberg groups (10 min).

CREATE FAILOVER GROUP IF NOT EXISTS DCA_BCDR_DB_FG
    OBJECT_TYPES         = DATABASES
    ALLOWED_DATABASES    = GOVERNANCE, RAW_DEV, CURATED_DEV, SEM_DEV
    ALLOWED_ACCOUNTS     = SFSENORTHAMERICA.SNOW_BCDR_SECONDARY
    REPLICATION_SCHEDULE = '10 MINUTE'
    COMMENT              = 'Failover group for DCA fullstack demo — GOVERNANCE, RAW_DEV, CURATED_DEV, SEM_DEV (incl. SEM_DEV.STREAMLIT)';

-- Verify the group was created with the correct databases
SHOW FAILOVER GROUPS LIKE 'DCA_BCDR_DB_FG';


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 5 — PRIMARY ACCOUNT — CLIENT-REDIRECT CONNECTION
-- ═══════════════════════════════════════════════════════════════════════════
-- A Connection provides a stable DNS hostname that transparently redirects
-- clients to whichever account is currently primary — no connection string
-- changes needed during failover.

CREATE CONNECTION IF NOT EXISTS DCA_DEMO_CONNECTION
    COMMENT = 'Client-redirect connection for DCA fullstack demo BCDR — points to current primary account';

ALTER CONNECTION DCA_DEMO_CONNECTION
    ENABLE FAILOVER TO ACCOUNTS SFSENORTHAMERICA.SNOW_BCDR_SECONDARY;

-- Show the connection and its failover URL
SHOW CONNECTIONS LIKE 'DCA_DEMO_CONNECTION';


-- ============================================================================
-- ─────────────────────────────────────────────────────────────────────────────
-- SWITCH CONNECTION TO: SNOW_BCDR_SECONDARY (OZC55031 / AWS us-east-1)
-- ─────────────────────────────────────────────────────────────────────────────
-- Run Parts 6 and 7 as ACCOUNTADMIN on SNOW_BCDR_SECONDARY
-- ============================================================================


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 6 — SECONDARY ACCOUNT — REPLICA FAILOVER GROUP
-- ═══════════════════════════════════════════════════════════════════════════

USE ROLE ACCOUNTADMIN;

-- Verify we are on the correct account.
-- Expected: ACCOUNT = OZC55031 | REGION = AWS_US_EAST_1 | ORG = SFSENORTHAMERICA
SELECT
    CURRENT_ACCOUNT()           AS ACCOUNT,
    CURRENT_REGION()            AS REGION,
    CURRENT_ORGANIZATION_NAME() AS ORG;

-- Create the secondary replica of the DCA database failover group.
-- After this, Snowflake begins replicating on the 10-minute schedule.
CREATE FAILOVER GROUP IF NOT EXISTS SFSENORTHAMERICA.SNOW_BCDR_PRIMARY.DCA_BCDR_DB_FG
    AS REPLICA OF SFSENORTHAMERICA.SNOW_BCDR_PRIMARY.DCA_BCDR_DB_FG;

-- Verify replica was created
SHOW FAILOVER GROUPS LIKE 'DCA_BCDR_DB_FG';


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 7 — SECONDARY ACCOUNT — REPLICA CONNECTION + INITIAL REFRESH
-- ═══════════════════════════════════════════════════════════════════════════

-- Create replica of the client-redirect Connection on the secondary.
CREATE CONNECTION IF NOT EXISTS SFSENORTHAMERICA.SNOW_BCDR_PRIMARY.DCA_DEMO_CONNECTION
    AS REPLICA OF SFSENORTHAMERICA.SNOW_BCDR_PRIMARY.DCA_DEMO_CONNECTION;

-- Trigger an immediate refresh of the DCA DB group rather than waiting
-- for the first scheduled interval.
ALTER FAILOVER GROUP DCA_BCDR_DB_FG REFRESH;

-- Verify replicated databases are visible on secondary
SHOW DATABASES LIKE 'GOVERNANCE';
SHOW DATABASES LIKE 'RAW_DEV';
SHOW DATABASES LIKE 'CURATED_DEV';
SHOW DATABASES LIKE 'SEM_DEV';


-- ============================================================================
-- ─────────────────────────────────────────────────────────────────────────────
-- VALIDATION QUERIES — run on either account after replication is established
-- ─────────────────────────────────────────────────────────────────────────────
-- ============================================================================


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 8 — VALIDATION
-- ═══════════════════════════════════════════════════════════════════════════

-- 8a. Failover group status (run on PRIMARY)
SHOW FAILOVER GROUPS;

-- 8b. Connection status (run on PRIMARY)
SHOW CONNECTIONS;

-- 8c. Replication refresh history — last 10 runs for DCA group
--     Healthy: STATUS = 'SUCCEEDED', ERROR_COUNT = 0
SELECT
    REPLICATION_GROUP_NAME,
    PHASE_TIME,
    STATUS,
    ERROR_COUNT,
    BYTES_TRANSFERRED,
    OBJECT_COUNT
FROM SNOWFLAKE.ACCOUNT_USAGE.REPLICATION_GROUP_REFRESH_HISTORY
WHERE REPLICATION_GROUP_NAME = 'DCA_BCDR_DB_FG'
ORDER BY PHASE_TIME DESC
LIMIT 10;

-- 8d. Replication lag — compare primary snapshot time vs secondary refresh time
SELECT
    PRIMARY_SNAPSHOT_TIMESTAMP,
    LAST_REFRESH_COMPLETED_ON,
    DATEDIFF('minute',
             LAST_REFRESH_COMPLETED_ON,
             CURRENT_TIMESTAMP()) AS LAG_MINUTES
FROM SNOWFLAKE.ACCOUNT_USAGE.REPLICATION_GROUP_USAGE_HISTORY
WHERE REPLICATION_GROUP_NAME = 'DCA_BCDR_DB_FG'
ORDER BY PRIMARY_SNAPSHOT_TIMESTAMP DESC
LIMIT 5;

-- 8e. Verify Git Repository replicated (run on SECONDARY after refresh)
SHOW GIT REPOSITORIES IN DATABASE GOVERNANCE;

-- 8f. Verify replicated databases are SECONDARY kind (run on SECONDARY)
SELECT DATABASE_NAME, TYPE AS KIND, DATABASE_OWNER
FROM INFORMATION_SCHEMA.DATABASES
WHERE DATABASE_NAME IN ('GOVERNANCE', 'RAW_DEV', 'CURATED_DEV', 'SEM_DEV')
ORDER BY DATABASE_NAME;


-- ============================================================================
-- ─────────────────────────────────────────────────────────────────────────────
-- PART 9 — FAILOVER / FAILBACK RUNBOOK
-- ─────────────────────────────────────────────────────────────────────────────
-- Execute these steps manually when a failover or failback event occurs.
-- Each block is intentionally commented out to prevent accidental execution.
-- ============================================================================

/*
────────────────────────────────────────────────────────────────────────────
FAILOVER — Promote SECONDARY to PRIMARY
(Run on SNOW_BCDR_SECONDARY as ACCOUNTADMIN when primary is unavailable)
────────────────────────────────────────────────────────────────────────────

USE ROLE ACCOUNTADMIN;

-- 1. Promote the DCA database group — makes replicated databases writable
ALTER FAILOVER GROUP DCA_BCDR_DB_FG PRIMARY;

-- 2. Promote the account object group — makes roles/warehouses/integrations
--    writable on this account (shared with Iceberg BCDR)
ALTER FAILOVER GROUP ICEBERG_BCDR_ACCOUNT_FG PRIMARY;

-- 3. Redirect the client Connection to this account
ALTER CONNECTION DCA_DEMO_CONNECTION PRIMARY;

-- 4. Verify Connection now points here
SHOW CONNECTIONS LIKE 'DCA_DEMO_CONNECTION';

-- 5. Resume warehouses if suspended
ALTER WAREHOUSE INGEST_WH    RESUME IF SUSPENDED;
ALTER WAREHOUSE TRANSFORM_WH RESUME IF SUSPENDED;
ALTER WAREHOUSE ANALYTICS_WH RESUME IF SUSPENDED;
ALTER WAREHOUSE AI_WH        RESUME IF SUSPENDED;


────────────────────────────────────────────────────────────────────────────
FAILBACK — Return PRIMARY to SNOW_BCDR_PRIMARY after recovery
────────────────────────────────────────────────────────────────────────────

-- STEP A: On the recovered SNOW_BCDR_PRIMARY (now acting as secondary)
--         Refresh to pull in any writes made during the outage period.
USE ROLE ACCOUNTADMIN;  -- connect to SNOW_BCDR_PRIMARY

ALTER FAILOVER GROUP DCA_BCDR_DB_FG REFRESH;
ALTER FAILOVER GROUP ICEBERG_BCDR_ACCOUNT_FG REFRESH;

-- Verify refresh succeeded before promoting
SELECT REPLICATION_GROUP_NAME, STATUS, ERROR_COUNT
FROM SNOWFLAKE.ACCOUNT_USAGE.REPLICATION_GROUP_REFRESH_HISTORY
WHERE REPLICATION_GROUP_NAME IN ('DCA_BCDR_DB_FG', 'ICEBERG_BCDR_ACCOUNT_FG')
ORDER BY PHASE_TIME DESC LIMIT 4;


-- STEP B: On SNOW_BCDR_SECONDARY (current primary) — hand primary back
USE ROLE ACCOUNTADMIN;  -- connect to SNOW_BCDR_SECONDARY

ALTER FAILOVER GROUP DCA_BCDR_DB_FG PRIMARY;          -- returns to OAB74379
ALTER FAILOVER GROUP ICEBERG_BCDR_ACCOUNT_FG PRIMARY; -- returns to OAB74379
ALTER CONNECTION DCA_DEMO_CONNECTION PRIMARY;          -- redirects back

*/
