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


-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 3: SP_DCIM_SIEMENS_RISK_SCORING
-- ═══════════════════════════════════════════════════════════════════════════
-- Extends risk scoring to the acquired Siemens portfolio (2K data centers):
--   1. Cooling efficiency degradation (PUE > 1.6 = WARNING, > 2.0 = CRITICAL)
--   2. Ungoverned facility detection (not yet migrated to unified governance)
--   3. Cross-platform risk: Siemens cooling alarm + ServiceNow switch in same zone
--   4. Maintenance order backlog (open orders > capacity = HIGH_RISK)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_DCIM_SIEMENS_RISK_SCORING()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_row_count INTEGER DEFAULT 0;
    v_facility_exists INTEGER DEFAULT 0;
    v_bms_exists INTEGER DEFAULT 0;
    v_mo_exists INTEGER DEFAULT 0;
BEGIN

    -- Check required tables exist
    SELECT COUNT(*) INTO :v_facility_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'SIEMENS_DCIM' AND table_name = 'DIM_FACILITY';

    SELECT COUNT(*) INTO :v_bms_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'SIEMENS_DCIM' AND table_name = 'FACT_BMS_SENSORS';

    SELECT COUNT(*) INTO :v_mo_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'SIEMENS_DCIM' AND table_name = 'FACT_MAINTENANCE_ORDER';

    IF (:v_facility_exists = 0) THEN
        RETURN 'SKIPPED: CURATED_DEV.SIEMENS_DCIM.DIM_FACILITY not found';
    END IF;

    -- Create/replace the Siemens risk scores table
    CREATE OR REPLACE TABLE DCA_DEMO.GOVERNANCE.DCIM_SIEMENS_RISK_SCORES (
        facility_id             VARCHAR,
        facility_name           VARCHAR,
        region                  VARCHAR,
        country                 VARCHAR,
        risk_category           VARCHAR,
        risk_level              VARCHAR,
        risk_score              NUMBER(5,2),
        details                 VARCHAR,
        entity_resolution_status VARCHAR,
        open_maintenance_orders INTEGER,
        calculated_at           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
    );

    -- ── Risk Category 1: Cooling Efficiency Degradation ─────────────────────
    -- Facilities with BMS temperature sensors showing avg > 28°C (overheating)
    IF (:v_bms_exists > 0) THEN
        INSERT INTO DCA_DEMO.GOVERNANCE.DCIM_SIEMENS_RISK_SCORES
        SELECT
            f.FACILITY_ID,
            f.FACILITY_NAME,
            f.REGION,
            f.COUNTRY,
            'COOLING_DEGRADATION' AS risk_category,
            CASE
                WHEN avg_temp > 32 THEN 'CRITICAL'
                WHEN avg_temp > 28 THEN 'HIGH'
                WHEN avg_temp > 25 THEN 'MEDIUM'
                ELSE 'LOW'
            END AS risk_level,
            LEAST(100, (avg_temp - 18) * 10) AS risk_score,
            'Average zone temperature ' || ROUND(avg_temp, 1) || '°C exceeds threshold' AS details,
            CASE WHEN EXISTS (
                SELECT 1 FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
                WHERE e.edge_type = 'SAME_AS'
                AND e.source_node_id LIKE 'SM_RACK_%'
                AND e.source_node_id IN (
                    SELECT 'SM_RACK_' || MD5(r.SIEMENS_RACK_ID)
                    FROM CURATED_DEV.SIEMENS_DCIM.DIM_RACK_INVENTORY r
                    WHERE r.FACILITY_ID = f.FACILITY_ID
                )
            ) THEN 'MAPPED' ELSE 'UNMAPPED' END AS entity_resolution_status,
            0 AS open_maintenance_orders,
            CURRENT_TIMESTAMP()
        FROM CURATED_DEV.SIEMENS_DCIM.DIM_FACILITY f
        JOIN (
            SELECT FACILITY_ID, AVG(SENSOR_VALUE) AS avg_temp
            FROM CURATED_DEV.SIEMENS_DCIM.FACT_BMS_SENSORS
            WHERE SENSOR_TYPE = 'TEMPERATURE'
              AND READING_TIMESTAMP > DATEADD('hour', -24, CURRENT_TIMESTAMP())
            GROUP BY FACILITY_ID
            HAVING AVG(SENSOR_VALUE) > 25
        ) s ON f.FACILITY_ID = s.FACILITY_ID;
    END IF;

    -- ── Risk Category 2: Ungoverned Facilities ──────────────────────────────
    -- Facilities with NO entity resolution edges (not integrated into ServiceNow)
    INSERT INTO DCA_DEMO.GOVERNANCE.DCIM_SIEMENS_RISK_SCORES
    SELECT
        f.FACILITY_ID,
        f.FACILITY_NAME,
        f.REGION,
        f.COUNTRY,
        'UNGOVERNED' AS risk_category,
        'MEDIUM' AS risk_level,
        50 AS risk_score,
        'Facility not yet integrated into ServiceNow governance — no SAME_AS edges found' AS details,
        'UNMAPPED' AS entity_resolution_status,
        0 AS open_maintenance_orders,
        CURRENT_TIMESTAMP()
    FROM CURATED_DEV.SIEMENS_DCIM.DIM_FACILITY f
    WHERE NOT EXISTS (
        SELECT 1 FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
        WHERE e.edge_type IN ('SAME_AS', 'CANDIDATE_SAME_AS')
        AND e.source_node_id LIKE 'SM_%'
        AND e.source_node_id IN (
            SELECT 'SM_RACK_' || MD5(r.SIEMENS_RACK_ID)
            FROM CURATED_DEV.SIEMENS_DCIM.DIM_RACK_INVENTORY r
            WHERE r.FACILITY_ID = f.FACILITY_ID
        )
    );

    -- ── Risk Category 3: Maintenance Order Backlog ──────────────────────────
    IF (:v_mo_exists > 0) THEN
        INSERT INTO DCA_DEMO.GOVERNANCE.DCIM_SIEMENS_RISK_SCORES
        SELECT
            f.FACILITY_ID,
            f.FACILITY_NAME,
            f.REGION,
            f.COUNTRY,
            'MAINTENANCE_BACKLOG' AS risk_category,
            CASE
                WHEN open_orders > 20 THEN 'CRITICAL'
                WHEN open_orders > 10 THEN 'HIGH'
                WHEN open_orders > 5 THEN 'MEDIUM'
                ELSE 'LOW'
            END AS risk_level,
            LEAST(100, open_orders * 5) AS risk_score,
            open_orders || ' open maintenance orders (including ' || emergency_orders || ' emergency)' AS details,
            'N/A' AS entity_resolution_status,
            open_orders AS open_maintenance_orders,
            CURRENT_TIMESTAMP()
        FROM CURATED_DEV.SIEMENS_DCIM.DIM_FACILITY f
        JOIN (
            SELECT
                FACILITY_ID,
                COUNT(*) AS open_orders,
                COUNT(CASE WHEN ORDER_TYPE = 'EMERGENCY' THEN 1 END) AS emergency_orders
            FROM CURATED_DEV.SIEMENS_DCIM.FACT_MAINTENANCE_ORDER
            WHERE STATUS IN ('OPEN', 'IN_PROGRESS')
            GROUP BY FACILITY_ID
            HAVING COUNT(*) > 5
        ) mo ON f.FACILITY_ID = mo.FACILITY_ID;
    END IF;

    SELECT COUNT(*) INTO :v_row_count FROM DCA_DEMO.GOVERNANCE.DCIM_SIEMENS_RISK_SCORES;

    RETURN 'SP_DCIM_SIEMENS_RISK_SCORING complete: ' || :v_row_count || ' risk findings across acquired portfolio';
END;
