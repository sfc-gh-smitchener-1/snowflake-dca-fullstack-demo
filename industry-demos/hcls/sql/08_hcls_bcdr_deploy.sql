-- ============================================================================
-- HCLS BC/DR DEPLOYMENT — BUSINESS CRITICAL HARDENING
-- ============================================================================
-- Extends sql/02_bcdr.sql for HCLS-specific validation and hardening.
-- Ensures HIPAA governance objects replicate correctly and clinical data
-- meets BC/DR requirements for healthcare.
--
-- PREREQS:
--   - sql/02_bcdr.sql executed on both accounts
--   - DCA_BCDR_DB_FG replication active and healthy
--   - HCLS data loaded and scripts 01-07 deployed on primary
--
-- TOPOLOGY (from sql/02_bcdr.sql):
--   Primary   : SNOW_BCDR_PRIMARY   (OAB74379)  AWS us-west-2
--   Secondary : SNOW_BCDR_SECONDARY (OZC55031)  AWS us-east-1
--   Org       : SFSENORTHAMERICA
--   Failover  : DCA_BCDR_DB_FG (GOVERNANCE, RAW_DEV, CURATED_DEV, SEM_DEV)
--
-- RUN AS: ACCOUNTADMIN on PRIMARY (Parts 1-4), SECONDARY (Parts 5-7)
-- ============================================================================


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 1 — PRIMARY: BC EDITION VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════
-- Verify the account is Business Critical and has required security features
-- active before proceeding with HCLS deployment.

USE ROLE ACCOUNTADMIN;

-- Pre-flight: confirm we're on the primary account
SELECT
    CURRENT_ACCOUNT()           AS ACCOUNT,
    CURRENT_REGION()            AS REGION,
    CURRENT_ORGANIZATION_NAME() AS ORG,
    CURRENT_USER()              AS DEPLOYING_USER,
    CURRENT_TIMESTAMP()         AS DEPLOYED_AT,
    IFF(CURRENT_ACCOUNT() = 'OAB74379',
        'CORRECT — PRIMARY ACCOUNT',
        '*** WARNING: Expected OAB74379 (PRIMARY) ***') AS ACCOUNT_CHECK;

-- Verify Business Critical features are available
SELECT SYSTEM$IS_APPLICATION_ROLE_ENABLED('SNOWFLAKE.SECURITY') AS BC_SECURITY_FEATURES;

-- Verify account-level security parameters
SHOW PARAMETERS LIKE 'PERIODIC_DATA_REKEYING' IN ACCOUNT;
SHOW PARAMETERS LIKE 'MIN_DATA_RETENTION_TIME_IN_DAYS' IN ACCOUNT;

-- Verify all HCLS governance objects exist on primary
SELECT 'ONTOLOGY_GRAPH_NODES' AS OBJECT_NAME, COUNT(*) AS ROW_COUNT
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
WHERE SOURCE_SYSTEM IN ('FHIR', 'WORKDAY_HCM', 'PAYER')
UNION ALL
SELECT 'ONTOLOGY_GRAPH_EDGES', COUNT(*)
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
WHERE EDGE_ID LIKE 'HCLS_%' OR EDGE_ID LIKE 'WD_%' OR EDGE_ID LIKE 'STAFF_%' OR EDGE_ID LIKE 'PYR_%'
UNION ALL
SELECT 'HCLS_STAFFING_CONTEXT', COUNT(*)
FROM DCA_DEMO.GOVERNANCE.HCLS_STAFFING_CONTEXT
UNION ALL
SELECT 'HCLS_PATIENT_COMORBIDITY', COUNT(*)
FROM DCA_DEMO.GOVERNANCE.HCLS_PATIENT_COMORBIDITY
UNION ALL
SELECT 'HCLS_PAYER_METRICS', COUNT(*)
FROM DCA_DEMO.GOVERNANCE.HCLS_PAYER_METRICS
UNION ALL
SELECT 'HCLS_CORRELATION_RESULTS', COUNT(*)
FROM DCA_DEMO.GOVERNANCE.HCLS_CORRELATION_RESULTS
UNION ALL
SELECT 'HCLS_COMORBIDITY_PAIRS', COUNT(*)
FROM DCA_DEMO.GOVERNANCE.HCLS_COMORBIDITY_PAIRS
UNION ALL
SELECT 'HCLS_CARE_GAPS', COUNT(*)
FROM DCA_DEMO.GOVERNANCE.HCLS_CARE_GAPS
UNION ALL
SELECT 'HCLS_STAFFING_OUTCOME_METRICS', COUNT(*)
FROM DCA_DEMO.GOVERNANCE.HCLS_STAFFING_OUTCOME_METRICS;


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 2 — PRIMARY: GOVERNANCE OBJECT REPLICATION CHECK
-- ═══════════════════════════════════════════════════════════════════════════
-- Verify that masking policies, tags, and row access policies exist in the
-- GOVERNANCE database. These must replicate via DCA_BCDR_DB_FG for HIPAA
-- compliance on the secondary account.

