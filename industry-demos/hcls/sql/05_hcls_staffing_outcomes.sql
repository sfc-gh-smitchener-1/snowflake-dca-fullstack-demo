-- ============================================================================
-- HCLS KNOWLEDGE GRAPH — STAFFING-OUTCOMES CORRELATION ANALYSIS
-- ============================================================================
-- Builds staffing context, joins to clinical outcomes, computes correlations,
-- and populates the Knowledge Graph with staffing-outcome edges.
--
-- Prerequisites: scripts 01 + 04 deployed, FHIR + Workday data loaded
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE DCA_DEMO;
USE SCHEMA GOVERNANCE;
USE WAREHOUSE COMPUTE_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 1: SP_HCLS_STAFFING_CONTEXT
-- ═══════════════════════════════════════════════════════════════════════════
-- Builds a materialized staffing context table that captures unit-level
-- staffing metrics at shift granularity from Workday HCM data.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_STAFFING_CONTEXT()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_row_count INTEGER DEFAULT 0;
    v_shift_exists INTEGER DEFAULT 0;
    v_dept_exists INTEGER DEFAULT 0;
BEGIN

    -- Check FACT_SHIFTS table exists
    SELECT COUNT(*) INTO :v_shift_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'WORKDAY' AND table_name = 'FACT_SHIFTS';

    -- Check DIM_DEPARTMENTS table exists
    SELECT COUNT(*) INTO :v_dept_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'WORKDAY' AND table_name = 'DIM_DEPARTMENTS';

    IF (:v_shift_exists = 0 OR :v_dept_exists = 0) THEN
        RETURN 'Staffing context skipped — required Workday tables not found.';
    END IF;

    CREATE OR REPLACE TABLE DCA_DEMO.GOVERNANCE.HCLS_STAFFING_CONTEXT AS
    SELECT
        s.DEPARTMENT_ID,
        d.DEPARTMENT_NAME,
        s.SHIFT_DATE,
        s.SHIFT_TYPE,
        d.UNIT_TYPE,
        d.ORG_ID,
        d.TARGET_NURSE_RATIO,
        COUNT(DISTINCT s.WORKER_ID) AS rn_on_shift,
        ROUND(AVG(s.PATIENT_COUNT), 1) AS avg_census,
        ROUND(AVG(s.NURSE_PATIENT_RATIO), 2) AS actual_ratio,
        ROUND(
            SUM(CASE WHEN s.IS_OVERTIME THEN s.HOURS_WORKED ELSE 0 END)
            / NULLIF(SUM(s.HOURS_WORKED), 0), 4
        ) AS overtime_pct,
        ROUND(AVG(s.ACUITY_SCORE), 2) AS avg_acuity,
        SUM(CASE WHEN t.SHIFT_IMPACT = 'UNDERSTAFFED' THEN 1 ELSE 0 END) AS understaffed_events
    FROM CURATED_DEV.WORKDAY.FACT_SHIFTS s
    JOIN CURATED_DEV.WORKDAY.DIM_DEPARTMENTS d
        ON s.DEPARTMENT_ID = d.DEPARTMENT_ID
    LEFT JOIN CURATED_DEV.WORKDAY.FACT_TIME_OFF t
        ON s.DEPARTMENT_ID = t.DEPARTMENT_ID
        AND s.SHIFT_DATE BETWEEN t.START_DATE AND t.END_DATE
    GROUP BY 1, 2, 3, 4, 5, 6, 7;

    SELECT COUNT(*) INTO :v_row_count
    FROM DCA_DEMO.GOVERNANCE.HCLS_STAFFING_CONTEXT;

    RETURN 'Staffing context built. Rows: ' || :v_row_count;
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 2: SP_HCLS_STAFFING_OUTCOME_METRICS
-- ═══════════════════════════════════════════════════════════════════════════
-- Joins staffing context to encounter outcomes and computes monthly
-- unit-level outcome metrics for correlation analysis.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_STAFFING_OUTCOME_METRICS()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_row_count INTEGER DEFAULT 0;
    v_ctx_exists INTEGER DEFAULT 0;
    v_enc_exists INTEGER DEFAULT 0;
