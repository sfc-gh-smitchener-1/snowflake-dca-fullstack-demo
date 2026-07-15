-- ============================================================================
-- DATA CONTRACTS ON SNOWFLAKE HORIZON — 09 DASHBOARD VIEWS
-- ============================================================================
--
-- Presentation views consumed by the Streamlit page (contracts/streamlit/).
--   V_CONTRACT_HEALTH        — one row per contract, latest run + rollup status
--   V_CONTRACT_SCORECARD     — per-dimension pass/warn/fail counts per contract
--   V_BREACH_FEED            — open breaches, newest first
--   V_CONTRACT_COVERAGE      — estate coverage: % of key objects under contract
--   V_VALIDATION_TIMELINE    — validation history for trend charts
--
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE WAREHOUSE TRANSFORM_WH;
USE SCHEMA GOVERNANCE.DATA_CONTRACTS;

-- ----------------------------------------------------------------------------
-- V_CONTRACT_HEALTH — latest validation state per contract
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW V_CONTRACT_HEALTH AS
SELECT
    c.CONTRACT_ID,
    c.CONTRACT_VERSION,
    c.CONTRACT_NAME,
    c.STATUS AS CONTRACT_STATUS,
    c.PRODUCER_TEAM,
    c.CONSUMER_CRITICALITY,
    c.DATA_CLASSIFICATION,
    c.DEFAULT_ENFORCEMENT,
    c.SCHEMA_STABILITY,
    b.FULL_OBJECT_PATH,
    b.DATA_LAYER,
    COALESCE(b.ENFORCEMENT_MODE, c.DEFAULT_ENFORCEMENT) AS EFFECTIVE_ENFORCEMENT,
    r.RUN_ID          AS LAST_RUN_ID,
    r.RUN_START       AS LAST_VALIDATED_AT,
    r.SCHEMA_STATUS,
    r.QUALITY_STATUS,
    r.SLA_STATUS,
    r.LINEAGE_STATUS,
    r.OVERALL_STATUS,
    r.ENFORCEMENT_ACTION,
    r.ROW_COUNT,
    CASE
        WHEN r.RUN_ID IS NULL          THEN 'NOT_VALIDATED'
        WHEN r.OVERALL_STATUS = 'PASS' THEN 'HEALTHY'
        WHEN r.OVERALL_STATUS = 'WARN' THEN 'DEGRADED'
        WHEN r.ENFORCEMENT_ACTION = 'BLOCKED' THEN 'BLOCKED'
        ELSE 'BREACHED'
    END AS HEALTH_STATUS
FROM CONTRACT c
JOIN CONTRACT_BINDING b
    ON c.CONTRACT_ID = b.CONTRACT_ID AND c.CONTRACT_VERSION = b.CONTRACT_VERSION
LEFT JOIN (
    SELECT * FROM VALIDATION_RUN
    QUALIFY ROW_NUMBER() OVER (PARTITION BY CONTRACT_ID, BINDING_ID ORDER BY RUN_START DESC) = 1
) r ON c.CONTRACT_ID = r.CONTRACT_ID AND b.BINDING_ID = r.BINDING_ID
WHERE c.STATUS = 'ACTIVE' AND b.IS_ACTIVE = TRUE;

-- ----------------------------------------------------------------------------
-- V_CONTRACT_SCORECARD — per-dimension detail counts from the latest run
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW V_CONTRACT_SCORECARD AS
WITH last_run AS (
    SELECT CONTRACT_ID, RUN_ID
    FROM VALIDATION_RUN
    QUALIFY ROW_NUMBER() OVER (PARTITION BY CONTRACT_ID ORDER BY RUN_START DESC) = 1
)
SELECT
    lr.CONTRACT_ID,
    vr.DIMENSION,
    COUNT(*)                                  AS TOTAL_CHECKS,
    COUNT_IF(vr.STATUS = 'PASS')              AS PASSED,
    COUNT_IF(vr.STATUS = 'WARN')              AS WARNED,
    COUNT_IF(vr.STATUS = 'FAIL')              AS FAILED,
    ROUND(100.0 * COUNT_IF(vr.STATUS = 'PASS') / NULLIF(COUNT(*), 0), 1) AS PASS_PCT
FROM last_run lr
JOIN VALIDATION_RESULT vr ON lr.RUN_ID = vr.RUN_ID
GROUP BY lr.CONTRACT_ID, vr.DIMENSION;

