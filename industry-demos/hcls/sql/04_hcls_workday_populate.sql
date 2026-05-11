-- ============================================================================
-- HCLS KNOWLEDGE GRAPH — WORKDAY HCM GRAPH POPULATION
-- ============================================================================
-- Extends the Ontology Knowledge Graph with Workday HCM worker, department,
-- and credential nodes plus staffing assignment and cross-system linkage edges.
--
-- Prerequisites: scripts 01 deployed (FHIR clinical graph), Workday data loaded
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE DCA_DEMO;
USE SCHEMA GOVERNANCE;
USE WAREHOUSE COMPUTE_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE: SP_HCLS_POPULATE_WORKDAY_GRAPH
-- ═══════════════════════════════════════════════════════════════════════════
-- Populates WORKER and DEPARTMENT nodes along with ASSIGNED_TO, EMPLOYED_AT,
-- SAME_AS, and cross-layer STORED_IN edges for workforce analytics.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_POPULATE_WORKDAY_GRAPH()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_worker_nodes INTEGER DEFAULT 0;
    v_department_nodes INTEGER DEFAULT 0;
    v_assigned_edges INTEGER DEFAULT 0;
    v_employed_edges INTEGER DEFAULT 0;
    v_sameas_edges INTEGER DEFAULT 0;
    v_cross_edges INTEGER DEFAULT 0;
    v_table_exists INTEGER DEFAULT 0;