BEGIN

    -- Check staffing context exists
    SELECT COUNT(*) INTO :v_ctx_exists
    FROM DCA_DEMO.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'GOVERNANCE' AND table_name = 'HCLS_STAFFING_CONTEXT';

    -- Check encounters exist
    SELECT COUNT(*) INTO :v_enc_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'FHIR' AND table_name = 'FACT_ENCOUNTERS';

    IF (:v_ctx_exists = 0 OR :v_enc_exists = 0) THEN
        RETURN 'Staffing outcome metrics skipped — required tables not found.';
    END IF;

    CREATE OR REPLACE TABLE DCA_DEMO.GOVERNANCE.HCLS_STAFFING_OUTCOME_METRICS AS
    WITH encounter_outcomes AS (
        SELECT
            e.ENCOUNTER_ID,
            e.PATIENT_ID,
            e.ORG_ID,
            e.ADMIT_DATE,
            e.DISCHARGE_DATE,
            e.CLASS AS encounter_class,
            e.STATUS,
            e.DISCHARGE_DISPOSITION,
            DATEDIFF('day', e.ADMIT_DATE, COALESCE(e.DISCHARGE_DATE, CURRENT_DATE())) AS los_days,
            -- Readmission: same patient readmitted within 30 days
            CASE WHEN EXISTS (
                SELECT 1 FROM CURATED_DEV.FHIR.FACT_ENCOUNTERS e2
                WHERE e2.PATIENT_ID = e.PATIENT_ID
                  AND e2.ENCOUNTER_ID != e.ENCOUNTER_ID
                  AND e2.ADMIT_DATE BETWEEN e.DISCHARGE_DATE AND DATEADD('day', 30, e.DISCHARGE_DATE)
            ) THEN TRUE ELSE FALSE END AS readmission_30day,
            -- Adverse event: expired or transferred
            CASE WHEN e.DISCHARGE_DISPOSITION IN ('EXPIRED', 'TRANSFER', 'HOSPICE')
                 THEN TRUE ELSE FALSE END AS adverse_event
        FROM CURATED_DEV.FHIR.FACT_ENCOUNTERS e
        WHERE e.ADMIT_DATE IS NOT NULL
    ),
    staffing_encounter_join AS (
        SELECT
            sc.DEPARTMENT_ID,
            sc.DEPARTMENT_NAME,
            sc.UNIT_TYPE,
            sc.ORG_ID,
            DATE_TRUNC('month', sc.SHIFT_DATE) AS metric_month,
            sc.actual_ratio,
            sc.overtime_pct,
            sc.avg_acuity,
            sc.understaffed_events,
            sc.TARGET_NURSE_RATIO,
            eo.ENCOUNTER_ID,
            eo.los_days,
            eo.readmission_30day,
            eo.adverse_event,
            eo.DISCHARGE_DISPOSITION
        FROM DCA_DEMO.GOVERNANCE.HCLS_STAFFING_CONTEXT sc
        JOIN encounter_outcomes eo
            ON sc.ORG_ID = eo.ORG_ID
            AND eo.ADMIT_DATE = sc.SHIFT_DATE
    )
    SELECT
        DEPARTMENT_ID,
        DEPARTMENT_NAME,
        UNIT_TYPE,
        ORG_ID,
        metric_month,
        ROUND(AVG(actual_ratio), 2) AS avg_nurse_ratio,
        ROUND(AVG(overtime_pct) * 100, 1) AS avg_overtime_pct,
        ROUND(AVG(avg_acuity), 2) AS avg_acuity,
        SUM(understaffed_events) AS total_understaffed_events,
        ROUND(AVG(TARGET_NURSE_RATIO), 2) AS target_ratio,
        COUNT(DISTINCT ENCOUNTER_ID) AS encounter_count,
        ROUND(AVG(los_days), 1) AS avg_los,
        ROUND(SUM(CASE WHEN readmission_30day THEN 1 ELSE 0 END)::FLOAT
              / NULLIF(COUNT(DISTINCT ENCOUNTER_ID), 0) * 100, 1) AS readmission_rate_pct,
        ROUND(SUM(CASE WHEN DISCHARGE_DISPOSITION = 'EXPIRED' THEN 1 ELSE 0 END)::FLOAT
              / NULLIF(COUNT(DISTINCT ENCOUNTER_ID), 0) * 100, 1) AS mortality_rate_pct,
        ROUND(SUM(CASE WHEN adverse_event THEN 1 ELSE 0 END)::FLOAT
              / NULLIF(COUNT(DISTINCT ENCOUNTER_ID), 0) * 100, 1) AS adverse_event_rate_pct
    FROM staffing_encounter_join
    GROUP BY 1, 2, 3, 4, 5;

    SELECT COUNT(*) INTO :v_row_count
    FROM DCA_DEMO.GOVERNANCE.HCLS_STAFFING_OUTCOME_METRICS;

    RETURN 'Staffing outcome metrics computed. Rows: ' || :v_row_count;
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 3: SP_HCLS_STAFFING_CORRELATION
-- ═══════════════════════════════════════════════════════════════════════════
-- Computes Pearson correlation coefficients between staffing metrics and
-- clinical outcome rates across monthly unit-level observations.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_STAFFING_CORRELATION()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_row_count INTEGER DEFAULT 0;
    v_metrics_exists INTEGER DEFAULT 0;
