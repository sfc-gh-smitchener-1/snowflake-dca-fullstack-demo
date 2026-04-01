-- ============================================================================
-- BCDR LITE — BUSINESS CONTINUITY & DISASTER RECOVERY
-- ============================================================================
--
-- Establishes cross-region replication and client-redirect failover for
-- all objects created by the DCA fullstack demo (sql/ + Streamlit).
--
-- TOPOLOGY
--   Primary   : SNOW_BCDR_PRIMARY   (OAB74379)  AWS us-west-2
--   Secondary : SNOW_BCDR_SECONDARY (OZC55031)  AWS us-east-1
--   Org       : SFSENORTHAMERICA
--
-- OBJECTS REPLICATED
--   Databases : GOVERNANCE, RAW_DEV, CURATED_DEV, SEM_DEV
--               (SEM_DEV.STREAMLIT is covered as part of SEM_DEV)
--   Git repo  : GOVERNANCE.LINEAGE.DCA_FULLSTACK_DEMO_REPO
--               (database-level object — replicates with GOVERNANCE)
--   Roles/WHs : Already covered by ICEBERG_BCDR_ACCOUNT_FG — no new group needed
--   Connection: DCA_DEMO_CONNECTION (client redirect for transparent failover)
--
-- EXISTING FAILOVER GROUPS (not modified)
--   ICEBERG_BCDR_ACCOUNT_FG — PARAMETERS, ROLES, USERS, WAREHOUSES,
--                              NETWORK POLICIES, INTEGRATIONS (10 min)
--   ICEBERG_BCDR_DB_FG      — Iceberg databases only (10 min)
--
-- SCRIPT STRUCTURE
--   PART 1 : PRIMARY   — Pre-flight verification
--   PART 2 : PRIMARY   — Git Repository
--   PART 3 : PRIMARY   — DCA database failover group
--   PART 4 : PRIMARY   — Client-redirect Connection
--   PART 5 : SECONDARY — Pre-flight + GIT_API prerequisite
--   PART 6 : SECONDARY — Replica failover group
--   PART 7 : SECONDARY — Replica Connection + initial refresh
--   PART 8 : SECONDARY — Streamlit app warm standby
--   PART 9 : BOTH      — Validation queries
--   PART 10: BOTH      — Failover / Failback runbook (commented)
--
-- RUN AS   : ACCOUNTADMIN on each account
-- CONNECTIONS: SNOW_BCDR_PRIMARY (Parts 1–4), SNOW_BCDR_SECONDARY (Parts 5–8)
-- PREREQ   : 01_setup.sql must have been run on SNOW_BCDR_PRIMARY
--
-- ============================================================================


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 1 — PRIMARY ACCOUNT — PRE-FLIGHT VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

USE ROLE ACCOUNTADMIN;

-- Verify we are on the correct account before making any changes.
-- Expected: ACCOUNT = OAB74379 | REGION = AWS_US_WEST_2 | ORG = SFSENORTHAMERICA
SELECT
    CURRENT_ACCOUNT()           AS ACCOUNT,
    CURRENT_REGION()            AS REGION,
    CURRENT_ORGANIZATION_NAME() AS ORG,
    CURRENT_USER()              AS DEPLOYING_USER,
    CURRENT_TIMESTAMP()         AS DEPLOYED_AT;

-- Verify prerequisite databases exist (created by 01_setup.sql).
-- All four must be present before proceeding.
SHOW DATABASES LIKE 'GOVERNANCE';
SHOW DATABASES LIKE 'RAW_DEV';
SHOW DATABASES LIKE 'CURATED_DEV';
SHOW DATABASES LIKE 'SEM_DEV';

-- Verify the GIT_API integration exists (required by Part 2).
SHOW API INTEGRATIONS LIKE 'GIT_API';


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 2 — PRIMARY ACCOUNT — GIT REPOSITORY
-- ═══════════════════════════════════════════════════════════════════════════
-- Creates the Snowflake Git Repository object for the demo source repo.
-- Placed in GOVERNANCE.LINEAGE so it replicates with the GOVERNANCE database
-- via DCA_BCDR_DB_FG — no separate account-level integration step required.

