-- ============================================================================
-- DCIM KNOWLEDGE GRAPH — RAI INFERENCE: NEAREST QUALIFIED TECHNICIAN
-- ============================================================================
-- Extends the base RAI inference with DCIM-specific dispatch logic:
--   1. For each HIGH_RISK switch, traverse the graph to find the physical
--      location (switch → rack → hall → data center)
--   2. Find on-shift technicians at the same campus with valid certs
--   3. Rank by proficiency, past performance, and proximity
--   4. Write risk findings back as RAI recommendation nodes
--
-- Prerequisites: 06_dcim_risk_scoring.sql deployed
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE DCA_DEMO;
USE SCHEMA GOVERNANCE;
USE WAREHOUSE COMPUTE_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 1: SP_DCIM_NEAREST_QUALIFIED_TECH
-- ═══════════════════════════════════════════════════════════════════════════
-- Graph traversal to find optimal technician dispatch for high-risk switches.
-- Considers campus proximity, shift status, certification validity, and
-- historical incident resolution performance.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_DCIM_NEAREST_QUALIFIED_TECH()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_row_count INTEGER DEFAULT 0;
    v_risk_exists INTEGER DEFAULT 0;
    v_tech_exists INTEGER DEFAULT 0;
    v_shift_exists INTEGER DEFAULT 0;