BEGIN

    SELECT COUNT(*) INTO :v_metrics_exists
    FROM DCA_DEMO.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'GOVERNANCE' AND table_name = 'HCLS_STAFFING_OUTCOME_METRICS';

    IF (:v_metrics_exists = 0) THEN
        RETURN 'Correlation skipped — HCLS_STAFFING_OUTCOME_METRICS not found.';
    END IF;

    CREATE OR REPLACE TABLE DCA_DEMO.GOVERNANCE.HCLS_CORRELATION_RESULTS AS
    WITH base AS (
        SELECT
            avg_nurse_ratio,
            avg_overtime_pct,
            CASE WHEN target_ratio > 0
                 THEN (avg_nurse_ratio - target_ratio) / target_ratio
                 ELSE 0 END AS vacancy_rate,
            readmission_rate_pct,
            adverse_event_rate_pct,
            avg_los,
            encounter_count
        FROM DCA_DEMO.GOVERNANCE.HCLS_STAFFING_OUTCOME_METRICS
        WHERE encounter_count >= 10
    )
    -- Ratio vs Readmission
    SELECT
        'nurse_ratio_vs_readmission' AS metric_pair,
        ROUND(CORR(avg_nurse_ratio, readmission_rate_pct), 4) AS correlation_coefficient,
        ROUND(
            2 * (1 - ABS(CORR(avg_nurse_ratio, readmission_rate_pct)))
            * SQRT(COUNT(*))
        , 4) AS p_value_approx,
        COUNT(*) AS sample_size,
        CURRENT_DATE() AS period
    FROM base
    WHERE avg_nurse_ratio IS NOT NULL AND readmission_rate_pct IS NOT NULL

    UNION ALL

    -- Overtime vs Adverse Events
    SELECT
        'overtime_vs_adverse_events' AS metric_pair,
        ROUND(CORR(avg_overtime_pct, adverse_event_rate_pct), 4),
        ROUND(
            2 * (1 - ABS(CORR(avg_overtime_pct, adverse_event_rate_pct)))
            * SQRT(COUNT(*))
        , 4),
        COUNT(*),
        CURRENT_DATE()
    FROM base
    WHERE avg_overtime_pct IS NOT NULL AND adverse_event_rate_pct IS NOT NULL

    UNION ALL

    -- Vacancy Rate vs Avg LOS
    SELECT
        'vacancy_rate_vs_avg_los' AS metric_pair,
        ROUND(CORR(vacancy_rate, avg_los), 4),
        ROUND(
            2 * (1 - ABS(CORR(vacancy_rate, avg_los)))
            * SQRT(COUNT(*))
        , 4),
        COUNT(*),
        CURRENT_DATE()
    FROM base
    WHERE vacancy_rate IS NOT NULL AND avg_los IS NOT NULL

    UNION ALL

    -- Overtime vs Readmission
    SELECT
        'overtime_vs_readmission' AS metric_pair,
        ROUND(CORR(avg_overtime_pct, readmission_rate_pct), 4),
        ROUND(
            2 * (1 - ABS(CORR(avg_overtime_pct, readmission_rate_pct)))
            * SQRT(COUNT(*))
        , 4),
        COUNT(*),
        CURRENT_DATE()
    FROM base
    WHERE avg_overtime_pct IS NOT NULL AND readmission_rate_pct IS NOT NULL;

    SELECT COUNT(*) INTO :v_row_count
    FROM DCA_DEMO.GOVERNANCE.HCLS_CORRELATION_RESULTS;

    RETURN 'Correlation analysis complete. Metric pairs: ' || :v_row_count;
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 4: SP_HCLS_POPULATE_STAFFING_GRAPH
-- ═══════════════════════════════════════════════════════════════════════════
-- Populates the Knowledge Graph with staffing-outcome nodes and edges:
-- STAFFING_CONTEXT nodes, INFLUENCED_BY edges, UNDERSTAFFED_DURING edges,
-- and SAME_AS cross-system identity links.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_POPULATE_STAFFING_GRAPH()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_context_nodes INTEGER DEFAULT 0;
    v_influenced_edges INTEGER DEFAULT 0;
    v_understaffed_edges INTEGER DEFAULT 0;
    v_cross_edges INTEGER DEFAULT 0;
    v_ctx_exists INTEGER DEFAULT 0;
    v_metrics_exists INTEGER DEFAULT 0;