USE DATABASE GOVERNANCE;
USE SCHEMA   GOVERNANCE.LINEAGE;

CREATE GIT REPOSITORY IF NOT EXISTS GOVERNANCE.LINEAGE.DCA_FULLSTACK_DEMO_REPO
    API_INTEGRATION = GIT_API
    ORIGIN          = 'https://github.com/sfc-gh-smitchener-1/snowflake-dca-fullstack-demo.git'
    COMMENT         = 'Source repository for the DCA fullstack demo — replicated via DCA_BCDR_DB_FG';

-- Fetch latest refs to verify connectivity.
ALTER GIT REPOSITORY GOVERNANCE.LINEAGE.DCA_FULLSTACK_DEMO_REPO FETCH;

-- Confirm connection is healthy.
SHOW GIT BRANCHES IN GIT REPOSITORY GOVERNANCE.LINEAGE.DCA_FULLSTACK_DEMO_REPO;


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 3 — PRIMARY ACCOUNT — DCA DATABASE FAILOVER GROUP
-- ═══════════════════════════════════════════════════════════════════════════
-- Dedicated failover group for the four DCA demo databases.
-- GOVERNANCE.LINEAGE.DCA_FULLSTACK_DEMO_REPO replicates automatically as a
-- database-level object within GOVERNANCE.
-- Schedule aligned with existing Iceberg groups (10 min).

CREATE FAILOVER GROUP IF NOT EXISTS DCA_BCDR_DB_FG
    OBJECT_TYPES         = DATABASES
    ALLOWED_DATABASES    = GOVERNANCE, RAW_DEV, CURATED_DEV, SEM_DEV
    ALLOWED_ACCOUNTS     = SFSENORTHAMERICA.SNOW_BCDR_SECONDARY
    REPLICATION_SCHEDULE = '10 MINUTE'
    COMMENT              = 'Failover group for DCA fullstack demo — GOVERNANCE, RAW_DEV, CURATED_DEV, SEM_DEV (incl. SEM_DEV.STREAMLIT)';

-- Verify the group was created.
SHOW FAILOVER GROUPS LIKE 'DCA_BCDR_DB_FG';


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 4 — PRIMARY ACCOUNT — CLIENT-REDIRECT CONNECTION
-- ═══════════════════════════════════════════════════════════════════════════
-- A Connection provides a stable DNS hostname that transparently redirects
-- clients to whichever account is currently primary — no connection string
-- changes are needed during failover.

CREATE CONNECTION IF NOT EXISTS DCA_DEMO_CONNECTION
    COMMENT = 'Client-redirect connection for DCA fullstack demo BCDR — points to current primary account';

ALTER CONNECTION DCA_DEMO_CONNECTION
    ENABLE FAILOVER TO ACCOUNTS SFSENORTHAMERICA.SNOW_BCDR_SECONDARY;

-- Show the connection and its failover URL.
SHOW CONNECTIONS LIKE 'DCA_DEMO_CONNECTION';


-- ============================================================================
-- ─────────────────────────────────────────────────────────────────────────────
-- SWITCH CONNECTION TO: SNOW_BCDR_SECONDARY (OZC55031 / AWS us-east-1)
-- ─────────────────────────────────────────────────────────────────────────────
-- Run Parts 5–7 as ACCOUNTADMIN on SNOW_BCDR_SECONDARY
-- ============================================================================


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 5 — SECONDARY ACCOUNT — PRE-FLIGHT + GIT_API PREREQUISITE
-- ═══════════════════════════════════════════════════════════════════════════

USE ROLE ACCOUNTADMIN;

-- Verify we are on the correct account.
-- Expected: ACCOUNT = OZC55031 | REGION = AWS_US_EAST_1 | ORG = SFSENORTHAMERICA
SELECT
    CURRENT_ACCOUNT()           AS ACCOUNT,
    CURRENT_REGION()            AS REGION,
    CURRENT_ORGANIZATION_NAME() AS ORG;

