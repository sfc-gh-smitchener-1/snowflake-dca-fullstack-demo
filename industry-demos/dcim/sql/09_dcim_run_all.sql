-- ============================================================================
-- DCIM KNOWLEDGE GRAPH — MASTER ORCHESTRATOR
-- ============================================================================
-- Runs all DCIM procedures in correct dependency order: infrastructure graph,
-- Workday graph, risk scoring, MTTR analysis, dispatch, risk nodes, and
-- time travel snapshot.
--
-- Prerequisites: All prior scripts (04-08) deployed, all data loaded
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE DCA_DEMO;
USE SCHEMA GOVERNANCE;
USE WAREHOUSE COMPUTE_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE: SP_DCIM_MASTER_ORCHESTRATOR
-- ═══════════════════════════════════════════════════════════════════════════
-- Executes all 7 DCIM procedures in dependency order with per-step
-- timing, error handling, and a comprehensive snapshot at completion.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_DCIM_MASTER_ORCHESTRATOR()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_run_start TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP();
    v_step_start TIMESTAMP_NTZ;
    v_step_result VARCHAR;
    v_step_status VARCHAR;
    v_step_duration INTEGER;
    v_results ARRAY DEFAULT ARRAY_CONSTRUCT();
    v_snapshot_id VARCHAR;
    v_step VARCHAR;
    v_total_duration INTEGER;
