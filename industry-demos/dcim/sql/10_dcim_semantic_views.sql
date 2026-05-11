-- ============================================================================
-- DCIM KNOWLEDGE GRAPH — SEMANTIC VIEWS FOR CORTEX ANALYST
-- ============================================================================
-- Creates semantic views that serve as the "Gold" analytical layer for BI
-- and Cortex Analyst consumption. These views join curated tables from
-- multiple source systems to answer cross-domain business questions.
--
-- Views:
--   1. DCIM_SYSTEM_UPTIME_VS_STAFF_AVAILABILITY — Switch uptime vs shift coverage
--   2. DCIM_RISK_WEIGHTED_MTTR — MTTR adjusted by SLA tier and cert freshness
--   3. DCIM_PORT_HEALTH_BY_BUSINESS_PRIORITY — Port health heatmap by SLA
--
-- PREREQUISITES:
--   - Scripts 01-08 deployed
--   - SP_DCIM_MASTER_ORCHESTRATOR executed (analytics tables populated)
--
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE DCA_DEMO;
USE SCHEMA GOVERNANCE;
USE WAREHOUSE COMPUTE_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- VIEW 1: DCIM_SYSTEM_UPTIME_VS_STAFF_AVAILABILITY
-- ═══════════════════════════════════════════════════════════════════════════
-- Correlates switch uptime (from telemetry) with technician shift coverage
-- (from Workday). Answers: "Are we adequately staffed when equipment is
-- most at risk?"
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW DCA_DEMO.GOVERNANCE.DCIM_SYSTEM_UPTIME_VS_STAFF_AVAILABILITY
    COMMENT = 'Correlates switch uptime with technician shift coverage by data center and hour. Use to detect understaffing during high-risk periods.'