-- Masking policies (7 expected: name, email, phone, address, SSN, DOB, financial)
SELECT POLICY_NAME, POLICY_KIND, POLICY_BODY
FROM GOVERNANCE.INFORMATION_SCHEMA.MASKING_POLICIES
ORDER BY POLICY_NAME;

-- Tags (HIPAA_CATEGORY, PII_TYPE, DATA_CLASSIFICATION, etc.)
SHOW TAGS IN DATABASE GOVERNANCE;

-- Row access policies
SELECT POLICY_NAME, POLICY_KIND
FROM GOVERNANCE.INFORMATION_SCHEMA.ROW_ACCESS_POLICIES
ORDER BY POLICY_NAME;

-- Confirm all 4 DCA databases are in the failover group
SHOW FAILOVER GROUPS LIKE 'DCA_BCDR_DB_FG';


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 3 — PRIMARY: HCLS DATA COMPLETENESS CHECK
-- ═══════════════════════════════════════════════════════════════════════════
-- Count rows in each data system to establish baselines for comparison
-- with the secondary account after replication.

-- FHIR clinical tables
SELECT 'FHIR' AS SYSTEM, 'PATIENTS' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM RAW_DEV.FHIR.PATIENTS
UNION ALL SELECT 'FHIR', 'ENCOUNTERS', COUNT(*) FROM RAW_DEV.FHIR.ENCOUNTERS
UNION ALL SELECT 'FHIR', 'CONDITIONS', COUNT(*) FROM RAW_DEV.FHIR.CONDITIONS
UNION ALL SELECT 'FHIR', 'OBSERVATIONS', COUNT(*) FROM RAW_DEV.FHIR.OBSERVATIONS
UNION ALL SELECT 'FHIR', 'MEDICATIONS', COUNT(*) FROM RAW_DEV.FHIR.MEDICATIONS
UNION ALL SELECT 'FHIR', 'PROCEDURES', COUNT(*) FROM RAW_DEV.FHIR.PROCEDURES
UNION ALL
-- Workday HCM tables
SELECT 'WORKDAY', 'WORKERS', COUNT(*) FROM RAW_DEV.WORKDAY_HCM.WORKERS
UNION ALL SELECT 'WORKDAY', 'SHIFTS', COUNT(*) FROM RAW_DEV.WORKDAY_HCM.SHIFTS
UNION ALL SELECT 'WORKDAY', 'DEPARTMENTS', COUNT(*) FROM RAW_DEV.WORKDAY_HCM.DEPARTMENTS
UNION ALL
-- Payer tables
SELECT 'PAYER', 'CLAIMS_DETAIL', COUNT(*) FROM RAW_DEV.PAYER.CLAIMS_DETAIL
UNION ALL SELECT 'PAYER', 'PRIOR_AUTHORIZATIONS', COUNT(*) FROM RAW_DEV.PAYER.PRIOR_AUTHORIZATIONS
UNION ALL
-- Governance analytics tables
SELECT 'GOVERNANCE', 'ONTOLOGY_GRAPH_NODES', COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
UNION ALL SELECT 'GOVERNANCE', 'ONTOLOGY_GRAPH_EDGES', COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
UNION ALL SELECT 'GOVERNANCE', 'HCLS_CORRELATION_RESULTS', COUNT(*) FROM DCA_DEMO.GOVERNANCE.HCLS_CORRELATION_RESULTS
UNION ALL SELECT 'GOVERNANCE', 'HCLS_PATIENT_COMORBIDITY', COUNT(*) FROM DCA_DEMO.GOVERNANCE.HCLS_PATIENT_COMORBIDITY
UNION ALL SELECT 'GOVERNANCE', 'HCLS_PAYER_METRICS', COUNT(*) FROM DCA_DEMO.GOVERNANCE.HCLS_PAYER_METRICS
UNION ALL SELECT 'GOVERNANCE', 'HCLS_COMORBIDITY_PAIRS', COUNT(*) FROM DCA_DEMO.GOVERNANCE.HCLS_COMORBIDITY_PAIRS
UNION ALL SELECT 'GOVERNANCE', 'HCLS_CARE_GAPS', COUNT(*) FROM DCA_DEMO.GOVERNANCE.HCLS_CARE_GAPS
ORDER BY SYSTEM, TABLE_NAME;