BEGIN

    -- ── 1. WORKER nodes from WORKDAY DIM_WORKERS ──────────────────────────
    SELECT COUNT(*) INTO :v_table_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'WORKDAY' AND table_name = 'DIM_WORKERS';

    IF (:v_table_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
        USING (
            SELECT
                'WD_WKR_' || MD5(WORKER_ID) AS node_id,
                'WORKER' AS node_type,
                'BUSINESS' AS layer,
                'WORKDAY_HCM' AS source_system,
                WORKER_ID AS fqn,
                FIRST_NAME || ' ' || LAST_NAME || ' (' || JOB_FAMILY || ')' AS display_name,
                OBJECT_CONSTRUCT(
                    'worker_id', WORKER_ID,
                    'employee_id', EMPLOYEE_ID,
                    'job_title', JOB_TITLE,
                    'job_family', JOB_FAMILY,
                    'specialty', SPECIALTY,
                    'npi', NPI,
                    'credentials', CREDENTIALS,
                    'department_id', DEPARTMENT_ID,
                    'hire_date', HIRE_DATE,
                    'active_status', ACTIVE_STATUS,
                    'fte', FTE
                ) AS properties
            FROM CURATED_DEV.WORKDAY.DIM_WORKERS
            WHERE WORKER_ID IS NOT NULL
        ) AS src
        ON tgt.node_id = src.node_id
        WHEN MATCHED THEN UPDATE SET
            tgt.display_name = src.display_name,
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
            VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

        SELECT COUNT(*) INTO :v_worker_nodes
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
        WHERE node_type = 'WORKER' AND node_id LIKE 'WD_WKR_%';
    END IF;

    -- ── 2. DEPARTMENT nodes from WORKDAY DIM_DEPARTMENTS ──────────────────
    LET v_dept_exists INTEGER := 0;
    SELECT COUNT(*) INTO :v_dept_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'WORKDAY' AND table_name = 'DIM_DEPARTMENTS';

    IF (:v_dept_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
        USING (
            SELECT
                'WD_DEPT_' || MD5(DEPARTMENT_ID) AS node_id,
                'DEPARTMENT' AS node_type,
                'BUSINESS' AS layer,
                'WORKDAY_HCM' AS source_system,
                DEPARTMENT_ID AS fqn,
                DEPARTMENT_NAME || ' (' || UNIT_TYPE || ')' AS display_name,
                OBJECT_CONSTRUCT(
                    'department_id', DEPARTMENT_ID,
                    'unit_type', UNIT_TYPE,
                    'org_id', ORG_ID,
                    'bed_count', BED_COUNT,
                    'target_nurse_ratio', TARGET_NURSE_RATIO,
                    'cost_center', COST_CENTER
                ) AS properties
            FROM CURATED_DEV.WORKDAY.DIM_DEPARTMENTS
            WHERE DEPARTMENT_ID IS NOT NULL
        ) AS src
        ON tgt.node_id = src.node_id
        WHEN MATCHED THEN UPDATE SET
            tgt.display_name = src.display_name,
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
            VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

        SELECT COUNT(*) INTO :v_department_nodes
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
        WHERE node_type = 'DEPARTMENT' AND node_id LIKE 'WD_DEPT_%';
    END IF;

    -- ── 3. ASSIGNED_TO Edges (Worker → Department) ────────────────────────
    LET v_assign_exists INTEGER := 0;
    SELECT COUNT(*) INTO :v_assign_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'WORKDAY' AND table_name = 'FACT_STAFFING_ASSIGNMENTS';

    IF (:v_assign_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
        USING (
            SELECT
                'WD_ASGN_' || MD5(WORKER_ID || DEPARTMENT_ID || START_DATE) AS edge_id,
                'WD_WKR_' || MD5(WORKER_ID) AS source_node_id,
                'WD_DEPT_' || MD5(DEPARTMENT_ID) AS target_node_id,
                'ASSIGNED_TO' AS edge_type,
                'BUSINESS' AS layer,
                1.0 AS weight,
                OBJECT_CONSTRUCT(
                    'shift_type', SHIFT_TYPE,
                    'start_date', START_DATE,
                    'end_date', END_DATE,
                    'is_float_pool', IS_FLOAT_POOL
                ) AS properties
            FROM CURATED_DEV.WORKDAY.FACT_STAFFING_ASSIGNMENTS
            WHERE WORKER_ID IS NOT NULL
              AND DEPARTMENT_ID IS NOT NULL
              AND ASSIGNMENT_STATUS = 'ACTIVE'
        ) AS src
        ON tgt.edge_id = src.edge_id
        WHEN MATCHED THEN UPDATE SET
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight, properties)
            VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight, src.properties);

        SELECT COUNT(*) INTO :v_assigned_edges
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
        WHERE edge_type = 'ASSIGNED_TO' AND edge_id LIKE 'WD_ASGN_%';
    END IF;

    -- ── 4. EMPLOYED_AT Edges (Worker → Organization via Department) ───────
    -- Links workers to FHIR Organization nodes through department.org_id
    IF (:v_table_exists > 0 AND :v_dept_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
        USING (
            SELECT DISTINCT
                'WD_EMP_' || MD5(w.WORKER_ID || d.ORG_ID) AS edge_id,
                'WD_WKR_' || MD5(w.WORKER_ID) AS source_node_id,
                'HCLS_ORG_' || MD5(d.ORG_ID) AS target_node_id,
                'EMPLOYED_AT' AS edge_type,
                'BUSINESS' AS layer,
                1.0 AS weight,
                OBJECT_CONSTRUCT(
                    'hire_date', w.HIRE_DATE,
                    'department', d.DEPARTMENT_NAME
                ) AS properties
            FROM CURATED_DEV.WORKDAY.DIM_WORKERS w
            JOIN CURATED_DEV.WORKDAY.DIM_DEPARTMENTS d
                ON w.DEPARTMENT_ID = d.DEPARTMENT_ID
            WHERE w.WORKER_ID IS NOT NULL
              AND d.ORG_ID IS NOT NULL
        ) AS src
        ON tgt.edge_id = src.edge_id
        WHEN MATCHED THEN UPDATE SET
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight, properties)
            VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight, src.properties);

        SELECT COUNT(*) INTO :v_employed_edges
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
        WHERE edge_type = 'EMPLOYED_AT' AND edge_id LIKE 'WD_EMP_%';
    END IF;

    -- ── 5. SAME_AS Edges (Worker → Practitioner via NPI match) ────────────
    -- Cross-system identity resolution: matches Workday workers to FHIR practitioners
    LET v_prac_exists INTEGER := 0;
    SELECT COUNT(*) INTO :v_prac_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'FHIR' AND table_name = 'DIM_PRACTITIONER';

    IF (:v_table_exists > 0 AND :v_prac_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
        USING (
            SELECT DISTINCT
                'WD_MATCH_' || MD5(w.WORKER_ID || p.PRACTITIONER_ID) AS edge_id,
                'WD_WKR_' || MD5(w.WORKER_ID) AS source_node_id,
                'HCLS_PRAC_' || MD5(p.PRACTITIONER_ID) AS target_node_id,
                'SAME_AS' AS edge_type,
                'CROSS' AS layer,
                1.0 AS weight,
                OBJECT_CONSTRUCT(
                    'match_method', 'NPI',
                    'confidence', 0.99,
                    'worker_npi', w.NPI,
                    'practitioner_npi', p.NPI
                ) AS properties
            FROM CURATED_DEV.WORKDAY.DIM_WORKERS w
            JOIN CURATED_DEV.FHIR.DIM_PRACTITIONER p
                ON w.NPI = p.NPI
            WHERE w.NPI IS NOT NULL
              AND w.NPI != ''
              AND p.NPI IS NOT NULL
        ) AS src
        ON tgt.edge_id = src.edge_id
        WHEN MATCHED THEN UPDATE SET
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight, properties)
            VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight, src.properties);

        SELECT COUNT(*) INTO :v_sameas_edges
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
        WHERE edge_type = 'SAME_AS' AND edge_id LIKE 'WD_MATCH_%';
    END IF;

    -- ── 6. CROSS-LAYER STORED_IN Edges ────────────────────────────────────

    -- WORKER nodes → DIM_WORKERS table metadata node
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
    USING (
        SELECT DISTINCT
            'WD_EDGE_' || MD5(
                n.node_id ||
                'META_' || MD5('CURATED_DEV.WORKDAY.DIM_WORKERS') ||
                'STORED_IN'
            ) AS edge_id,
            n.node_id AS source_node_id,
            'META_' || MD5('CURATED_DEV.WORKDAY.DIM_WORKERS') AS target_node_id,
            'STORED_IN' AS edge_type,
            'CROSS' AS layer,
            1.0 AS weight
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n
        WHERE n.node_id LIKE 'WD_WKR_%'
          AND n.node_type = 'WORKER'
    ) AS src
    ON tgt.edge_id = src.edge_id
    WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
        VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);

    -- DEPARTMENT nodes → DIM_DEPARTMENTS table metadata node
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
    USING (
        SELECT DISTINCT
            'WD_EDGE_' || MD5(
                n.node_id ||
                'META_' || MD5('CURATED_DEV.WORKDAY.DIM_DEPARTMENTS') ||
                'STORED_IN'
            ) AS edge_id,
            n.node_id AS source_node_id,
            'META_' || MD5('CURATED_DEV.WORKDAY.DIM_DEPARTMENTS') AS target_node_id,
            'STORED_IN' AS edge_type,
            'CROSS' AS layer,
            1.0 AS weight
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n
        WHERE n.node_id LIKE 'WD_DEPT_%'
          AND n.node_type = 'DEPARTMENT'
    ) AS src
    ON tgt.edge_id = src.edge_id
    WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
        VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);

    SELECT COUNT(*) INTO :v_cross_edges
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
    WHERE (edge_id LIKE 'WD_EDGE_%' OR edge_id LIKE 'WD_MATCH_%')
      AND layer = 'CROSS';

    -- ── Final summary ─────────────────────────────────────────────────────
    RETURN 'Workday HCM Graph populated. Nodes — Workers: ' || :v_worker_nodes ||
           ', Departments: ' || :v_department_nodes ||
           '. Edges — Assigned: ' || :v_assigned_edges ||
           ', Employed: ' || :v_employed_edges ||
           ', Same-As (NPI): ' || :v_sameas_edges ||
           ', Cross-layer: ' || :v_cross_edges;
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

SELECT 'Workday HCM graph population procedure created' AS status;

SELECT node_type, COUNT(*) AS node_count
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
WHERE node_id LIKE 'WD_%'
GROUP BY node_type
ORDER BY node_type;

SELECT edge_type, layer, COUNT(*) AS edge_count
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
WHERE edge_id LIKE 'WD_%'
GROUP BY edge_type, layer
ORDER BY layer, edge_type;

-- ═══════════════════════════════════════════════════════════════════════════
-- GRANTS
-- ═══════════════════════════════════════════════════════════════════════════

GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_POPULATE_WORKDAY_GRAPH() TO ROLE ONTOLOGY_ADMIN;