-- !! PRE-FLIGHT — DCA_BCDR_DB_FG from SNOW_BCDR_PRIMARY must appear below !!
-- If it is missing, return to SNOW_BCDR_PRIMARY and confirm Part 3 completed
-- successfully: SHOW FAILOVER GROUPS LIKE 'DCA_BCDR_DB_FG';
SHOW REPLICATION GROUPS;

-- GIT_API prerequisite:
-- Git Repository objects replicate as database-level objects with GOVERNANCE.
-- For them to be functional after failover, a GIT_API integration must exist
-- on this account. Each account manages its own Git credentials — create it
-- here directly rather than relying on replication from primary.
--
-- Skip this block if a compatible GIT_API integration already exists.
-- Verify with: SHOW API INTEGRATIONS LIKE 'GIT_API';
--
--   CREATE API INTEGRATION IF NOT EXISTS GIT_API
--       API_PROVIDER         = git_https_api
--       API_ALLOWED_PREFIXES = ('https://github.com/sfc-gh-smitchener-1/')
--       ENABLED              = TRUE
--       COMMENT              = 'Git API integration for DCA fullstack demo repo';


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 6 — SECONDARY ACCOUNT — REPLICA FAILOVER GROUP
-- ═══════════════════════════════════════════════════════════════════════════
-- PREREQ: DCA_BCDR_DB_FG must be visible in SHOW REPLICATION GROUPS above.

CREATE FAILOVER GROUP IF NOT EXISTS DCA_BCDR_DB_FG
    AS REPLICA OF SFSENORTHAMERICA.SNOW_BCDR_PRIMARY.DCA_BCDR_DB_FG;

-- Verify replica was created. secondary_state should show STARTED.
SHOW FAILOVER GROUPS LIKE 'DCA_BCDR_DB_FG';


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 7 — SECONDARY ACCOUNT — REPLICA CONNECTION + INITIAL REFRESH
-- ═══════════════════════════════════════════════════════════════════════════

-- Create replica of the client-redirect Connection on the secondary.
CREATE CONNECTION IF NOT EXISTS DCA_DEMO_CONNECTION
    AS REPLICA OF SFSENORTHAMERICA.SNOW_BCDR_PRIMARY.DCA_DEMO_CONNECTION;

-- !! ACCOUNT GUARD — confirm before running REFRESH !!
SELECT
    CURRENT_ACCOUNT()  AS CURRENT_ACCOUNT,
    CURRENT_REGION()   AS CURRENT_REGION,
    IFF(CURRENT_ACCOUNT() = 'OZC55031',
        'CORRECT ACCOUNT — safe to run REFRESH',
        '*** WRONG ACCOUNT — switch to SNOW_BCDR_SECONDARY before continuing ***'
    )                  AS ACCOUNT_CHECK;

-- Trigger an immediate refresh rather than waiting for the first scheduled run.
-- PREREQ: ACCOUNT_CHECK above must show 'CORRECT ACCOUNT'.
ALTER FAILOVER GROUP DCA_BCDR_DB_FG REFRESH;

-- Verify replicated databases are now visible on secondary.
SHOW DATABASES LIKE 'GOVERNANCE';
SHOW DATABASES LIKE 'RAW_DEV';
SHOW DATABASES LIKE 'CURATED_DEV';
SHOW DATABASES LIKE 'SEM_DEV';


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 8 — SECONDARY ACCOUNT — STREAMLIT APP WARM STANDBY
-- ═══════════════════════════════════════════════════════════════════════════
-- CREATE STREAMLIT is not a replicated object type, and SEM_DEV on the
-- secondary is read-only so the app cannot be created there directly.
--
-- BCDR_DEMO does not replicate from the primary — it is created here as a
-- native writable database on the secondary, solely to host the Streamlit app.
-- Its ROOT_LOCATION points at @SEM_DEV.STREAMLIT.STREAMLIT_STAGE, which
-- replicates with SEM_DEV on the 10-minute schedule. After failover SEM_DEV
-- becomes the primary (writable) and the same path continues to work — no
-- changes to the app are needed.