AS
WITH switch_hourly AS (
    -- Aggregate switch health to hourly granularity per data center
    SELECT
        sw.RACK_ID,
        DATE_TRUNC('hour', sh.METRIC_TIMESTAMP) AS DATE_HOUR,
        COUNT(DISTINCT sh.SWITCH_ID) AS TOTAL_SWITCHES,
        COUNT(DISTINCT CASE WHEN sh.ERROR_RATE_PCT < 0.5 THEN sh.SWITCH_ID END) AS SWITCHES_ONLINE,
        COUNT(DISTINCT CASE WHEN sh.ERROR_RATE_PCT >= 0.5 AND sh.ERROR_RATE_PCT < 2.0 THEN sh.SWITCH_ID END) AS SWITCHES_DEGRADED,
        COUNT(DISTINCT CASE WHEN sh.ERROR_RATE_PCT >= 2.0 THEN sh.SWITCH_ID END) AS SWITCHES_CRITICAL,
        AVG(sh.ERROR_RATE_PCT) AS AVG_ERROR_RATE
    FROM CURATED_DEV.TELEMETRY.FACT_SWITCH_HEALTH sh
    JOIN CURATED_DEV.SERVICENOW.DIM_SWITCH sw
        ON sh.SWITCH_ID = sw.SWITCH_ID
    GROUP BY sw.RACK_ID, DATE_TRUNC('hour', sh.METRIC_TIMESTAMP)
),
rack_to_dc AS (
    -- Map racks to data centers via halls
    SELECT
        r.RACK_ID,
        h.HALL_ID,
        dc.DATA_CENTER_ID,
        dc.DC_NAME AS DATA_CENTER_NAME
    FROM CURATED_DEV.SERVICENOW.DIM_RACK r
    JOIN CURATED_DEV.SERVICENOW.DIM_HALL h ON r.HALL_ID = h.HALL_ID
    JOIN CURATED_DEV.SERVICENOW.DIM_DATA_CENTER dc ON h.DATA_CENTER_ID = dc.DATA_CENTER_ID
),
dc_switch_hourly AS (
    -- Roll up to data center level
    SELECT
        rd.DATA_CENTER_NAME,
        sh.DATE_HOUR,
        SUM(sh.TOTAL_SWITCHES) AS TOTAL_SWITCHES,
        SUM(sh.SWITCHES_ONLINE) AS SWITCHES_ONLINE,
        SUM(sh.SWITCHES_DEGRADED) AS SWITCHES_DEGRADED,
        SUM(sh.SWITCHES_CRITICAL) AS SWITCHES_CRITICAL,
        AVG(sh.AVG_ERROR_RATE) AS AVG_ERROR_RATE
    FROM switch_hourly sh
    JOIN rack_to_dc rd ON sh.RACK_ID = rd.RACK_ID
    GROUP BY rd.DATA_CENTER_NAME, sh.DATE_HOUR
),
shift_coverage AS (
    -- Count technicians on shift per campus per hour
    SELECT
        dc.DC_NAME AS DATA_CENTER_NAME,
        DATE_TRUNC('hour', fs.SHIFT_DATE::TIMESTAMP_NTZ) AS DATE_HOUR,
        COUNT(DISTINCT fs.WORKER_ID) AS TECHNICIANS_ON_SHIFT
    FROM CURATED_DEV.WORKDAY_DCIM.FACT_SHIFTS fs
    JOIN CURATED_DEV.WORKDAY_DCIM.DIM_TECHNICIAN t ON fs.WORKER_ID = t.WORKER_ID
    JOIN CURATED_DEV.SERVICENOW.DIM_DATA_CENTER dc ON t.CAMPUS_ASSIGNMENT = dc.CAMPUS_ID
    GROUP BY dc.DC_NAME, DATE_TRUNC('hour', fs.SHIFT_DATE::TIMESTAMP_NTZ)
)
SELECT
    dsh.DATA_CENTER_NAME,
    dsh.DATE_HOUR,
    ROUND(dsh.SWITCHES_ONLINE * 100.0 / NULLIF(dsh.TOTAL_SWITCHES, 0), 1) AS SWITCHES_ONLINE_PCT,
    ROUND(dsh.SWITCHES_DEGRADED * 100.0 / NULLIF(dsh.TOTAL_SWITCHES, 0), 1) AS SWITCHES_DEGRADED_PCT,
    ROUND(dsh.SWITCHES_CRITICAL * 100.0 / NULLIF(dsh.TOTAL_SWITCHES, 0), 1) AS SWITCHES_CRITICAL_PCT,
    COALESCE(sc.TECHNICIANS_ON_SHIFT, 0) AS TECHNICIANS_ON_SHIFT,
    -- Rule of thumb: 1 technician per 50 switches as baseline
    CEIL(dsh.TOTAL_SWITCHES / 50.0) AS REQUIRED_TECHNICIANS,
    ROUND(COALESCE(sc.TECHNICIANS_ON_SHIFT, 0) / NULLIF(CEIL(dsh.TOTAL_SWITCHES / 50.0), 0), 2) AS STAFF_COVERAGE_RATIO,
    CASE WHEN COALESCE(sc.TECHNICIANS_ON_SHIFT, 0) < CEIL(dsh.TOTAL_SWITCHES / 50.0)
         THEN TRUE ELSE FALSE END AS UNDERSTAFFED_FLAG,
    ROUND(dsh.AVG_ERROR_RATE, 3) AS AVG_ERROR_RATE,
    -- Pull in MTTR for the most recent calculation if available
    NULL AS AVG_MTTR_MINUTES  -- Populated by joining DCIM_MTTR_METRICS in downstream queries
FROM dc_switch_hourly dsh
LEFT JOIN shift_coverage sc
    ON dsh.DATA_CENTER_NAME = sc.DATA_CENTER_NAME
    AND dsh.DATE_HOUR = sc.DATE_HOUR;