BEGIN

    -- Check prerequisites
    SELECT COUNT(*) INTO :v_risk_exists
    FROM DCA_DEMO.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'GOVERNANCE' AND table_name = 'DCIM_RISK_SCORES';

    SELECT COUNT(*) INTO :v_tech_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'WORKDAY_DCIM' AND table_name = 'DIM_TECHNICIAN';

    SELECT COUNT(*) INTO :v_shift_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'WORKDAY_DCIM' AND table_name = 'FACT_SHIFTS';

    IF (:v_risk_exists = 0 OR :v_tech_exists = 0 OR :v_shift_exists = 0) THEN
        RETURN 'Dispatch recommendation skipped — required tables not found (DCIM_RISK_SCORES='
            || :v_risk_exists || ', DIM_TECHNICIAN=' || :v_tech_exists
            || ', FACT_SHIFTS=' || :v_shift_exists || ')';
    END IF;

    CREATE OR REPLACE TABLE DCA_DEMO.GOVERNANCE.DCIM_DISPATCH_RECOMMENDATIONS AS
    WITH high_risk_switches AS (
        SELECT
            rs.SWITCH_ID,
            rs.switch_name,
            rs.data_center,
            rs.rack_id,
            rs.risk_level,
            rs.risk_score,
            rs.assigned_technician_id,
            -- Get the data center node to determine campus
            n_dc.properties:campus_id::VARCHAR AS campus_id
        FROM DCA_DEMO.GOVERNANCE.DCIM_RISK_SCORES rs
        LEFT JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n_sw
            ON n_sw.node_id = 'DC_SW_' || MD5(rs.SWITCH_ID)
        -- Traverse: switch → rack → hall → data_center
        LEFT JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e_sir
            ON e_sir.source_node_id = n_sw.node_id
            AND e_sir.edge_type = 'SWITCH_IN_RACK'
        LEFT JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e_rih
            ON e_rih.source_node_id = e_sir.target_node_id
            AND e_rih.edge_type = 'RACK_IN_HALL'
        LEFT JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e_hidc
            ON e_hidc.source_node_id = e_rih.target_node_id
            AND e_hidc.edge_type = 'HALL_IN_DC'
        LEFT JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n_dc
            ON n_dc.node_id = e_hidc.target_node_id
        WHERE rs.risk_level IN ('HIGH', 'MEDIUM')
    ),
    -- Get most recent incident per switch for context
    switch_incidents AS (
        SELECT
            inc.SWITCH_ID,
            inc.INCIDENT_ID,
            inc.CATEGORY,
            ROW_NUMBER() OVER (PARTITION BY inc.SWITCH_ID ORDER BY inc.CREATED_AT DESC) AS rn
        FROM CURATED_DEV.SERVICENOW.FACT_INCIDENTS inc
    ),
    -- Find technicians with their campus, shift status, and certifications
    available_techs AS (
        SELECT
            t.WORKER_ID,
            t.WORKER_NAME AS tech_name,
            t.CURRENT_CAMPUS_ASSIGNMENT AS tech_campus_id,
            t.CURRENT_TEAM AS tech_team,
            c.CERT_TYPE,
            c.STATUS AS cert_status,
            c.PROFICIENCY_LEVEL,
            -- Check if on shift today
            CASE
                WHEN EXISTS (
                    SELECT 1 FROM CURATED_DEV.WORKDAY_DCIM.FACT_SHIFTS s
                    WHERE s.WORKER_ID = t.WORKER_ID
                      AND s.SHIFT_DATE = CURRENT_DATE()
                ) THEN TRUE
                ELSE FALSE
            END AS on_shift
        FROM CURATED_DEV.WORKDAY_DCIM.DIM_TECHNICIAN t
        LEFT JOIN CURATED_DEV.WORKDAY_DCIM.DIM_CERTIFICATION c
            ON t.WORKER_ID = c.WORKER_ID
            AND c.STATUS = 'ACTIVE'
    ),
    -- Count past resolutions per technician for performance ranking
    tech_performance AS (
        SELECT
            inc.ASSIGNED_TECHNICIAN AS worker_id,
            COUNT(*) AS resolved_incidents,
            AVG(inc.RESOLUTION_TIME_MINUTES) AS avg_resolution_time
        FROM CURATED_DEV.SERVICENOW.FACT_INCIDENTS inc
        WHERE inc.RESOLUTION_TIME_MINUTES IS NOT NULL
          AND inc.ASSIGNED_TECHNICIAN IS NOT NULL
        GROUP BY inc.ASSIGNED_TECHNICIAN
    ),
    -- Cross-join high-risk switches with available techs and score
    candidates AS (
        SELECT
            hrs.SWITCH_ID,
            si.INCIDENT_ID,
            at.WORKER_ID AS recommended_technician_id,
            at.tech_name,
            -- Proximity scoring
            CASE
                WHEN at.tech_campus_id = hrs.campus_id THEN 'SAME_DC'
                ELSE 'SAME_CAMPUS'
            END AS campus_match,
            at.CERT_TYPE,
            at.cert_status,
            COALESCE(at.PROFICIENCY_LEVEL, 0) AS proficiency_level,
            at.on_shift,
            -- Dispatch score: proximity(30) + cert_proficiency(30) + performance(20) + on_shift(20)
            ROUND(
                (CASE
                    WHEN at.tech_campus_id = hrs.campus_id THEN 30
                    ELSE 10
                END)
                + (COALESCE(at.PROFICIENCY_LEVEL, 0) * 6)  -- 0-5 scale * 6 = 0-30
                + (LEAST(COALESCE(tp.resolved_incidents, 0) / 50.0, 1.0) * 20)
                + (CASE WHEN at.on_shift THEN 20 ELSE 0 END)
            , 1) AS dispatch_score,
            -- Reasoning
            'Tech ' || at.tech_name
                || ' | Campus: ' || campus_match
                || ' | Cert: ' || COALESCE(at.CERT_TYPE, 'N/A') || ' (' || COALESCE(at.cert_status, 'N/A') || ')'
                || ' | Proficiency: ' || COALESCE(at.PROFICIENCY_LEVEL, 0)
                || ' | On-shift: ' || CASE WHEN at.on_shift THEN 'YES' ELSE 'NO' END
                || ' | Past resolutions: ' || COALESCE(tp.resolved_incidents, 0)
            AS reasoning,
            ROW_NUMBER() OVER (
                PARTITION BY hrs.SWITCH_ID
                ORDER BY
                    CASE WHEN at.on_shift THEN 0 ELSE 1 END,
                    CASE WHEN at.tech_campus_id = hrs.campus_id THEN 0 ELSE 1 END,
                    COALESCE(at.PROFICIENCY_LEVEL, 0) DESC,
                    COALESCE(tp.resolved_incidents, 0) DESC
            ) AS rank_num
        FROM high_risk_switches hrs
        LEFT JOIN switch_incidents si
            ON hrs.SWITCH_ID = si.SWITCH_ID AND si.rn = 1
        CROSS JOIN available_techs at
        LEFT JOIN tech_performance tp
            ON at.WORKER_ID = tp.worker_id
        WHERE at.on_shift = TRUE
          AND at.cert_status = 'ACTIVE'
    )
    SELECT
        MD5(SWITCH_ID || '-' || recommended_technician_id) AS recommendation_id,
        SWITCH_ID AS switch_id,
        INCIDENT_ID AS incident_id,
        recommended_technician_id,
        tech_name,
        campus_match,
        CERT_TYPE AS cert_type,
        cert_status,
        proficiency_level,
        on_shift,
        dispatch_score,
        reasoning,
        CURRENT_TIMESTAMP() AS created_at
    FROM candidates
    WHERE rank_num <= 3;  -- Top 3 candidates per switch

    SELECT COUNT(*) INTO :v_row_count
    FROM DCA_DEMO.GOVERNANCE.DCIM_DISPATCH_RECOMMENDATIONS;

    RETURN 'Dispatch recommendations complete. Recommendations: ' || :v_row_count;
