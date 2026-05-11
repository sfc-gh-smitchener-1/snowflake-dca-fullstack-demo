-- ============================================================================
-- HCLS KNOWLEDGE GRAPH — MASTER ORCHESTRATOR
-- ============================================================================
-- Runs all HCLS procedures in correct dependency order: clinical graph,
-- Workday graph, staffing-outcomes, comorbidity-payer, and RAI inference.
--
-- Prerequisites: All prior scripts (01-06) deployed, all data loaded
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE DCA_DEMO;
USE SCHEMA GOVERNANCE;
USE WAREHOUSE COMPUTE_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE: SP_HCLS_MASTER_ORCHESTRATOR
-- ═══════════════════════════════════════════════════════════════════════════
-- Executes all 15 HCLS procedures in dependency order with per-step
-- timing, error handling, and a comprehensive snapshot at completion.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_MASTER_ORCHESTRATOR()
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

    -- ── Step 1: Clinical Graph (Script 01) ─────────────────────────────────
    LET v_step := 'SP_HCLS_POPULATE_CLINICAL_GRAPH';
    LET v_step_start := CURRENT_TIMESTAMP();
    BEGIN
        CALL DCA_DEMO.GOVERNANCE.SP_HCLS_POPULATE_CLINICAL_GRAPH();
        SELECT * INTO :v_step_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
        LET v_step_status := 'SUCCESS';
    EXCEPTION
        WHEN OTHER THEN
            LET v_step_result := SQLERRM;
            LET v_step_status := 'FAILED';
    END;
    LET v_step_duration := DATEDIFF('second', :v_step_start, CURRENT_TIMESTAMP());
    v_results := ARRAY_APPEND(:v_results, OBJECT_CONSTRUCT('step', :v_step, 'status', :v_step_status, 'duration_seconds', :v_step_duration, 'result', :v_step_result));

    -- ── Step 2: Workday Graph (Script 04) ──────────────────────────────────
    LET v_step := 'SP_HCLS_POPULATE_WORKDAY_GRAPH';
    LET v_step_start := CURRENT_TIMESTAMP();
    BEGIN
        CALL DCA_DEMO.GOVERNANCE.SP_HCLS_POPULATE_WORKDAY_GRAPH();
        SELECT * INTO :v_step_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
        LET v_step_status := 'SUCCESS';
    EXCEPTION
        WHEN OTHER THEN
            LET v_step_result := SQLERRM;
            LET v_step_status := 'FAILED';
    END;
    LET v_step_duration := DATEDIFF('second', :v_step_start, CURRENT_TIMESTAMP());
    v_results := ARRAY_APPEND(:v_results, OBJECT_CONSTRUCT('step', :v_step, 'status', :v_step_status, 'duration_seconds', :v_step_duration, 'result', :v_step_result));

    -- ── Step 3: Staffing Context (Script 05) ───────────────────────────────
    LET v_step := 'SP_HCLS_STAFFING_CONTEXT';
    LET v_step_start := CURRENT_TIMESTAMP();
    BEGIN
        CALL DCA_DEMO.GOVERNANCE.SP_HCLS_STAFFING_CONTEXT();
        SELECT * INTO :v_step_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
        LET v_step_status := 'SUCCESS';
    EXCEPTION
        WHEN OTHER THEN
            LET v_step_result := SQLERRM;
            LET v_step_status := 'FAILED';
    END;
    LET v_step_duration := DATEDIFF('second', :v_step_start, CURRENT_TIMESTAMP());
    v_results := ARRAY_APPEND(:v_results, OBJECT_CONSTRUCT('step', :v_step, 'status', :v_step_status, 'duration_seconds', :v_step_duration, 'result', :v_step_result));

    -- ── Step 4: Staffing Outcome Metrics (Script 05) ───────────────────────
    LET v_step := 'SP_HCLS_STAFFING_OUTCOME_METRICS';
    LET v_step_start := CURRENT_TIMESTAMP();
    BEGIN
        CALL DCA_DEMO.GOVERNANCE.SP_HCLS_STAFFING_OUTCOME_METRICS();
        SELECT * INTO :v_step_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
        LET v_step_status := 'SUCCESS';
    EXCEPTION
        WHEN OTHER THEN
            LET v_step_result := SQLERRM;
            LET v_step_status := 'FAILED';
    END;
    LET v_step_duration := DATEDIFF('second', :v_step_start, CURRENT_TIMESTAMP());
    v_results := ARRAY_APPEND(:v_results, OBJECT_CONSTRUCT('step', :v_step, 'status', :v_step_status, 'duration_seconds', :v_step_duration, 'result', :v_step_result));

    -- ── Step 5: Staffing Correlation (Script 05) ───────────────────────────
    LET v_step := 'SP_HCLS_STAFFING_CORRELATION';
    LET v_step_start := CURRENT_TIMESTAMP();
    BEGIN
        CALL DCA_DEMO.GOVERNANCE.SP_HCLS_STAFFING_CORRELATION();
        SELECT * INTO :v_step_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
        LET v_step_status := 'SUCCESS';
    EXCEPTION
        WHEN OTHER THEN
            LET v_step_result := SQLERRM;
            LET v_step_status := 'FAILED';
    END;
    LET v_step_duration := DATEDIFF('second', :v_step_start, CURRENT_TIMESTAMP());
    v_results := ARRAY_APPEND(:v_results, OBJECT_CONSTRUCT('step', :v_step, 'status', :v_step_status, 'duration_seconds', :v_step_duration, 'result', :v_step_result));

    -- ── Step 6: Staffing Graph (Script 05) ─────────────────────────────────
    LET v_step := 'SP_HCLS_POPULATE_STAFFING_GRAPH';
    LET v_step_start := CURRENT_TIMESTAMP();
    BEGIN
        CALL DCA_DEMO.GOVERNANCE.SP_HCLS_POPULATE_STAFFING_GRAPH();
        SELECT * INTO :v_step_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
        LET v_step_status := 'SUCCESS';
    EXCEPTION
        WHEN OTHER THEN
            LET v_step_result := SQLERRM;
            LET v_step_status := 'FAILED';
    END;
    LET v_step_duration := DATEDIFF('second', :v_step_start, CURRENT_TIMESTAMP());
    v_results := ARRAY_APPEND(:v_results, OBJECT_CONSTRUCT('step', :v_step, 'status', :v_step_status, 'duration_seconds', :v_step_duration, 'result', :v_step_result));

    -- ── Step 7: Comorbidity Index (Script 06) ──────────────────────────────
    LET v_step := 'SP_HCLS_COMORBIDITY_INDEX';
    LET v_step_start := CURRENT_TIMESTAMP();
    BEGIN
        CALL DCA_DEMO.GOVERNANCE.SP_HCLS_COMORBIDITY_INDEX();
        SELECT * INTO :v_step_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
        LET v_step_status := 'SUCCESS';
    EXCEPTION
        WHEN OTHER THEN
            LET v_step_result := SQLERRM;
            LET v_step_status := 'FAILED';
    END;
    LET v_step_duration := DATEDIFF('second', :v_step_start, CURRENT_TIMESTAMP());
    v_results := ARRAY_APPEND(:v_results, OBJECT_CONSTRUCT('step', :v_step, 'status', :v_step_status, 'duration_seconds', :v_step_duration, 'result', :v_step_result));

    -- ── Step 8: Comorbidity Clusters (Script 06) ───────────────────────────
    LET v_step := 'SP_HCLS_COMORBIDITY_CLUSTERS';
    LET v_step_start := CURRENT_TIMESTAMP();
    BEGIN
        CALL DCA_DEMO.GOVERNANCE.SP_HCLS_COMORBIDITY_CLUSTERS();
        SELECT * INTO :v_step_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
        LET v_step_status := 'SUCCESS';
    EXCEPTION
        WHEN OTHER THEN
            LET v_step_result := SQLERRM;
            LET v_step_status := 'FAILED';
    END;
    LET v_step_duration := DATEDIFF('second', :v_step_start, CURRENT_TIMESTAMP());
    v_results := ARRAY_APPEND(:v_results, OBJECT_CONSTRUCT('step', :v_step, 'status', :v_step_status, 'duration_seconds', :v_step_duration, 'result', :v_step_result));

    -- ── Step 9: Payer Response (Script 06) ─────────────────────────────────
    LET v_step := 'SP_HCLS_PAYER_RESPONSE';
    LET v_step_start := CURRENT_TIMESTAMP();
    BEGIN
        CALL DCA_DEMO.GOVERNANCE.SP_HCLS_PAYER_RESPONSE();
        SELECT * INTO :v_step_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
        LET v_step_status := 'SUCCESS';
    EXCEPTION
        WHEN OTHER THEN
            LET v_step_result := SQLERRM;
            LET v_step_status := 'FAILED';
    END;
    LET v_step_duration := DATEDIFF('second', :v_step_start, CURRENT_TIMESTAMP());
    v_results := ARRAY_APPEND(:v_results, OBJECT_CONSTRUCT('step', :v_step, 'status', :v_step_status, 'duration_seconds', :v_step_duration, 'result', :v_step_result));

    -- ── Step 10: Plan of Care Gaps (Script 06) ─────────────────────────────
    LET v_step := 'SP_HCLS_PLAN_OF_CARE_GAPS';
    LET v_step_start := CURRENT_TIMESTAMP();
    BEGIN
        CALL DCA_DEMO.GOVERNANCE.SP_HCLS_PLAN_OF_CARE_GAPS();
        SELECT * INTO :v_step_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
        LET v_step_status := 'SUCCESS';
    EXCEPTION
        WHEN OTHER THEN
            LET v_step_result := SQLERRM;
            LET v_step_status := 'FAILED';
    END;
    LET v_step_duration := DATEDIFF('second', :v_step_start, CURRENT_TIMESTAMP());
    v_results := ARRAY_APPEND(:v_results, OBJECT_CONSTRUCT('step', :v_step, 'status', :v_step_status, 'duration_seconds', :v_step_duration, 'result', :v_step_result));

    -- ── Step 11: Payer Graph (Script 06) ───────────────────────────────────
    LET v_step := 'SP_HCLS_POPULATE_PAYER_GRAPH';
    LET v_step_start := CURRENT_TIMESTAMP();
    BEGIN
        CALL DCA_DEMO.GOVERNANCE.SP_HCLS_POPULATE_PAYER_GRAPH();
        SELECT * INTO :v_step_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
        LET v_step_status := 'SUCCESS';
    EXCEPTION
        WHEN OTHER THEN
            LET v_step_result := SQLERRM;
            LET v_step_status := 'FAILED';
    END;
    LET v_step_duration := DATEDIFF('second', :v_step_start, CURRENT_TIMESTAMP());
    v_results := ARRAY_APPEND(:v_results, OBJECT_CONSTRUCT('step', :v_step, 'status', :v_step_status, 'duration_seconds', :v_step_duration, 'result', :v_step_result));

    -- ── Step 12: PHI Detection (Script 03) ─────────────────────────────────
    LET v_step := 'SP_HCLS_PHI_DETECTION';
    LET v_step_start := CURRENT_TIMESTAMP();
    BEGIN
        CALL DCA_DEMO.GOVERNANCE.SP_HCLS_PHI_DETECTION();
        SELECT * INTO :v_step_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
        LET v_step_status := 'SUCCESS';
    EXCEPTION
        WHEN OTHER THEN
            LET v_step_result := SQLERRM;
            LET v_step_status := 'FAILED';
    END;
    LET v_step_duration := DATEDIFF('second', :v_step_start, CURRENT_TIMESTAMP());
    v_results := ARRAY_APPEND(:v_results, OBJECT_CONSTRUCT('step', :v_step, 'status', :v_step_status, 'duration_seconds', :v_step_duration, 'result', :v_step_result));

    -- ── Step 13: Patient Entity Resolution (Script 03) ─────────────────────
    LET v_step := 'SP_HCLS_PATIENT_RESOLUTION';
    LET v_step_start := CURRENT_TIMESTAMP();
    BEGIN
        CALL DCA_DEMO.GOVERNANCE.SP_HCLS_PATIENT_RESOLUTION();
        SELECT * INTO :v_step_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
        LET v_step_status := 'SUCCESS';
    EXCEPTION
        WHEN OTHER THEN
            LET v_step_result := SQLERRM;
            LET v_step_status := 'FAILED';
    END;
    LET v_step_duration := DATEDIFF('second', :v_step_start, CURRENT_TIMESTAMP());
    v_results := ARRAY_APPEND(:v_results, OBJECT_CONSTRUCT('step', :v_step, 'status', :v_step_status, 'duration_seconds', :v_step_duration, 'result', :v_step_result));

    -- ── Step 14: Care Pathway (Script 03) ──────────────────────────────────
    LET v_step := 'SP_HCLS_CARE_PATHWAY';
    LET v_step_start := CURRENT_TIMESTAMP();
    BEGIN
        CALL DCA_DEMO.GOVERNANCE.SP_HCLS_CARE_PATHWAY();
        SELECT * INTO :v_step_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
        LET v_step_status := 'SUCCESS';
    EXCEPTION
        WHEN OTHER THEN
            LET v_step_result := SQLERRM;
            LET v_step_status := 'FAILED';
    END;
    LET v_step_duration := DATEDIFF('second', :v_step_start, CURRENT_TIMESTAMP());
    v_results := ARRAY_APPEND(:v_results, OBJECT_CONSTRUCT('step', :v_step, 'status', :v_step_status, 'duration_seconds', :v_step_duration, 'result', :v_step_result));

    -- ── Step 15: HIPAA Compliance Scoring (Script 03) ──────────────────────
    LET v_step := 'SP_HCLS_HIPAA_SCORING';
    LET v_step_start := CURRENT_TIMESTAMP();
    BEGIN
        CALL DCA_DEMO.GOVERNANCE.SP_HCLS_HIPAA_SCORING();
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
    LET v_snapshot_id := 'HCLS_MASTER_' || TO_VARCHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS');

    INSERT INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_SNAPSHOTS (snapshot_id, snapshot_type, created_at, metadata)
    SELECT
        :v_snapshot_id,
        'HCLS_MASTER_RUN',
        CURRENT_TIMESTAMP(),
        OBJECT_CONSTRUCT(
            'step_results', :v_results,
            'total_duration_seconds', :v_total_duration,
            'timestamp', CURRENT_TIMESTAMP(),
            'node_count', (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
                           WHERE source_system IN ('FHIR', 'WORKDAY_HCM', 'PAYER')),
            'edge_count', (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
                           WHERE edge_id LIKE 'HCLS_%' OR edge_id LIKE 'WD_%'
                              OR edge_id LIKE 'STAFF_%' OR edge_id LIKE 'PYR_%'),
            'steps_succeeded', (SELECT COUNT(*) FROM TABLE(FLATTEN(INPUT => :v_results))
                                WHERE value:status::VARCHAR = 'SUCCESS'),
            'steps_failed', (SELECT COUNT(*) FROM TABLE(FLATTEN(INPUT => :v_results))
                             WHERE value:status::VARCHAR = 'FAILED')
        );

    RETURN 'HCLS Master Orchestrator complete. Snapshot: ' || :v_snapshot_id || CHR(10) ||
           'Total duration: ' || :v_total_duration || ' seconds' || CHR(10) ||
           'Steps: ' || ARRAY_SIZE(:v_results) || ' executed' || CHR(10) ||
           'Succeeded: ' || (SELECT COUNT(*) FROM TABLE(FLATTEN(INPUT => :v_results)) WHERE value:status::VARCHAR = 'SUCCESS') || CHR(10) ||
           'Failed: ' || (SELECT COUNT(*) FROM TABLE(FLATTEN(INPUT => :v_results)) WHERE value:status::VARCHAR = 'FAILED');
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE: SP_HCLS_QUICK_REFRESH
-- ═══════════════════════════════════════════════════════════════════════════
-- Lightweight refresh for demo purposes — runs minimum viable subset:
-- clinical graph, Workday graph, CCI, PHI, resolution, pathway, scoring.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_QUICK_REFRESH()
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

    -- ── Step 1: Clinical Graph ─────────────────────────────────────────────
    LET v_step := 'SP_HCLS_POPULATE_CLINICAL_GRAPH';
    LET v_step_start := CURRENT_TIMESTAMP();
    BEGIN
        CALL DCA_DEMO.GOVERNANCE.SP_HCLS_POPULATE_CLINICAL_GRAPH();
        SELECT * INTO :v_step_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
        LET v_step_status := 'SUCCESS';
    EXCEPTION
        WHEN OTHER THEN
            LET v_step_result := SQLERRM;
            LET v_step_status := 'FAILED';
    END;
    LET v_step_duration := DATEDIFF('second', :v_step_start, CURRENT_TIMESTAMP());
    v_results := ARRAY_APPEND(:v_results, OBJECT_CONSTRUCT('step', :v_step, 'status', :v_step_status, 'duration_seconds', :v_step_duration));

    -- ── Step 2: Workday Graph ──────────────────────────────────────────────
    LET v_step := 'SP_HCLS_POPULATE_WORKDAY_GRAPH';
    LET v_step_start := CURRENT_TIMESTAMP();
    BEGIN
        CALL DCA_DEMO.GOVERNANCE.SP_HCLS_POPULATE_WORKDAY_GRAPH();
        SELECT * INTO :v_step_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
        LET v_step_status := 'SUCCESS';
    EXCEPTION
        WHEN OTHER THEN
            LET v_step_result := SQLERRM;
            LET v_step_status := 'FAILED';
    END;
    LET v_step_duration := DATEDIFF('second', :v_step_start, CURRENT_TIMESTAMP());
    v_results := ARRAY_APPEND(:v_results, OBJECT_CONSTRUCT('step', :v_step, 'status', :v_step_status, 'duration_seconds', :v_step_duration));

    -- ── Step 3: Comorbidity Index ──────────────────────────────────────────
    LET v_step := 'SP_HCLS_COMORBIDITY_INDEX';
    LET v_step_start := CURRENT_TIMESTAMP();
    BEGIN
        CALL DCA_DEMO.GOVERNANCE.SP_HCLS_COMORBIDITY_INDEX();
        SELECT * INTO :v_step_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
        LET v_step_status := 'SUCCESS';
    EXCEPTION
        WHEN OTHER THEN
            LET v_step_result := SQLERRM;
            LET v_step_status := 'FAILED';
    END;
    LET v_step_duration := DATEDIFF('second', :v_step_start, CURRENT_TIMESTAMP());
    v_results := ARRAY_APPEND(:v_results, OBJECT_CONSTRUCT('step', :v_step, 'status', :v_step_status, 'duration_seconds', :v_step_duration));

    -- ── Step 4: PHI Detection ──────────────────────────────────────────────
    LET v_step := 'SP_HCLS_PHI_DETECTION';
    LET v_step_start := CURRENT_TIMESTAMP();
    BEGIN
        CALL DCA_DEMO.GOVERNANCE.SP_HCLS_PHI_DETECTION();
        SELECT * INTO :v_step_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
        LET v_step_status := 'SUCCESS';
    EXCEPTION
        WHEN OTHER THEN
            LET v_step_result := SQLERRM;
            LET v_step_status := 'FAILED';
    END;
    LET v_step_duration := DATEDIFF('second', :v_step_start, CURRENT_TIMESTAMP());
    v_results := ARRAY_APPEND(:v_results, OBJECT_CONSTRUCT('step', :v_step, 'status', :v_step_status, 'duration_seconds', :v_step_duration));

    -- ── Step 5: Patient Resolution ─────────────────────────────────────────
    LET v_step := 'SP_HCLS_PATIENT_RESOLUTION';
    LET v_step_start := CURRENT_TIMESTAMP();
    BEGIN
        CALL DCA_DEMO.GOVERNANCE.SP_HCLS_PATIENT_RESOLUTION();
        SELECT * INTO :v_step_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
        LET v_step_status := 'SUCCESS';
    EXCEPTION
        WHEN OTHER THEN
            LET v_step_result := SQLERRM;
            LET v_step_status := 'FAILED';
    END;
    LET v_step_duration := DATEDIFF('second', :v_step_start, CURRENT_TIMESTAMP());
    v_results := ARRAY_APPEND(:v_results, OBJECT_CONSTRUCT('step', :v_step, 'status', :v_step_status, 'duration_seconds', :v_step_duration));

    -- ── Step 6: Care Pathway ───────────────────────────────────────────────
    LET v_step := 'SP_HCLS_CARE_PATHWAY';
    LET v_step_start := CURRENT_TIMESTAMP();
    BEGIN
        CALL DCA_DEMO.GOVERNANCE.SP_HCLS_CARE_PATHWAY();
        SELECT * INTO :v_step_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
        LET v_step_status := 'SUCCESS';
    EXCEPTION
        WHEN OTHER THEN
            LET v_step_result := SQLERRM;
            LET v_step_status := 'FAILED';
    END;
    LET v_step_duration := DATEDIFF('second', :v_step_start, CURRENT_TIMESTAMP());
    v_results := ARRAY_APPEND(:v_results, OBJECT_CONSTRUCT('step', :v_step, 'status', :v_step_status, 'duration_seconds', :v_step_duration));

    -- ── Step 7: HIPAA Scoring ──────────────────────────────────────────────
    LET v_step := 'SP_HCLS_HIPAA_SCORING';
    LET v_step_start := CURRENT_TIMESTAMP();
    BEGIN
        CALL DCA_DEMO.GOVERNANCE.SP_HCLS_HIPAA_SCORING();
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
    LET v_snapshot_id := 'HCLS_QUICK_' || TO_VARCHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS');

    INSERT INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_SNAPSHOTS (snapshot_id, snapshot_type, created_at, metadata)
    SELECT
        :v_snapshot_id,
        'HCLS_QUICK_REFRESH',
        CURRENT_TIMESTAMP(),
        OBJECT_CONSTRUCT(
            'step_results', :v_results,
            'total_duration_seconds', :v_total_duration,
            'timestamp', CURRENT_TIMESTAMP(),
            'node_count', (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
                           WHERE source_system IN ('FHIR', 'WORKDAY_HCM', 'PAYER')),
            'edge_count', (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
                           WHERE edge_id LIKE 'HCLS_%' OR edge_id LIKE 'WD_%'
                              OR edge_id LIKE 'STAFF_%' OR edge_id LIKE 'PYR_%')
        );

    RETURN 'HCLS Quick Refresh complete. Snapshot: ' || :v_snapshot_id || CHR(10) ||
           'Total duration: ' || :v_total_duration || ' seconds' || CHR(10) ||
           'Steps: ' || ARRAY_SIZE(:v_results) || ' executed';
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

SELECT 'HCLS master orchestrator procedures created successfully' AS status;

-- ═══════════════════════════════════════════════════════════════════════════
-- GRANTS
-- ═══════════════════════════════════════════════════════════════════════════

GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_MASTER_ORCHESTRATOR() TO ROLE ONTOLOGY_ADMIN;
GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_QUICK_REFRESH() TO ROLE ONTOLOGY_ADMIN;