USE ROLE ACCOUNTADMIN;

-- Create a native (non-replicated) database on the secondary to host the app.
CREATE DATABASE IF NOT EXISTS BCDR_DEMO
    COMMENT = 'Native secondary database — hosts the DCA demo Streamlit warm standby. Not replicated from primary.';

CREATE SCHEMA IF NOT EXISTS BCDR_DEMO.STREAMLIT
    COMMENT = 'Streamlit warm standby for DCA fullstack demo.';

CREATE STREAMLIT IF NOT EXISTS BCDR_DEMO.STREAMLIT.DCA_DEMO_APP
    ROOT_LOCATION   = '@SEM_DEV.STREAMLIT.STREAMLIT_STAGE'
    MAIN_FILE       = 'app.py'
    QUERY_WAREHOUSE = ANALYTICS_WH
    COMMENT         = 'DCA fullstack demo — BCDR secondary warm standby. Mirrors SEM_DEV.STREAMLIT.DCA_DEMO_APP on primary.';

-- Mirror the grants from 09_streamlit.sql.
GRANT USAGE ON DATABASE BCDR_DEMO TO ROLE DATA_ADMIN;
GRANT USAGE ON DATABASE BCDR_DEMO TO ROLE DATA_ENGINEER;
GRANT USAGE ON DATABASE BCDR_DEMO TO ROLE DATA_STEWARD;
GRANT USAGE ON DATABASE BCDR_DEMO TO ROLE ANALYST;
GRANT USAGE ON DATABASE BCDR_DEMO TO ROLE MANAGER;
GRANT USAGE ON DATABASE BCDR_DEMO TO ROLE VIEWER;
GRANT USAGE ON SCHEMA BCDR_DEMO.STREAMLIT TO ROLE DATA_ADMIN;
GRANT USAGE ON SCHEMA BCDR_DEMO.STREAMLIT TO ROLE DATA_ENGINEER;
GRANT USAGE ON SCHEMA BCDR_DEMO.STREAMLIT TO ROLE DATA_STEWARD;
GRANT USAGE ON SCHEMA BCDR_DEMO.STREAMLIT TO ROLE ANALYST;
GRANT USAGE ON SCHEMA BCDR_DEMO.STREAMLIT TO ROLE MANAGER;
GRANT USAGE ON SCHEMA BCDR_DEMO.STREAMLIT TO ROLE VIEWER;
GRANT USAGE ON STREAMLIT BCDR_DEMO.STREAMLIT.DCA_DEMO_APP TO ROLE DATA_ADMIN;
GRANT USAGE ON STREAMLIT BCDR_DEMO.STREAMLIT.DCA_DEMO_APP TO ROLE DATA_ENGINEER;
GRANT USAGE ON STREAMLIT BCDR_DEMO.STREAMLIT.DCA_DEMO_APP TO ROLE DATA_STEWARD;
GRANT USAGE ON STREAMLIT BCDR_DEMO.STREAMLIT.DCA_DEMO_APP TO ROLE ANALYST;
GRANT USAGE ON STREAMLIT BCDR_DEMO.STREAMLIT.DCA_DEMO_APP TO ROLE MANAGER;
GRANT USAGE ON STREAMLIT BCDR_DEMO.STREAMLIT.DCA_DEMO_APP TO ROLE VIEWER;

-- Verify app was created and is accessible.
SHOW STREAMLITS IN SCHEMA BCDR_DEMO.STREAMLIT;


-- ============================================================================
-- ─────────────────────────────────────────────────────────────────────────────
-- VALIDATION QUERIES — run on either account after replication is established
-- ─────────────────────────────────────────────────────────────────────────────
-- ============================================================================


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 9 — VALIDATION
-- ═══════════════════════════════════════════════════════════════════════════

-- 9a. Failover group status (run on PRIMARY).
SHOW FAILOVER GROUPS;

-- 9b. Connection status (run on PRIMARY).
SHOW CONNECTIONS;