-- ═══════════════════════════════════════════════════════════════════════════
-- VIEW 2: DCIM_RISK_WEIGHTED_MTTR
-- ═══════════════════════════════════════════════════════════════════════════
-- MTTR adjusted by SLA tier and certification freshness. Answers: "How does
-- certification compliance affect our repair times, weighted by business
-- impact?"
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW DCA_DEMO.GOVERNANCE.DCIM_RISK_WEIGHTED_MTTR
    COMMENT = 'MTTR adjusted by SLA tier and certification freshness. Shows whether cert gaps correlate with slower repair times.'
AS
WITH mttr_base AS (
    SELECT
        m.DATA_CENTER_ID,
        m.DC_NAME AS DATA_CENTER_NAME,
        m.PRIORITY,
        m.AVG_MTTR_MINUTES,
        m.MEDIAN_MTTR_MINUTES,
        m.P95_MTTR_MINUTES,
        m.INCIDENTS_COUNT,
        m.STAFF_AVAILABLE_PCT,
        m.CALCULATED_AT
    FROM DCA_DEMO.GOVERNANCE.DCIM_MTTR_METRICS m
),
risk_by_dc AS (
    -- Aggregate certification freshness factor per data center
    SELECT
        rs.DATA_CENTER AS DATA_CENTER_NAME,
        rs.SLA_TIER,
        COUNT(*) AS RISK_COUNT,
        -- Cert freshness: 1.0 if all valid, degrades as certs expire
        AVG(CASE
            WHEN rs.CERT_STATUS = 'ACTIVE' THEN 1.0
            WHEN rs.CERT_STATUS = 'PENDING_RENEWAL' THEN 0.7
            WHEN rs.CERT_STATUS = 'EXPIRED' THEN 0.3
            ELSE 0.5
        END) AS CERT_FRESHNESS_FACTOR,
        AVG(rs.RISK_SCORE) AS AVG_RISK_SCORE
    FROM DCA_DEMO.GOVERNANCE.DCIM_RISK_SCORES rs
    GROUP BY rs.DATA_CENTER, rs.SLA_TIER
),
sla_targets AS (
    -- SLA tier target MTTR in minutes
    SELECT 'PLATINUM' AS SLA_TIER, 15 AS SLA_TARGET_MINUTES UNION ALL
    SELECT 'GOLD', 30 UNION ALL
    SELECT 'SILVER', 60 UNION ALL
    SELECT 'BRONZE', 120
)
SELECT
    mb.DATA_CENTER_NAME,
    mb.PRIORITY,
    COALESCE(rbd.SLA_TIER, 'UNKNOWN') AS SLA_TIER,
    ROUND(mb.AVG_MTTR_MINUTES, 1) AS AVG_RAW_MTTR_MINUTES,
    ROUND(COALESCE(rbd.CERT_FRESHNESS_FACTOR, 1.0), 2) AS CERT_FRESHNESS_FACTOR,
    -- Risk-adjusted MTTR: raw MTTR inflated by inverse of cert freshness
    ROUND(mb.AVG_MTTR_MINUTES / NULLIF(COALESCE(rbd.CERT_FRESHNESS_FACTOR, 1.0), 0), 1) AS RISK_ADJUSTED_MTTR,
    st.SLA_TARGET_MINUTES,
    -- SLA breach percentage: how often does adjusted MTTR exceed target?
    ROUND(
        CASE WHEN mb.AVG_MTTR_MINUTES / NULLIF(COALESCE(rbd.CERT_FRESHNESS_FACTOR, 1.0), 0) > st.SLA_TARGET_MINUTES
             THEN 100.0
             ELSE (mb.AVG_MTTR_MINUTES / NULLIF(COALESCE(rbd.CERT_FRESHNESS_FACTOR, 1.0), 0)) / NULLIF(st.SLA_TARGET_MINUTES, 0) * 100.0
        END, 1) AS SLA_BREACH_PCT,
    mb.INCIDENTS_COUNT AS INCIDENT_COUNT,
    mb.CALCULATED_AT