BEGIN

    -- ── Step 1: Infrastructure Graph (Script 04) ────────────────────────────
    LET v_step := 'SP_DCIM_POPULATE_INFRASTRUCTURE_GRAPH';
    LET v_step_start := CURRENT_TIMESTAMP();
    BEGIN
        CALL DCA_DEMO.GOVERNANCE.SP_DCIM_POPULATE_INFRASTRUCTURE_GRAPH();
        SELECT * INTO :v_step_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
        LET v_step_status := 'SUCCESS';
    EXCEPTION
        WHEN OTHER THEN
            LET v_step_result := SQLERRM;
            LET v_step_status := 'FAILED';
    END;
    LET v_step_duration := DATEDIFF('second', :v_step_start, CURRENT_TIMESTAMP());
    v_results := ARRAY_APPEND(:v_results, OBJECT_CONSTRUCT('step', :v_step, 'status', :v_step_status, 'duration_seconds', :v_step_duration, 'result', :v_step_result));

    -- ── Step 2: Workday Workforce Graph (Script 05) ─────────────────────────
    LET v_step := 'SP_DCIM_POPULATE_WORKDAY_GRAPH';
    LET v_step_start := CURRENT_TIMESTAMP();
    BEGIN
        CALL DCA_DEMO.GOVERNANCE.SP_DCIM_POPULATE_WORKDAY_GRAPH();
        SELECT * INTO :v_step_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
        LET v_step_status := 'SUCCESS';
    EXCEPTION
        WHEN OTHER THEN
            LET v_step_result := SQLERRM;
            LET v_step_status := 'FAILED';
    END;
    LET v_step_duration := DATEDIFF('second', :v_step_start, CURRENT_TIMESTAMP());
    v_results := ARRAY_APPEND(:v_results, OBJECT_CONSTRUCT('step', :v_step, 'status', :v_step_status, 'duration_seconds', :v_step_duration, 'result', :v_step_result));

    -- ── Step 3: Risk Scoring (Script 06) ────────────────────────────────────
    LET v_step := 'SP_DCIM_RISK_SCORING';
    LET v_step_start := CURRENT_TIMESTAMP();
    BEGIN
        CALL DCA_DEMO.GOVERNANCE.SP_DCIM_RISK_SCORING();
        SELECT * INTO :v_step_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
        LET v_step_status := 'SUCCESS';
    EXCEPTION
        WHEN OTHER THEN
            LET v_step_result := SQLERRM;
            LET v_step_status := 'FAILED';
    END;
    LET v_step_duration := DATEDIFF('second', :v_step_start, CURRENT_TIMESTAMP());
    v_results := ARRAY_APPEND(:v_results, OBJECT_CONSTRUCT('step', :v_step, 'status', :v_step_status, 'duration_seconds', :v_step_duration, 'result', :v_step_result));

    -- ── Step 4: MTTR Analysis (Script 06) ───────────────────────────────────
    LET v_step := 'SP_DCIM_MTTR_ANALYSIS';
    LET v_step_start := CURRENT_TIMESTAMP();
    BEGIN
        CALL DCA_DEMO.GOVERNANCE.SP_DCIM_MTTR_ANALYSIS();
        SELECT * INTO :v_step_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
        LET v_step_status := 'SUCCESS';
    EXCEPTION
        WHEN OTHER THEN
            LET v_step_result := SQLERRM;
            LET v_step_status := 'FAILED';
    END;
    LET v_step_duration := DATEDIFF('second', :v_step_start, CURRENT_TIMESTAMP());
    v_results := ARRAY_APPEND(:v_results, OBJECT_CONSTRUCT('step', :v_step, 'status', :v_step_status, 'duration_seconds', :v_step_duration, 'result', :v_step_result));

    -- ── Step 5: Nearest Qualified Technician (Script 07) ────────────────────
    LET v_step := 'SP_DCIM_NEAREST_QUALIFIED_TECH';
    LET v_step_start := CURRENT_TIMESTAMP();
    BEGIN
        CALL DCA_DEMO.GOVERNANCE.SP_DCIM_NEAREST_QUALIFIED_TECH();
        SELECT * INTO :v_step_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
        LET v_step_status := 'SUCCESS';
    EXCEPTION
        WHEN OTHER THEN
            LET v_step_result := SQLERRM;
            LET v_step_status := 'FAILED';
    END;
    LET v_step_duration := DATEDIFF('second', :v_step_start, CURRENT_TIMESTAMP());
    v_results := ARRAY_APPEND(:v_results, OBJECT_CONSTRUCT('step', :v_step, 'status', :v_step_status, 'duration_seconds', :v_step_duration, 'result', :v_step_result));

    -- ── Step 6: Update Risk Nodes in Graph (Script 07) ──────────────────────
    LET v_step := 'SP_DCIM_UPDATE_RISK_NODES';
    LET v_step_start := CURRENT_TIMESTAMP();
    BEGIN
        CALL DCA_DEMO.GOVERNANCE.SP_DCIM_UPDATE_RISK_NODES();
        SELECT * INTO :v_step_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
        LET v_step_status := 'SUCCESS';
    EXCEPTION
        WHEN OTHER THEN
            LET v_step_result := SQLERRM;
            LET v_step_status := 'FAILED';
    END;
    LET v_step_duration := DATEDIFF('second', :v_step_start, CURRENT_TIMESTAMP());
    v_results := ARRAY_APPEND(:v_results, OBJECT_CONSTRUCT('step', :v_step, 'status', :v_step_status, 'duration_seconds', :v_step_duration, 'result', :v_step_result));

    -- ── Step 7: Time Travel Snapshot (Script 08) ────────────────────────────
    LET v_step := 'SP_DCIM_TIME_TRAVEL';
    LET v_step_start := CURRENT_TIMESTAMP();
    BEGIN
        CALL DCA_DEMO.GOVERNANCE.SP_DCIM_TIME_TRAVEL(CURRENT_TIMESTAMP());
        SELECT * INTO :v_step_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
        LET v_step_status := 'SUCCESS';
    EXCEPTION
        WHEN OTHER THEN
            LET v_step_result := SQLERRM;
            LET v_step_status := 'FAILED';
    END;
    LET v_step_duration := DATEDIFF('second', :v_step_start, CURRENT_TIMESTAMP());
    v_results := ARRAY_APPEND(:v_results, OBJECT_CONSTRUCT('step', :v_step, 'status', :v_step_status, 'duration_seconds', :v_step_duration, 'result', :v_step_result));

    -- ── Record comprehensive snapshot ──────────────────────────────────────
    LET v_total_duration := DATEDIFF('second', :v_run_start, CURRENT_TIMESTAMP());
    LET v_snapshot_id := 'DCIM_MASTER_' || TO_VARCHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS');

    INSERT INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_SNAPSHOTS (snapshot_id, snapshot_type, created_at, metadata)
    SELECT
        :v_snapshot_id,
        'DCIM_MASTER_RUN',
        CURRENT_TIMESTAMP(),
        OBJECT_CONSTRUCT(
            'step_results', :v_results,
            'total_duration_seconds', :v_total_duration,
            'timestamp', CURRENT_TIMESTAMP(),
            'node_count', (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
                           WHERE source_system IN ('SERVICENOW', 'WORKDAY_DCIM')),
            'edge_count', (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
                           WHERE edge_id LIKE 'DC_%'),
            'steps_succeeded', (SELECT COUNT(*) FROM TABLE(FLATTEN(INPUT => :v_results))
                                WHERE value:status::VARCHAR = 'SUCCESS'),
            'steps_failed', (SELECT COUNT(*) FROM TABLE(FLATTEN(INPUT => :v_results))
                             WHERE value:status::VARCHAR = 'FAILED')
        );

    RETURN 'DCIM Master Orchestrator complete. Snapshot: ' || :v_snapshot_id || CHR(10) ||
           'Total duration: ' || :v_total_duration || ' seconds' || CHR(10) ||
           'Steps: ' || ARRAY_SIZE(:v_results) || ' executed' || CHR(10) ||
           'Succeeded: ' || (SELECT COUNT(*) FROM TABLE(FLATTEN(INPUT => :v_results)) WHERE value:status::VARCHAR = 'SUCCESS') || CHR(10) ||
           'Failed: ' || (SELECT COUNT(*) FROM TABLE(FLATTEN(INPUT => :v_results)) WHERE value:status::VARCHAR = 'FAILED');
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE: SP_DCIM_QUICK_REFRESH
-- ═══════════════════════════════════════════════════════════════════════════
-- Lightweight refresh — only runs risk scoring, dispatch, and risk nodes.
-- Skips graph population and historical recomputation (expensive).
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_DCIM_QUICK_REFRESH()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_run_start TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP();
    v_step_result VARCHAR;
    v_snapshot_id VARCHAR;
    v_total_duration INTEGER;
    v_results ARRAY DEFAULT ARRAY_CONSTRUCT();
    v_step VARCHAR;
    v_step_start TIMESTAMP_NTZ;
    v_step_status VARCHAR;
    v_step_duration INTEGER;