-- 9c. Replication refresh history — last 10 runs.
--     Healthy: STATUS = 'SUCCEEDED', ERROR_COUNT = 0.
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

-- 9d. Replication lag in minutes.
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

-- 9e. Verify Git Repository replicated (run on SECONDARY after refresh).
SHOW GIT REPOSITORIES IN DATABASE GOVERNANCE;

-- 9f. Verify replicated databases show as SECONDARY kind (run on SECONDARY).
SHOW DATABASES LIKE 'GOVERNANCE';
SHOW DATABASES LIKE 'RAW_DEV';
SHOW DATABASES LIKE 'CURATED_DEV';
SHOW DATABASES LIKE 'SEM_DEV';


-- ============================================================================
-- ─────────────────────────────────────────────────────────────────────────────
-- PART 10 — FAILOVER / FAILBACK RUNBOOK
-- ─────────────────────────────────────────────────────────────────────────────
-- Execute these steps manually during a failover or failback event.
-- Blocks are intentionally commented out to prevent accidental execution.
-- ============================================================================

/*
────────────────────────────────────────────────────────────────────────────
FAILOVER — Promote SECONDARY to PRIMARY
Run on SNOW_BCDR_SECONDARY as ACCOUNTADMIN when primary is unavailable.
────────────────────────────────────────────────────────────────────────────

USE ROLE ACCOUNTADMIN;

-- 1. Promote the DCA database group — makes replicated databases writable.
ALTER FAILOVER GROUP DCA_BCDR_DB_FG PRIMARY;

-- 2. Promote the account object group — makes roles/warehouses writable
--    on this account (shared with Iceberg BCDR).
ALTER FAILOVER GROUP ICEBERG_BCDR_ACCOUNT_FG PRIMARY;

-- 3. Redirect the client Connection to this account.
ALTER CONNECTION DCA_DEMO_CONNECTION PRIMARY;

-- 4. Verify Connection now points here.
SHOW CONNECTIONS LIKE 'DCA_DEMO_CONNECTION';

-- 5. Resume warehouses if suspended.
ALTER WAREHOUSE INGEST_WH    RESUME IF SUSPENDED;
ALTER WAREHOUSE TRANSFORM_WH RESUME IF SUSPENDED;
ALTER WAREHOUSE ANALYTICS_WH RESUME IF SUSPENDED;
ALTER WAREHOUSE AI_WH        RESUME IF SUSPENDED;


────────────────────────────────────────────────────────────────────────────
FAILBACK — Return PRIMARY to SNOW_BCDR_PRIMARY after recovery
────────────────────────────────────────────────────────────────────────────

-- STEP A: On the recovered SNOW_BCDR_PRIMARY (now acting as secondary).
--         Sync any writes made on the secondary during the outage.
USE ROLE ACCOUNTADMIN;  -- connect to SNOW_BCDR_PRIMARY

ALTER FAILOVER GROUP DCA_BCDR_DB_FG REFRESH;
ALTER FAILOVER GROUP ICEBERG_BCDR_ACCOUNT_FG REFRESH;

-- Confirm refresh succeeded before promoting.
SELECT REPLICATION_GROUP_NAME, STATUS, ERROR_COUNT
FROM SNOWFLAKE.ACCOUNT_USAGE.REPLICATION_GROUP_REFRESH_HISTORY
WHERE REPLICATION_GROUP_NAME IN ('DCA_BCDR_DB_FG', 'ICEBERG_BCDR_ACCOUNT_FG')
ORDER BY PHASE_TIME DESC
LIMIT 4;


-- STEP B: On SNOW_BCDR_SECONDARY (current primary) — hand primary back.
USE ROLE ACCOUNTADMIN;  -- connect to SNOW_BCDR_SECONDARY

ALTER FAILOVER GROUP DCA_BCDR_DB_FG PRIMARY;           -- returns to OAB74379
ALTER FAILOVER GROUP ICEBERG_BCDR_ACCOUNT_FG PRIMARY;  -- returns to OAB74379
ALTER CONNECTION DCA_DEMO_CONNECTION PRIMARY;           -- redirects back

*/