END;


-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 2: SP_DCIM_UPDATE_RISK_NODES
-- ═══════════════════════════════════════════════════════════════════════════
-- Writes risk findings back into the RAI recommendations table as
-- MAINTENANCE_GAP recommendations for graph-based visibility.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_DCIM_UPDATE_RISK_NODES()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_inserted INTEGER DEFAULT 0;
    v_risk_exists INTEGER DEFAULT 0;
BEGIN

    SELECT COUNT(*) INTO :v_risk_exists
    FROM DCA_DEMO.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'GOVERNANCE' AND table_name = 'DCIM_RISK_SCORES';

    IF (:v_risk_exists = 0) THEN
        RETURN 'Risk node update skipped — DCIM_RISK_SCORES table not found.';
    END IF;

    -- Insert maintenance gap recommendations into the RAI recommendations table
    INSERT INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS
        (recommendation_type, severity, source_node_id, target_node_id, description, suggested_action, status)
    SELECT
        'MAINTENANCE_GAP' AS recommendation_type,
        rs.risk_level AS severity,
        'DC_SW_' || MD5(rs.SWITCH_ID) AS source_node_id,
        CASE
            WHEN rs.assigned_technician_id IS NOT NULL
                THEN 'DC_TECH_' || MD5(rs.assigned_technician_id)
            ELSE NULL
        END AS target_node_id,
        'Switch ' || rs.switch_name || ' in ' || COALESCE(rs.data_center, 'Unknown DC')
            || ' has error rate ' || rs.error_rate_pct || '% with '
            || CASE
                WHEN rs.cert_status = 'EXPIRED' THEN 'expired certification on assigned technician'
                WHEN rs.cert_status = 'UNKNOWN' THEN 'no certification data for assigned technician'
                ELSE 'valid certification but elevated error rate'
               END
            || '. Risk score: ' || rs.risk_score || '/100.'
        AS description,
        CASE rs.risk_level
            WHEN 'HIGH' THEN 'Immediately dispatch qualified technician; escalate cert renewal'
            WHEN 'MEDIUM' THEN 'Schedule proactive maintenance within 24 hours'
            WHEN 'LOW' THEN 'Flag certification for renewal at next review cycle'
            ELSE 'Monitor — no immediate action required'
        END AS suggested_action,
        'OPEN' AS status
    FROM DCA_DEMO.GOVERNANCE.DCIM_RISK_SCORES rs
    WHERE rs.risk_level IN ('HIGH', 'MEDIUM', 'LOW')
    -- Avoid duplicates: only insert if no existing recommendation for this switch
    AND NOT EXISTS (
        SELECT 1
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS existing
        WHERE existing.source_node_id = 'DC_SW_' || MD5(rs.SWITCH_ID)
          AND existing.recommendation_type = 'MAINTENANCE_GAP'
          AND existing.status = 'OPEN'
    );

    SELECT COUNT(*) INTO :v_inserted
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS
    WHERE recommendation_type = 'MAINTENANCE_GAP';

    RETURN 'Risk nodes updated. Total MAINTENANCE_GAP recommendations: ' || :v_inserted;
END;