BEGIN

    -- ── Step 1: Risk Scoring ────────────────────────────────────────────────
    LET v_step := 'SP_DCIM_RISK_SCORING';
    LET v_step_start := CURRENT_TIMESTAMP();
    BEGIN
        CALL DCA_DEMO.GOVERNANCE.SP_DCIM_RISK_SCORING();
        SELECT * INTO :v_step_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
        LET v_step_status := 'SUCCESS';
    EXCEPTION
        WHEN OTHER THEN
            LET v_step_result := SQLERRM;
            LET v_step_status := 'FAILED';
    END;
    LET v_step_duration := DATEDIFF('second', :v_step_start, CURRENT_TIMESTAMP());
    v_results := ARRAY_APPEND(:v_results, OBJECT_CONSTRUCT('step', :v_step, 'status', :v_step_status, 'duration_seconds', :v_step_duration));

    -- ── Step 2: Nearest Qualified Technician ────────────────────────────────
    LET v_step := 'SP_DCIM_NEAREST_QUALIFIED_TECH';
    LET v_step_start := CURRENT_TIMESTAMP();
    BEGIN
        CALL DCA_DEMO.GOVERNANCE.SP_DCIM_NEAREST_QUALIFIED_TECH();
        SELECT * INTO :v_step_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
        LET v_step_status := 'SUCCESS';
    EXCEPTION
        WHEN OTHER THEN
            LET v_step_result := SQLERRM;
            LET v_step_status := 'FAILED';
    END;
    LET v_step_duration := DATEDIFF('second', :v_step_start, CURRENT_TIMESTAMP());
    v_results := ARRAY_APPEND(:v_results, OBJECT_CONSTRUCT('step', :v_step, 'status', :v_step_status, 'duration_seconds', :v_step_duration));

    -- ── Step 3: Update Risk Nodes ───────────────────────────────────────────
    LET v_step := 'SP_DCIM_UPDATE_RISK_NODES';
    LET v_step_start := CURRENT_TIMESTAMP();
    BEGIN
        CALL DCA_DEMO.GOVERNANCE.SP_DCIM_UPDATE_RISK_NODES();
        SELECT * INTO :v_step_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
        LET v_step_status := 'SUCCESS';
    EXCEPTION
        WHEN OTHER THEN
            LET v_step_result := SQLERRM;
            LET v_step_status := 'FAILED';
    END;
    LET v_step_duration := DATEDIFF('second', :v_step_start, CURRENT_TIMESTAMP());
    v_results := ARRAY_APPEND(:v_results, OBJECT_CONSTRUCT('step', :v_step, 'status', :v_step_status, 'duration_seconds', :v_step_duration));

    -- ── Record snapshot ────────────────────────────────────────────────────
    LET v_total_duration := DATEDIFF('second', :v_run_start, CURRENT_TIMESTAMP());
    LET v_snapshot_id := 'DCIM_QUICK_' || TO_VARCHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS');

    INSERT INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_SNAPSHOTS (snapshot_id, snapshot_type, created_at, metadata)
    SELECT
        :v_snapshot_id,
        'DCIM_QUICK_REFRESH',
        CURRENT_TIMESTAMP(),
        OBJECT_CONSTRUCT(
            'step_results', :v_results,
            'total_duration_seconds', :v_total_duration,
            'timestamp', CURRENT_TIMESTAMP(),
            'node_count', (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
                           WHERE source_system IN ('SERVICENOW', 'WORKDAY_DCIM')),
            'edge_count', (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
                           WHERE edge_id LIKE 'DC_%')
        );

    RETURN 'DCIM Quick Refresh complete. Snapshot: ' || :v_snapshot_id || CHR(10) ||
           'Total duration: ' || :v_total_duration || ' seconds' || CHR(10) ||
           'Steps: ' || ARRAY_SIZE(:v_results) || ' executed';
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- GRANTS
-- ═══════════════════════════════════════════════════════════════════════════

GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_DCIM_MASTER_ORCHESTRATOR() TO ROLE ONTOLOGY_ADMIN;
GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_DCIM_QUICK_REFRESH() TO ROLE ONTOLOGY_ADMIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

SELECT 'DCIM master orchestrator procedures created successfully' AS STATUS;