BEGIN

    -- Check prerequisites
    SELECT COUNT(*) INTO :v_ctx_exists
    FROM DCA_DEMO.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'GOVERNANCE' AND table_name = 'HCLS_STAFFING_CONTEXT';

    SELECT COUNT(*) INTO :v_metrics_exists
    FROM DCA_DEMO.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'GOVERNANCE' AND table_name = 'HCLS_STAFFING_OUTCOME_METRICS';

    IF (:v_ctx_exists = 0) THEN
        RETURN 'Staffing graph skipped — HCLS_STAFFING_CONTEXT not found.';
    END IF;

    -- ── 1. STAFFING_CONTEXT nodes ──────────────────────────────────────────
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
    USING (
        SELECT DISTINCT
            'WD_STAFF_' || MD5(DEPARTMENT_ID || SHIFT_DATE) AS node_id,
            'STAFFING_CONTEXT' AS node_type,
            'BUSINESS' AS layer,
            'WORKDAY_HCM' AS source_system,
            DEPARTMENT_ID || '::' || SHIFT_DATE AS fqn,
            DEPARTMENT_NAME || ' (' || UNIT_TYPE || ') ' || SHIFT_DATE AS display_name,
            OBJECT_CONSTRUCT(
                'department_id', DEPARTMENT_ID,
                'shift_date', SHIFT_DATE,
                'unit_type', UNIT_TYPE,
                'org_id', ORG_ID,
                'actual_ratio', actual_ratio,
                'target_ratio', TARGET_NURSE_RATIO,
                'overtime_pct', overtime_pct,
                'avg_census', avg_census,
                'avg_acuity', avg_acuity,
                'rn_on_shift', rn_on_shift,
                'understaffed_events', understaffed_events
            ) AS properties
        FROM DCA_DEMO.GOVERNANCE.HCLS_STAFFING_CONTEXT
    ) AS src
    ON tgt.node_id = src.node_id
    WHEN MATCHED THEN UPDATE SET
        tgt.display_name = src.display_name,
        tgt.properties = src.properties
    WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
        VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

    SELECT COUNT(*) INTO :v_context_nodes
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
    WHERE node_type = 'STAFFING_CONTEXT' AND node_id LIKE 'WD_STAFF_%';

    -- ── 2. INFLUENCED_BY edges (Encounter → Staffing Context) ──────────────
    -- Links encounters with adverse outcomes to the staffing context at that
    -- unit/date where the nurse ratio exceeded the target.
    LET v_enc_exists INTEGER := 0;
    SELECT COUNT(*) INTO :v_enc_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'FHIR' AND table_name = 'FACT_ENCOUNTERS';

    IF (:v_enc_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
        USING (
            SELECT DISTINCT
                'STAFF_INF_' || MD5(
                    'HCLS_ENC_' || MD5(e.ENCOUNTER_ID) ||
                    'WD_STAFF_' || MD5(sc.DEPARTMENT_ID || sc.SHIFT_DATE) ||
                    'INFLUENCED_BY'
                ) AS edge_id,
                'HCLS_ENC_' || MD5(e.ENCOUNTER_ID) AS source_node_id,
                'WD_STAFF_' || MD5(sc.DEPARTMENT_ID || sc.SHIFT_DATE) AS target_node_id,
                'INFLUENCED_BY' AS edge_type,
                'CROSS' AS layer,
                ROUND(LEAST(sc.actual_ratio / NULLIF(sc.TARGET_NURSE_RATIO, 0), 3.0), 2) AS weight,
                OBJECT_CONSTRUCT(
                    'correlation_strength', ROUND(LEAST(sc.actual_ratio / NULLIF(sc.TARGET_NURSE_RATIO, 0), 3.0), 2),
                    'actual_ratio', sc.actual_ratio,
                    'target_ratio', sc.TARGET_NURSE_RATIO,
                    'overtime_pct', sc.overtime_pct,
                    'encounter_class', e.CLASS,
                    'discharge_disposition', e.DISCHARGE_DISPOSITION
                ) AS properties
            FROM CURATED_DEV.FHIR.FACT_ENCOUNTERS e
            JOIN DCA_DEMO.GOVERNANCE.HCLS_STAFFING_CONTEXT sc
                ON sc.ORG_ID = e.ORG_ID
                AND e.ADMIT_DATE = sc.SHIFT_DATE
            WHERE e.DISCHARGE_DISPOSITION IN ('EXPIRED', 'TRANSFER', 'HOSPICE')
              AND sc.actual_ratio > sc.TARGET_NURSE_RATIO
        ) AS src
        ON tgt.edge_id = src.edge_id
        WHEN MATCHED THEN UPDATE SET
            tgt.weight = src.weight,
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight, properties)
            VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight, src.properties);

        SELECT COUNT(*) INTO :v_influenced_edges
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
        WHERE edge_type = 'INFLUENCED_BY' AND edge_id LIKE 'STAFF_INF_%';
    END IF;

    -- ── 3. UNDERSTAFFED_DURING edges (Encounter → Department) ──────────────
    -- Links encounters to department nodes when actual ratio > target * 1.2
    IF (:v_enc_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
        USING (
            SELECT DISTINCT
                'STAFF_US_' || MD5(
                    'HCLS_ENC_' || MD5(e.ENCOUNTER_ID) ||
                    'WD_DEPT_' || MD5(sc.DEPARTMENT_ID) ||
                    'UNDERSTAFFED_DURING'
                ) AS edge_id,
                'HCLS_ENC_' || MD5(e.ENCOUNTER_ID) AS source_node_id,
                'WD_DEPT_' || MD5(sc.DEPARTMENT_ID) AS target_node_id,
                'UNDERSTAFFED_DURING' AS edge_type,
                'CROSS' AS layer,
                1.0 AS weight,
                OBJECT_CONSTRUCT(
                    'shift_date', sc.SHIFT_DATE,
                    'actual_ratio', sc.actual_ratio,
                    'target_ratio', sc.TARGET_NURSE_RATIO,
                    'ratio_exceeded_by_pct', ROUND((sc.actual_ratio - sc.TARGET_NURSE_RATIO) / NULLIF(sc.TARGET_NURSE_RATIO, 0) * 100, 1)
                ) AS properties
            FROM CURATED_DEV.FHIR.FACT_ENCOUNTERS e
            JOIN DCA_DEMO.GOVERNANCE.HCLS_STAFFING_CONTEXT sc
                ON sc.ORG_ID = e.ORG_ID
                AND e.ADMIT_DATE = sc.SHIFT_DATE
            WHERE sc.actual_ratio > sc.TARGET_NURSE_RATIO * 1.2
        ) AS src
        ON tgt.edge_id = src.edge_id
        WHEN MATCHED THEN UPDATE SET
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight, properties)
            VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight, src.properties);

        SELECT COUNT(*) INTO :v_understaffed_edges
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
        WHERE edge_type = 'UNDERSTAFFED_DURING' AND edge_id LIKE 'STAFF_US_%';
    END IF;

    -- ── 4. CROSS-LAYER STORED_IN Edges ─────────────────────────────────────
    -- STAFFING_CONTEXT nodes → HCLS_STAFFING_CONTEXT table metadata node
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
    USING (
        SELECT DISTINCT
            'STAFF_EDGE_' || MD5(
                n.node_id ||
                'META_' || MD5('DCA_DEMO.GOVERNANCE.HCLS_STAFFING_CONTEXT') ||
                'STORED_IN'
            ) AS edge_id,
            n.node_id AS source_node_id,
            'META_' || MD5('DCA_DEMO.GOVERNANCE.HCLS_STAFFING_CONTEXT') AS target_node_id,
            'STORED_IN' AS edge_type,
            'CROSS' AS layer,
            1.0 AS weight
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n
        WHERE n.node_id LIKE 'WD_STAFF_%'
          AND n.node_type = 'STAFFING_CONTEXT'
    ) AS src
    ON tgt.edge_id = src.edge_id
    WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
        VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);

    SELECT COUNT(*) INTO :v_cross_edges
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
    WHERE edge_id LIKE 'STAFF_EDGE_%' AND layer = 'CROSS';

    -- ── Final summary ───────────────────────────────────────────────────────
    RETURN 'Staffing graph populated. Nodes — Staffing Context: ' || :v_context_nodes ||
           '. Edges — Influenced By: ' || :v_influenced_edges ||
           ', Understaffed During: ' || :v_understaffed_edges ||
           ', Cross-layer: ' || :v_cross_edges;
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 5: SP_HCLS_STAFFING_RUN_ALL (Orchestrator)
-- ═══════════════════════════════════════════════════════════════════════════
-- Runs all staffing-outcomes procedures in sequence and records a snapshot.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_STAFFING_RUN_ALL()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_result_context VARCHAR;
    v_result_metrics VARCHAR;
    v_result_correlation VARCHAR;
    v_result_graph VARCHAR;
    v_snapshot_id VARCHAR;