-- Save primary counts for later comparison (record these values before switching to secondary)
SELECT
    'PRIMARY_BASELINE' AS CHECK_TYPE,
    CURRENT_TIMESTAMP() AS CHECKED_AT,
    (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES) AS TOTAL_NODES,
    (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES) AS TOTAL_EDGES,
    (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.HCLS_CORRELATION_RESULTS) AS CORRELATIONS,
    (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.HCLS_PATIENT_COMORBIDITY) AS COMORBIDITY_RECORDS,
    (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.HCLS_PAYER_METRICS) AS PAYER_METRICS,
    (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_SNAPSHOTS) AS SNAPSHOTS;


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 4 — PRIMARY: REPLICATION STATUS MONITORING
-- ═══════════════════════════════════════════════════════════════════════════
-- Monitor replication health and calculate current lag.
-- Alert threshold: 15 minutes (healthcare RPO target).

-- Recent replication refresh history for DCA_BCDR_DB_FG
SELECT
    REPLICATION_GROUP_NAME,
    PHASE_NAME,
    START_TIME,
    END_TIME,
    DATEDIFF('second', START_TIME, END_TIME) AS DURATION_SECONDS,
    TOTAL_BYTES,
    OBJECT_COUNT
FROM SNOWFLAKE.ACCOUNT_USAGE.REPLICATION_GROUP_REFRESH_HISTORY
WHERE REPLICATION_GROUP_NAME = 'DCA_BCDR_DB_FG'
ORDER BY START_TIME DESC
LIMIT 10;

-- Calculate current replication lag
SELECT
    REPLICATION_GROUP_NAME,
    MAX(END_TIME) AS LAST_SUCCESSFUL_REFRESH,
    DATEDIFF('minute', MAX(END_TIME), CURRENT_TIMESTAMP()) AS LAG_MINUTES,
    IFF(DATEDIFF('minute', MAX(END_TIME), CURRENT_TIMESTAMP()) > 15,
        '*** ALERT: Replication lag exceeds 15-minute RPO target ***',
        'OK: Replication within RPO target') AS RPO_STATUS
FROM SNOWFLAKE.ACCOUNT_USAGE.REPLICATION_GROUP_REFRESH_HISTORY
WHERE REPLICATION_GROUP_NAME = 'DCA_BCDR_DB_FG'
  AND PHASE_NAME = 'COMPLETED'
GROUP BY REPLICATION_GROUP_NAME;

-- Bytes transferred over last 24 hours (capacity planning)
SELECT
    DATE_TRUNC('hour', START_TIME) AS HOUR,
    SUM(TOTAL_BYTES) / (1024*1024) AS MB_TRANSFERRED,
    COUNT(*) AS REFRESH_COUNT