FROM mttr_base mb
LEFT JOIN risk_by_dc rbd
    ON mb.DATA_CENTER_NAME = rbd.DATA_CENTER_NAME
LEFT JOIN sla_targets st
    ON rbd.SLA_TIER = st.SLA_TIER;

-- ═══════════════════════════════════════════════════════════════════════════
-- VIEW 3: DCIM_PORT_HEALTH_BY_BUSINESS_PRIORITY
-- ═══════════════════════════════════════════════════════════════════════════
-- Port health heatmap data filtered by business priority from ServiceNow
-- SLA tiers. Answers: "Which switches have the worst port health, and what
-- is the business impact?"
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW DCA_DEMO.GOVERNANCE.DCIM_PORT_HEALTH_BY_BUSINESS_PRIORITY
    COMMENT = 'Port health heatmap by switch and SLA tier. Shows healthy/degraded/critical port counts for each switch with business impact scoring.'
AS
WITH latest_port_metrics AS (
    -- Get the most recent metric window per port (last interval)
    SELECT
        pm.PORT_ID,
        pm.SWITCH_ID,
        pm.CRC_ERRORS,
        pm.INPUT_ERRORS,
        pm.OUTPUT_ERRORS,
        pm.UTILIZATION_PCT,
        pm.LINK_STATUS,
        -- Error rate proxy: total errors relative to packet count
        CASE
            WHEN pm.CRC_ERRORS = 0 AND pm.INPUT_ERRORS = 0 AND pm.OUTPUT_ERRORS = 0 THEN 0.0
            ELSE (pm.CRC_ERRORS + pm.INPUT_ERRORS + pm.OUTPUT_ERRORS)::FLOAT
        END AS TOTAL_ERRORS,
        ROW_NUMBER() OVER (PARTITION BY pm.PORT_ID ORDER BY pm.METRIC_TIMESTAMP DESC) AS RN
    FROM CURATED_DEV.TELEMETRY.FACT_PORT_METRICS pm
),
port_health AS (
    SELECT
        lpm.SWITCH_ID,
        COUNT(*) AS TOTAL_PORTS,
        COUNT(CASE WHEN lpm.TOTAL_ERRORS < 1 AND lpm.LINK_STATUS = 'UP' THEN 1 END) AS HEALTHY_PORTS,
        COUNT(CASE WHEN lpm.TOTAL_ERRORS >= 1 AND lpm.TOTAL_ERRORS < 10 THEN 1 END) AS DEGRADED_PORTS,
        COUNT(CASE WHEN lpm.TOTAL_ERRORS >= 10 OR lpm.LINK_STATUS IN ('DOWN', 'FLAPPING') THEN 1 END) AS CRITICAL_PORTS,
        -- Dominant error type
        CASE
            WHEN SUM(lpm.CRC_ERRORS) >= SUM(lpm.INPUT_ERRORS) AND SUM(lpm.CRC_ERRORS) >= SUM(lpm.OUTPUT_ERRORS) THEN 'CRC_ERRORS'
            WHEN SUM(lpm.INPUT_ERRORS) >= SUM(lpm.OUTPUT_ERRORS) THEN 'INPUT_ERRORS'
            ELSE 'OUTPUT_ERRORS'
        END AS TOP_ERROR_TYPE
    FROM latest_port_metrics lpm
    WHERE lpm.RN = 1
    GROUP BY lpm.SWITCH_ID
),
switch_location AS (
    SELECT
        sw.SWITCH_ID,
        sw.SWITCH_NAME,
        sw.SLA_TIER,
        r.RACK_NAME,
        h.HALL_NAME,
        dc.DC_NAME AS DATA_CENTER_NAME
    FROM CURATED_DEV.SERVICENOW.DIM_SWITCH sw
    JOIN CURATED_DEV.SERVICENOW.DIM_RACK r ON sw.RACK_ID = r.RACK_ID
    JOIN CURATED_DEV.SERVICENOW.DIM_HALL h ON r.HALL_ID = h.HALL_ID
    JOIN CURATED_DEV.SERVICENOW.DIM_DATA_CENTER dc ON h.DATA_CENTER_ID = dc.DATA_CENTER_ID
)
SELECT
    sl.DATA_CENTER_NAME,
    sl.HALL_NAME,
    sl.RACK_NAME,
    sl.SWITCH_NAME,
    COALESCE(sl.SLA_TIER, 'UNKNOWN') AS SLA_TIER,
    COALESCE(ph.TOTAL_PORTS, 0) AS TOTAL_PORTS,
    COALESCE(ph.HEALTHY_PORTS, 0) AS HEALTHY_PORTS,
    COALESCE(ph.DEGRADED_PORTS, 0) AS DEGRADED_PORTS,
    COALESCE(ph.CRITICAL_PORTS, 0) AS CRITICAL_PORTS,
    -- Health score: 0-100 weighted by port health
    ROUND(
        CASE WHEN COALESCE(ph.TOTAL_PORTS, 0) = 0 THEN 100.0
             ELSE (COALESCE(ph.HEALTHY_PORTS, 0) * 100.0
                   + COALESCE(ph.DEGRADED_PORTS, 0) * 50.0
                   + COALESCE(ph.CRITICAL_PORTS, 0) * 0.0)
                  / NULLIF(ph.TOTAL_PORTS, 0)
        END, 1) AS HEALTH_SCORE,
    -- Business impact: health score weighted by SLA tier
    ROUND(
        (CASE WHEN COALESCE(ph.TOTAL_PORTS, 0) = 0 THEN 100.0
              ELSE (COALESCE(ph.HEALTHY_PORTS, 0) * 100.0
                    + COALESCE(ph.DEGRADED_PORTS, 0) * 50.0
                    + COALESCE(ph.CRITICAL_PORTS, 0) * 0.0)
                   / NULLIF(ph.TOTAL_PORTS, 0)
         END) *
        (CASE sl.SLA_TIER
            WHEN 'PLATINUM' THEN 1.0
            WHEN 'GOLD' THEN 0.75
            WHEN 'SILVER' THEN 0.5
            WHEN 'BRONZE' THEN 0.25
            ELSE 0.5
         END), 1) AS BUSINESS_IMPACT_SCORE,
    COALESCE(ph.TOP_ERROR_TYPE, 'NONE') AS TOP_ERROR_TYPE