BEGIN
    -- Step 1: Build staffing context table
    CALL DCA_DEMO.GOVERNANCE.SP_HCLS_STAFFING_CONTEXT();
    SELECT * INTO :v_result_context FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

    -- Step 2: Compute staffing-outcome metrics
    CALL DCA_DEMO.GOVERNANCE.SP_HCLS_STAFFING_OUTCOME_METRICS();
    SELECT * INTO :v_result_metrics FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

    -- Step 3: Compute correlations
    CALL DCA_DEMO.GOVERNANCE.SP_HCLS_STAFFING_CORRELATION();
    SELECT * INTO :v_result_correlation FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

    -- Step 4: Populate Knowledge Graph
    CALL DCA_DEMO.GOVERNANCE.SP_HCLS_POPULATE_STAFFING_GRAPH();
    SELECT * INTO :v_result_graph FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

    -- Record snapshot
    LET v_snapshot_id := 'HCLS_STAFFING_' || TO_VARCHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS');

    INSERT INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_SNAPSHOTS (snapshot_id, snapshot_type, created_at, metadata)
    SELECT
        :v_snapshot_id,
        'HCLS_STAFFING_RUN',
        CURRENT_TIMESTAMP(),
        OBJECT_CONSTRUCT(
            'context_result', :v_result_context,
            'metrics_result', :v_result_metrics,
            'correlation_result', :v_result_correlation,
            'graph_result', :v_result_graph,
            'staffing_node_count', (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES WHERE node_id LIKE 'WD_STAFF_%'),
            'staffing_edge_count', (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES WHERE edge_id LIKE 'STAFF_%'),
            'correlation_count', (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.HCLS_CORRELATION_RESULTS)
        );

    RETURN 'HCLS Staffing pipeline complete. Snapshot: ' || :v_snapshot_id || CHR(10) ||
           '  Context: ' || :v_result_context || CHR(10) ||
           '  Metrics: ' || :v_result_metrics || CHR(10) ||
           '  Correlation: ' || :v_result_correlation || CHR(10) ||
           '  Graph: ' || :v_result_graph;
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

SELECT 'HCLS staffing-outcomes procedures created successfully' AS status;

-- ═══════════════════════════════════════════════════════════════════════════
-- GRANTS
-- ═══════════════════════════════════════════════════════════════════════════

GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_STAFFING_CONTEXT() TO ROLE ONTOLOGY_ADMIN;
GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_STAFFING_OUTCOME_METRICS() TO ROLE ONTOLOGY_ADMIN;
GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_STAFFING_CORRELATION() TO ROLE ONTOLOGY_ADMIN;
GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_POPULATE_STAFFING_GRAPH() TO ROLE ONTOLOGY_ADMIN;
GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_STAFFING_RUN_ALL() TO ROLE ONTOLOGY_ADMIN;