FROM SNOWFLAKE.ACCOUNT_USAGE.REPLICATION_GROUP_REFRESH_HISTORY
WHERE REPLICATION_GROUP_NAME = 'DCA_BCDR_DB_FG'
  AND START_TIME > DATEADD('hour', -24, CURRENT_TIMESTAMP())
GROUP BY 1
ORDER BY 1 DESC;


-- ============================================================================
-- ─────────────────────────────────────────────────────────────────────────────
-- SWITCH CONNECTION TO: SNOW_BCDR_SECONDARY (OZC55031 / AWS us-east-1)
-- ─────────────────────────────────────────────────────────────────────────────
-- Run Parts 5-7 as ACCOUNTADMIN on SNOW_BCDR_SECONDARY
-- ============================================================================


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 5 — SECONDARY: POST-REPLICATION VALIDATION
-- ═══════════════════════════════════════════════════════════════════════════
-- Verify all 4 databases are visible as SECONDARY replicas and that
-- governance objects replicated correctly.

USE ROLE ACCOUNTADMIN;

-- Confirm we're on the secondary account
SELECT
    CURRENT_ACCOUNT()           AS ACCOUNT,
    CURRENT_REGION()            AS REGION,
    CURRENT_ORGANIZATION_NAME() AS ORG,
    IFF(CURRENT_ACCOUNT() = 'OZC55031',
        'CORRECT — SECONDARY ACCOUNT',
        '*** WARNING: Expected OZC55031 (SECONDARY) ***') AS ACCOUNT_CHECK;

-- Verify all 4 DCA databases are visible as replicas
SHOW DATABASES LIKE 'GOVERNANCE';
SHOW DATABASES LIKE 'RAW_DEV';
SHOW DATABASES LIKE 'CURATED_DEV';
SHOW DATABASES LIKE 'SEM_DEV';

-- Verify failover group status on secondary
SHOW FAILOVER GROUPS LIKE 'DCA_BCDR_DB_FG';

-- Verify governance tables replicated with data (compare counts to Part 3 baseline)
SELECT
    'SECONDARY_VALIDATION' AS CHECK_TYPE,
    CURRENT_TIMESTAMP() AS CHECKED_AT,
    (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES) AS TOTAL_NODES,
    (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES) AS TOTAL_EDGES,
    (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.HCLS_CORRELATION_RESULTS) AS CORRELATIONS,
    (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.HCLS_PATIENT_COMORBIDITY) AS COMORBIDITY_RECORDS,
    (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.HCLS_PAYER_METRICS) AS PAYER_METRICS,
    (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_SNAPSHOTS) AS SNAPSHOTS;

-- Verify masking policies exist on secondary
SELECT POLICY_NAME, POLICY_KIND
FROM GOVERNANCE.INFORMATION_SCHEMA.MASKING_POLICIES
ORDER BY POLICY_NAME;

-- Verify tags exist on secondary
SHOW TAGS IN DATABASE GOVERNANCE;

-- Verify row access policies on secondary
SELECT POLICY_NAME, POLICY_KIND
FROM GOVERNANCE.INFORMATION_SCHEMA.ROW_ACCESS_POLICIES
ORDER BY POLICY_NAME;


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 6 — SECONDARY: STREAMLIT APP VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════
-- Verify the Streamlit app is accessible on the secondary account and that
-- the Signal Graph page dependencies are available.

-- Check if BCDR_DEMO database and Streamlit app exist
-- (Created by sql/02_bcdr.sql Part 8)
SHOW DATABASES LIKE 'BCDR_DEMO';
SHOW STREAMLITS IN SCHEMA BCDR_DEMO.STREAMLIT;