FROM switch_location sl
LEFT JOIN port_health ph ON sl.SWITCH_ID = ph.SWITCH_ID;

-- ═══════════════════════════════════════════════════════════════════════════
-- GRANTS
-- ═══════════════════════════════════════════════════════════════════════════

GRANT SELECT ON VIEW DCA_DEMO.GOVERNANCE.DCIM_SYSTEM_UPTIME_VS_STAFF_AVAILABILITY TO ROLE DATA_STEWARD;
GRANT SELECT ON VIEW DCA_DEMO.GOVERNANCE.DCIM_RISK_WEIGHTED_MTTR TO ROLE DATA_STEWARD;
GRANT SELECT ON VIEW DCA_DEMO.GOVERNANCE.DCIM_PORT_HEALTH_BY_BUSINESS_PRIORITY TO ROLE DATA_STEWARD;

GRANT SELECT ON VIEW DCA_DEMO.GOVERNANCE.DCIM_SYSTEM_UPTIME_VS_STAFF_AVAILABILITY TO ROLE ONTOLOGY_ADMIN;
GRANT SELECT ON VIEW DCA_DEMO.GOVERNANCE.DCIM_RISK_WEIGHTED_MTTR TO ROLE ONTOLOGY_ADMIN;
GRANT SELECT ON VIEW DCA_DEMO.GOVERNANCE.DCIM_PORT_HEALTH_BY_BUSINESS_PRIORITY TO ROLE ONTOLOGY_ADMIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

SELECT 'DCIM semantic views created successfully' AS STATUS;
