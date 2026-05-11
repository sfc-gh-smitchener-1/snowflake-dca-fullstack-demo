-- ============================================================================
-- DCIM KNOWLEDGE GRAPH — CRITICAL MAINTENANCE GAP RISK SCORING
-- ============================================================================
-- Detects the "Critical Maintenance Gap" pattern:
--   Switch with elevated error rate + assigned technician with expired cert
--   = Risk that qualified maintenance cannot be performed
--
-- Also computes Mean Time To Repair (MTTR) analytics per data center.
--
-- Prerequisites: scripts 01-05 deployed, DCIM data loaded and curated
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE DCA_DEMO;
USE SCHEMA GOVERNANCE;
USE WAREHOUSE COMPUTE_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 1: SP_DCIM_RISK_SCORING
-- ═══════════════════════════════════════════════════════════════════════════
-- Joins switch telemetry, incidents, and technician certifications to
-- detect "Critical Maintenance Gap" — switches with high error rates
-- assigned to technicians whose relevant certifications have expired.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_DCIM_RISK_SCORING()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_row_count INTEGER DEFAULT 0;
    v_switch_exists INTEGER DEFAULT 0;
    v_incident_exists INTEGER DEFAULT 0;
    v_cert_exists INTEGER DEFAULT 0;
BEGIN

    -- Check required tables exist
    SELECT COUNT(*) INTO :v_switch_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'SERVICENOW' AND table_name = 'DIM_SWITCH';

    SELECT COUNT(*) INTO :v_incident_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'SERVICENOW' AND table_name = 'FACT_INCIDENTS';

    SELECT COUNT(*) INTO :v_cert_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'WORKDAY_DCIM' AND table_name = 'DIM_CERTIFICATION';

    IF (:v_switch_exists = 0 OR :v_incident_exists = 0 OR :v_cert_exists = 0) THEN
        RETURN 'Risk scoring skipped — required tables not found (DIM_SWITCH=' || :v_switch_exists
            || ', FACT_INCIDENTS=' || :v_incident_exists
            || ', DIM_CERTIFICATION=' || :v_cert_exists || ')';
    END IF;

    -- Build risk scores: join switches with elevated errors to incidents
    -- and check assigned technician's certification status
    CREATE OR REPLACE TABLE DCA_DEMO.GOVERNANCE.DCIM_RISK_SCORES AS
    WITH switch_errors AS (
        -- Aggregate latest switch health to get average error rate
        SELECT
            sh.SWITCH_ID,
            AVG(sh.ERROR_RATE_PCT) AS avg_error_rate,
            MAX(sh.TIMESTAMP) AS last_reading
        FROM CURATED_DEV.TELEMETRY.FACT_SWITCH_HEALTH sh
        GROUP BY sh.SWITCH_ID
    ),
    problem_switches AS (
        SELECT
            se.SWITCH_ID,
            se.avg_error_rate,
            se.last_reading,
            sw.CURRENT_RACK_ID AS rack_id,
            sw.MODEL AS switch_model,
            sw.FIRMWARE_VERSION,
            dc.DATA_CENTER_ID,
            dc.DC_NAME AS data_center,
            dc.SLA_TIER
        FROM switch_errors se
        JOIN CURATED_DEV.SERVICENOW.DIM_SWITCH sw
            ON se.SWITCH_ID = sw.SWITCH_ID
        LEFT JOIN CURATED_DEV.SERVICENOW.DIM_RACK r
            ON sw.CURRENT_RACK_ID = r.RACK_ID
        LEFT JOIN CURATED_DEV.SERVICENOW.DIM_HALL h
            ON r.HALL_ID = h.HALL_ID
        LEFT JOIN CURATED_DEV.SERVICENOW.DIM_DATA_CENTER dc
            ON h.DATA_CENTER_ID = dc.DATA_CENTER_ID
    ),
    incident_techs AS (
        -- Find most recent incident per switch and its assigned technician
        SELECT
            inc.SWITCH_ID,
            inc.INCIDENT_ID,
            inc.ASSIGNED_TECHNICIAN AS technician_id,
            inc.PRIORITY,
            inc.CATEGORY,
            inc.STATUS AS incident_status,
            inc.RESOLUTION_TIME_MINUTES,
            ROW_NUMBER() OVER (PARTITION BY inc.SWITCH_ID ORDER BY inc.CREATED_AT DESC) AS rn
        FROM CURATED_DEV.SERVICENOW.FACT_INCIDENTS inc
        WHERE inc.ASSIGNED_TECHNICIAN IS NOT NULL
    ),
    tech_certs AS (
        -- Get each technician's most critical certification and its status
        SELECT
            c.WORKER_ID,
            t.WORKER_NAME AS technician_name,
            c.CERT_TYPE,
            c.STATUS AS cert_status,
            c.EXPIRY_DATE AS cert_expiry_date,
            ROW_NUMBER() OVER (
                PARTITION BY c.WORKER_ID
                ORDER BY CASE c.STATUS
                    WHEN 'EXPIRED' THEN 1
                    WHEN 'PENDING_RENEWAL' THEN 2
                    WHEN 'ACTIVE' THEN 3
                    ELSE 4
                END
            ) AS rn
        FROM CURATED_DEV.WORKDAY_DCIM.DIM_CERTIFICATION c
        JOIN CURATED_DEV.WORKDAY_DCIM.DIM_TECHNICIAN t
            ON c.WORKER_ID = t.WORKER_ID
    )
    SELECT
        ps.SWITCH_ID,
        COALESCE(ps.switch_model, 'Unknown') AS switch_name,
        ps.data_center,
        ps.rack_id,
        ROUND(ps.avg_error_rate, 3) AS error_rate_pct,
        it.technician_id AS assigned_technician_id,
        tc.technician_name,
        COALESCE(tc.cert_status, 'UNKNOWN') AS cert_status,
        tc.cert_expiry_date,
        -- Risk level determination
        CASE
            WHEN ps.avg_error_rate > 2.0 AND COALESCE(tc.cert_status, 'UNKNOWN') IN ('EXPIRED', 'UNKNOWN')
                THEN 'HIGH'
            WHEN ps.avg_error_rate > 2.0 AND COALESCE(tc.cert_status, 'UNKNOWN') IN ('ACTIVE', 'PENDING_RENEWAL')
                THEN 'MEDIUM'
            WHEN ps.avg_error_rate <= 2.0 AND COALESCE(tc.cert_status, 'UNKNOWN') IN ('EXPIRED', 'UNKNOWN')
                THEN 'LOW'
            ELSE 'NOMINAL'
        END AS risk_level,
        -- Risk score formula: error_rate(40%) + cert_gap(30%) + sla_tier(30%)
        ROUND(
            (LEAST(ps.avg_error_rate / 5.0, 1.0) * 40)
            + (CASE
                WHEN COALESCE(tc.cert_status, 'UNKNOWN') = 'EXPIRED' THEN 1.0
                WHEN COALESCE(tc.cert_status, 'UNKNOWN') = 'PENDING_RENEWAL' THEN 0.5
                ELSE 0.0
              END * 30)
            + (CASE COALESCE(ps.SLA_TIER, 'BRONZE')
                WHEN 'PLATINUM' THEN 1.0
                WHEN 'GOLD' THEN 0.75
                WHEN 'SILVER' THEN 0.5
                WHEN 'BRONZE' THEN 0.25
                ELSE 0.25
              END * 30)
        , 1) AS risk_score,
        COALESCE(ps.SLA_TIER, 'BRONZE') AS sla_tier,
        CASE
            WHEN COALESCE(ps.SLA_TIER, 'BRONZE') IN ('PLATINUM', 'GOLD') AND ps.avg_error_rate > 2.0
                THEN 'HIGH — Production-critical switch with degraded performance'
            WHEN ps.avg_error_rate > 2.0
                THEN 'MEDIUM — Switch error rate elevated'
            ELSE 'LOW — Certification gap without active equipment issue'
        END AS business_impact,
        CURRENT_TIMESTAMP() AS calculated_at
    FROM problem_switches ps
    LEFT JOIN incident_techs it
        ON ps.SWITCH_ID = it.SWITCH_ID AND it.rn = 1
    LEFT JOIN tech_certs tc
        ON it.technician_id = tc.WORKER_ID AND tc.rn = 1
    WHERE ps.avg_error_rate > 0.5  -- Only include switches with non-trivial error rates
       OR COALESCE(tc.cert_status, 'ACTIVE') IN ('EXPIRED', 'UNKNOWN');

    SELECT COUNT(*) INTO :v_row_count
    FROM DCA_DEMO.GOVERNANCE.DCIM_RISK_SCORES;

    RETURN 'Risk scoring complete. Scored switches: ' || :v_row_count
        || ' | HIGH: ' || (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.DCIM_RISK_SCORES WHERE risk_level = 'HIGH')
        || ' | MEDIUM: ' || (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.DCIM_RISK_SCORES WHERE risk_level = 'MEDIUM')
        || ' | LOW: ' || (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.DCIM_RISK_SCORES WHERE risk_level = 'LOW');