-- Verify Signal Graph page dependencies are available
-- These are read from replicated GOVERNANCE database
SELECT
    'Signal Graph Dependencies' AS CHECK,
    (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
     WHERE SOURCE_SYSTEM IN ('FHIR', 'WORKDAY_HCM', 'PAYER')) AS HCLS_NODES,
    (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
     WHERE EDGE_ID LIKE 'HCLS_%' OR EDGE_ID LIKE 'WD_%'
        OR EDGE_ID LIKE 'STAFF_%' OR EDGE_ID LIKE 'PYR_%') AS HCLS_EDGES,
    IFF(HCLS_NODES > 0 AND HCLS_EDGES > 0,
        'OK: Signal Graph data available',
        '*** WARNING: Missing graph data — wait for next replication cycle ***') AS STATUS;

-- Test a sample governance query against replicated data
SELECT
    'Sample Governance Query' AS CHECK,
    COUNT(DISTINCT SOURCE_SYSTEM) AS SYSTEMS_REPRESENTED,
    COUNT(DISTINCT NODE_TYPE) AS NODE_TYPES,
    COUNT(*) AS TOTAL_NODES
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
WHERE SOURCE_SYSTEM IN ('FHIR', 'WORKDAY_HCM', 'PAYER');


-- ═══════════════════════════════════════════════════════════════════════════
-- PART 7 — BOTH ACCOUNTS: FAILOVER DRILL CHECKLIST
-- ═══════════════════════════════════════════════════════════════════════════
-- Step-by-step failover drill procedure specific to HCLS.
-- Execute monthly and document results for CMS CoP compliance.
--
-- ESTIMATED TIMINGS:
--   Failover execution:    < 2 minutes
--   Application available: < 5 minutes (RTO target)
--   Pipeline refresh:      < 15 minutes
--   Full validation:       < 20 minutes total
--
-- ── PRE-FAILOVER (run on PRIMARY) ──────────────────────────────────────
--
-- Step 1: Record pre-failover governance state
--   SELECT COUNT(*) AS PRE_NODES FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES;
--   SELECT COUNT(*) AS PRE_EDGES FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES;
--   SELECT MAX(CREATED_AT) AS LAST_SNAPSHOT FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_SNAPSHOTS;
--   -- Record these values for post-failover RPO verification
--
-- Step 2: Record replication lag immediately before failover
--   SELECT MAX(END_TIME) AS LAST_REFRESH
--   FROM SNOWFLAKE.ACCOUNT_USAGE.REPLICATION_GROUP_REFRESH_HISTORY
--   WHERE REPLICATION_GROUP_NAME = 'DCA_BCDR_DB_FG'
--     AND PHASE_NAME = 'COMPLETED';
--
-- ── FAILOVER EXECUTION (run on SECONDARY) ──────────────────────────────
--
-- Step 3: Promote secondary to primary (target: < 2 min)
--   ALTER FAILOVER GROUP DCA_BCDR_DB_FG PRIMARY;
--
-- Step 4: Promote client-redirect connection
--   ALTER CONNECTION DCA_DEMO_CONNECTION PRIMARY;
--
-- ── POST-FAILOVER VALIDATION (run on SECONDARY — now primary) ──────────
--
-- Step 5: Verify Streamlit app is accessible
--   SHOW STREAMLITS IN SCHEMA BCDR_DEMO.STREAMLIT;
--   -- Open the Streamlit URL in a browser to confirm
--
-- Step 6: Run quick refresh to ensure pipeline is functional (target: < 10 min)
--   CALL DCA_DEMO.GOVERNANCE.SP_HCLS_QUICK_REFRESH();
--
-- Step 7: Compare governance counts with pre-failover baseline
--   SELECT COUNT(*) AS POST_NODES FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES;
--   SELECT COUNT(*) AS POST_EDGES FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES;
--   -- Counts should match pre-failover values (RPO verification)
--
-- Step 8: Record actual RPO achieved
--   -- RPO = CURRENT_TIMESTAMP() - LAST_REFRESH (from Step 2)
--   -- Target: < 10 minutes
--
-- Step 9: Record actual RTO achieved
--   -- RTO = time from Step 3 start to Step 5 completion
--   -- Target: < 5 minutes
--
-- ── FAILBACK (after primary is recovered) ──────────────────────────────
--
-- Step 10: On the recovered original primary:
--   CREATE FAILOVER GROUP IF NOT EXISTS DCA_BCDR_DB_FG
--       AS REPLICA OF SFSENORTHAMERICA.SNOW_BCDR_SECONDARY.DCA_BCDR_DB_FG;
--   -- Wait for initial replication to complete
--
-- Step 11: On current primary (original secondary):
--   ALTER FAILOVER GROUP DCA_BCDR_DB_FG
--       ALLOWED_ACCOUNTS = SFSENORTHAMERICA.SNOW_BCDR_PRIMARY;
--   -- Promote original primary back:
--   -- On original primary: ALTER FAILOVER GROUP DCA_BCDR_DB_FG PRIMARY;
--   -- On original primary: ALTER CONNECTION DCA_DEMO_CONNECTION PRIMARY;
--
-- Step 12: Document drill results
--   -- Record: date, RPO achieved, RTO achieved, issues encountered
--   -- Store in ONTOLOGY_GRAPH_SNAPSHOTS with snapshot_type = 'BCDR_DRILL'
--
-- ═══════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════
-- SUMMARY — OVERALL BC/DR HEALTH STATUS
-- ═══════════════════════════════════════════════════════════════════════════
-- Run this on either account to get a quick BC/DR health dashboard.