-- ----------------------------------------------------------------------------
-- V_BREACH_FEED — open breaches newest first, enriched with contract context
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW V_BREACH_FEED AS
SELECT
    bl.BREACH_ID,
    bl.CONTRACT_ID,
    c.CONTRACT_NAME,
    c.CONSUMER_CRITICALITY,
    b.FULL_OBJECT_PATH,
    bl.DIMENSION,
    bl.SEVERITY,
    bl.ENFORCEMENT_ACTION,
    bl.SUMMARY,
    bl.DETAILS,
    bl.STATUS,
    bl.DETECTED_AT,
    bl.RESOLVED_AT,
    DATEDIFF('minute', bl.DETECTED_AT, COALESCE(bl.RESOLVED_AT, CURRENT_TIMESTAMP())) AS AGE_MINUTES
FROM BREACH_LOG bl
LEFT JOIN CONTRACT c ON bl.CONTRACT_ID = c.CONTRACT_ID AND bl.CONTRACT_VERSION = c.CONTRACT_VERSION
LEFT JOIN CONTRACT_BINDING b ON bl.BINDING_ID = b.BINDING_ID
ORDER BY
    CASE bl.STATUS WHEN 'OPEN' THEN 1 WHEN 'ACKNOWLEDGED' THEN 2 ELSE 3 END,
    bl.DETECTED_AT DESC;

-- ----------------------------------------------------------------------------
-- V_CONTRACT_COVERAGE — how much of the estate is under contract
-- Compares contracted objects vs all base tables in RAW_DEV / CURATED_DEV / SEM_DEV.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW V_CONTRACT_COVERAGE AS
WITH contracted AS (
    SELECT DISTINCT FULL_OBJECT_PATH, DATA_LAYER
    FROM CONTRACT_BINDING WHERE IS_ACTIVE = TRUE
),
estate AS (
    SELECT 'RAW'     AS DATA_LAYER, COUNT(*) AS OBJ_COUNT
      FROM RAW_DEV.INFORMATION_SCHEMA.TABLES
     WHERE TABLE_TYPE = 'BASE TABLE'
       AND TABLE_SCHEMA NOT IN ('INFORMATION_SCHEMA','STAGING','SHARED','PUBLIC')
       AND TABLE_NAME NOT LIKE '%_TEMPLATE'
    UNION ALL
    SELECT 'CURATED', COUNT(*)
      FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
     WHERE TABLE_TYPE IN ('BASE TABLE','DYNAMIC TABLE')
       AND TABLE_SCHEMA NOT IN ('INFORMATION_SCHEMA','HORIZON_CONTEXT')
)
SELECT
    e.DATA_LAYER,
    e.OBJ_COUNT                                   AS TOTAL_OBJECTS,
    COUNT(c.FULL_OBJECT_PATH)                     AS CONTRACTED_OBJECTS,
    ROUND(100.0 * COUNT(c.FULL_OBJECT_PATH) / NULLIF(e.OBJ_COUNT, 0), 1) AS COVERAGE_PCT
FROM estate e
LEFT JOIN contracted c ON e.DATA_LAYER = c.DATA_LAYER
GROUP BY e.DATA_LAYER, e.OBJ_COUNT;

-- ----------------------------------------------------------------------------
-- V_VALIDATION_TIMELINE — run history for trend charts
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW V_VALIDATION_TIMELINE AS
SELECT
    CONTRACT_ID,
    DATE_TRUNC('hour', RUN_START) AS RUN_HOUR,
    RUN_START,
    OVERALL_STATUS,
    SCHEMA_STATUS, QUALITY_STATUS, SLA_STATUS, LINEAGE_STATUS,
    ENFORCEMENT_ACTION,
    TRIGGERED_BY
FROM VALIDATION_RUN
WHERE RUN_START >= DATEADD('day', -30, CURRENT_TIMESTAMP())
ORDER BY RUN_START DESC;

-- ----------------------------------------------------------------------------
-- Grants
-- ----------------------------------------------------------------------------
GRANT SELECT ON ALL VIEWS IN SCHEMA GOVERNANCE.DATA_CONTRACTS TO ROLE DATA_STEWARD;
GRANT SELECT ON ALL VIEWS IN SCHEMA GOVERNANCE.DATA_CONTRACTS TO ROLE DATA_ENGINEER;
GRANT SELECT ON ALL VIEWS IN SCHEMA GOVERNANCE.DATA_CONTRACTS TO ROLE AUDITOR;

SELECT '✓ Dashboard views created (5 views)' AS STATUS;