END;


-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 2: SP_DCIM_MTTR_ANALYSIS
-- ═══════════════════════════════════════════════════════════════════════════
-- Computes Mean Time To Repair (MTTR) analytics grouped by data center,
-- priority, and shift coverage to identify operational bottlenecks.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_DCIM_MTTR_ANALYSIS()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_row_count INTEGER DEFAULT 0;
    v_inc_exists INTEGER DEFAULT 0;
BEGIN

    SELECT COUNT(*) INTO :v_inc_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'SERVICENOW' AND table_name = 'FACT_INCIDENTS';

    IF (:v_inc_exists = 0) THEN
        RETURN 'MTTR analysis skipped — FACT_INCIDENTS table not found.';
    END IF;

    CREATE OR REPLACE TABLE DCA_DEMO.GOVERNANCE.DCIM_MTTR_METRICS AS
    WITH incident_details AS (
        SELECT
            inc.INCIDENT_ID,
            inc.SWITCH_ID,
            inc.PRIORITY,
            inc.RESOLUTION_TIME_MINUTES,
            inc.CREATED_AT,
            -- Determine shift coverage at incident time
            CASE
                WHEN HOUR(inc.CREATED_AT) BETWEEN 6 AND 13 THEN 'DAY'
                WHEN HOUR(inc.CREATED_AT) BETWEEN 14 AND 21 THEN 'SWING'
                ELSE 'NIGHT'
            END AS shift_period,
            sw.CURRENT_RACK_ID
        FROM CURATED_DEV.SERVICENOW.FACT_INCIDENTS inc
        LEFT JOIN CURATED_DEV.SERVICENOW.DIM_SWITCH sw
            ON inc.SWITCH_ID = sw.SWITCH_ID
        WHERE inc.RESOLUTION_TIME_MINUTES IS NOT NULL
    ),
    dc_mapping AS (
        SELECT
            r.RACK_ID,
            h.HALL_ID,
            dc.DATA_CENTER_ID,
            dc.DC_NAME
        FROM CURATED_DEV.SERVICENOW.DIM_RACK r
        JOIN CURATED_DEV.SERVICENOW.DIM_HALL h ON r.HALL_ID = h.HALL_ID
        JOIN CURATED_DEV.SERVICENOW.DIM_DATA_CENTER dc ON h.DATA_CENTER_ID = dc.DATA_CENTER_ID
    )
    SELECT
        dm.DATA_CENTER_ID AS data_center_id,
        dm.DC_NAME AS dc_name,
        id.PRIORITY AS priority,
        ROUND(AVG(id.RESOLUTION_TIME_MINUTES), 1) AS avg_mttr_minutes,
        ROUND(MEDIAN(id.RESOLUTION_TIME_MINUTES), 1) AS median_mttr_minutes,
        ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY id.RESOLUTION_TIME_MINUTES), 1) AS p95_mttr_minutes,
        COUNT(*) AS incidents_count,
        ROUND(
            SUM(CASE WHEN id.shift_period = 'DAY' THEN 1 ELSE 0 END) * 100.0
            / NULLIF(COUNT(*), 0)
        , 1) AS staff_available_pct,
        CURRENT_TIMESTAMP() AS calculated_at
    FROM incident_details id
    LEFT JOIN dc_mapping dm ON id.CURRENT_RACK_ID = dm.RACK_ID
    GROUP BY dm.DATA_CENTER_ID, dm.DC_NAME, id.PRIORITY;

    SELECT COUNT(*) INTO :v_row_count
    FROM DCA_DEMO.GOVERNANCE.DCIM_MTTR_METRICS;

    RETURN 'MTTR analysis complete. Metric rows: ' || :v_row_count;
END;