SELECT
    'HCLS BC/DR Health Check' AS REPORT,
    CURRENT_ACCOUNT() AS ACCOUNT,
    CURRENT_REGION() AS REGION,
    CURRENT_TIMESTAMP() AS CHECKED_AT;

-- Object counts summary
SELECT
    'Governance Nodes' AS METRIC,
    COUNT(*) AS VALUE
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
WHERE SOURCE_SYSTEM IN ('FHIR', 'WORKDAY_HCM', 'PAYER')
UNION ALL
SELECT 'Governance Edges', COUNT(*)
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
WHERE EDGE_ID LIKE 'HCLS_%' OR EDGE_ID LIKE 'WD_%'
   OR EDGE_ID LIKE 'STAFF_%' OR EDGE_ID LIKE 'PYR_%'
UNION ALL
SELECT 'Correlation Results', COUNT(*)
FROM DCA_DEMO.GOVERNANCE.HCLS_CORRELATION_RESULTS
UNION ALL
SELECT 'Comorbidity Records', COUNT(*)
FROM DCA_DEMO.GOVERNANCE.HCLS_PATIENT_COMORBIDITY
UNION ALL
SELECT 'Payer Metrics', COUNT(*)
FROM DCA_DEMO.GOVERNANCE.HCLS_PAYER_METRICS
UNION ALL
SELECT 'Comorbidity Pairs', COUNT(*)
FROM DCA_DEMO.GOVERNANCE.HCLS_COMORBIDITY_PAIRS
UNION ALL
SELECT 'Care Gaps', COUNT(*)
FROM DCA_DEMO.GOVERNANCE.HCLS_CARE_GAPS
UNION ALL
SELECT 'Snapshots', COUNT(*)
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_SNAPSHOTS
ORDER BY METRIC;

-- ============================================================================
-- DEPLOYMENT COMPLETE
-- ============================================================================
-- VALIDATED:
--   ✓ Business Critical edition verified
--   ✓ Security parameters checked (rekeying, retention)
--   ✓ All HCLS governance objects present on primary
--   ✓ Masking policies, tags, and row access policies cataloged
--   ✓ HCLS data completeness baseline established
--   ✓ Replication lag monitored against 15-minute RPO target
--   ✓ Secondary database replication confirmed
--   ✓ Governance object replication verified on secondary
--   ✓ Streamlit app and Signal Graph dependencies checked
--   ✓ Failover drill checklist documented
--
-- NEXT STEPS:
--   1. Compare Part 3 (primary) counts with Part 5 (secondary) counts
--   2. Schedule monthly failover drills (see Part 7)
--   3. Deploy network hardening (09_hcls_network_hardening.sql)
--   4. Configure replication lag alerts (threshold: 15 minutes)
--   5. Document BC/DR status in customer security review
-- ============================================================================
