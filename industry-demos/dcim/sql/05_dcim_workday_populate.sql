-- ============================================================================
-- DCIM KNOWLEDGE GRAPH — WORKDAY WORKFORCE GRAPH POPULATION
-- ============================================================================
-- Extends the Ontology Knowledge Graph with Workday DCIM workforce nodes
-- (technicians, certifications, teams) and cross-system linkage edges.
--
-- Prerequisites: 04_dcim_graph_populate.sql deployed, Workday DCIM data loaded
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE DCA_DEMO;
USE SCHEMA GOVERNANCE;
USE WAREHOUSE COMPUTE_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE: SP_DCIM_POPULATE_WORKDAY_GRAPH
-- ═══════════════════════════════════════════════════════════════════════════
-- Populates TECHNICIAN, CERTIFICATION, and TEAM nodes along with
-- certification, incident assignment, team membership, and cross-system
-- SAME_AS edges for workforce-infrastructure analytics.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_DCIM_POPULATE_WORKDAY_GRAPH()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_tech_nodes INTEGER DEFAULT 0;
    v_cert_nodes INTEGER DEFAULT 0;
    v_team_nodes INTEGER DEFAULT 0;
    v_cert_edges INTEGER DEFAULT 0;
    v_assignment_edges INTEGER DEFAULT 0;
    v_team_edges INTEGER DEFAULT 0;
    v_sameas_edges INTEGER DEFAULT 0;
    v_cross_edges INTEGER DEFAULT 0;
    v_table_exists INTEGER DEFAULT 0;
BEGIN

    -- ── 1. TECHNICIAN nodes from WORKDAY_DCIM DIM_TECHNICIANS ──────────────
    SELECT COUNT(*) INTO :v_table_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'WORKDAY_DCIM' AND table_name = 'DIM_TECHNICIANS';

    IF (:v_table_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
        USING (
            SELECT
                'DC_TECH_' || MD5(WORKER_ID) AS node_id,
                'TECHNICIAN' AS node_type,
                'BUSINESS' AS layer,
                'WORKDAY_DCIM' AS source_system,
                WORKER_ID AS fqn,
                COALESCE(FIRST_NAME, '') || ' ' || COALESCE(LAST_NAME, '') || ' (' || COALESCE(JOB_TITLE, 'Technician') || ')' AS display_name,
                OBJECT_CONSTRUCT(
                    'worker_id', WORKER_ID,
                    'employee_id', EMPLOYEE_ID,
                    'job_title', JOB_TITLE,
                    'job_family', JOB_FAMILY,
                    'campus', CAMPUS,
                    'hire_date', HIRE_DATE,
                    'active_status', ACTIVE_STATUS,
                    'source_table', 'CURATED_DEV.WORKDAY_DCIM.DIM_TECHNICIANS'
                ) AS properties
            FROM CURATED_DEV.WORKDAY_DCIM.DIM_TECHNICIANS
            WHERE WORKER_ID IS NOT NULL
              AND ACTIVE_STATUS = 'ACTIVE'
        ) AS src
        ON tgt.node_id = src.node_id
        WHEN MATCHED THEN UPDATE SET
            tgt.display_name = src.display_name,
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
            VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

        SELECT COUNT(*) INTO :v_tech_nodes
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
        WHERE node_type = 'TECHNICIAN' AND node_id LIKE 'DC_TECH_%';
    END IF;

    -- ── 2. CERTIFICATION nodes from WORKDAY_DCIM FACT_CERTIFICATIONS ───────
    LET v_cert_exists INTEGER := 0;
    SELECT COUNT(*) INTO :v_cert_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'WORKDAY_DCIM' AND table_name = 'FACT_CERTIFICATIONS';

    IF (:v_cert_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
        USING (
            SELECT
                'DC_CERT_' || MD5(CERTIFICATION_ID) AS node_id,
                'CERTIFICATION' AS node_type,
                'BUSINESS' AS layer,
                'WORKDAY_DCIM' AS source_system,
                CERTIFICATION_ID AS fqn,
                COALESCE(CERTIFICATION_NAME, CERTIFICATION_TYPE) || ' [' || COALESCE(STATUS, 'UNKNOWN') || ']' AS display_name,
                OBJECT_CONSTRUCT(
                    'certification_id', CERTIFICATION_ID,
                    'certification_name', CERTIFICATION_NAME,
                    'certification_type', CERTIFICATION_TYPE,
                    'status', STATUS,
                    'issue_date', ISSUE_DATE,
                    'expiry_date', EXPIRY_DATE,
                    'worker_id', WORKER_ID,
                    'source_table', 'CURATED_DEV.WORKDAY_DCIM.FACT_CERTIFICATIONS'
                ) AS properties
            FROM CURATED_DEV.WORKDAY_DCIM.FACT_CERTIFICATIONS
            WHERE CERTIFICATION_ID IS NOT NULL
        ) AS src
        ON tgt.node_id = src.node_id
        WHEN MATCHED THEN UPDATE SET
            tgt.display_name = src.display_name,
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
            VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

        SELECT COUNT(*) INTO :v_cert_nodes
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
        WHERE node_type = 'CERTIFICATION' AND node_id LIKE 'DC_CERT_%';
    END IF;

    -- ── 3. TEAM nodes from WORKDAY_DCIM DIM_TEAMS ─────────────────────────
    LET v_team_exists INTEGER := 0;
    SELECT COUNT(*) INTO :v_team_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'WORKDAY_DCIM' AND table_name = 'DIM_TEAMS';

    IF (:v_team_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
        USING (
            SELECT
                'DC_TEAM_' || MD5(TEAM_ID) AS node_id,
                'TEAM' AS node_type,
                'BUSINESS' AS layer,
                'WORKDAY_DCIM' AS source_system,
                TEAM_ID AS fqn,
                COALESCE(TEAM_NAME, TEAM_ID) AS display_name,
                OBJECT_CONSTRUCT(
                    'team_id', TEAM_ID,
                    'team_name', TEAM_NAME,
                    'campus', CAMPUS,
                    'shift_coverage', SHIFT_COVERAGE,
                    'source_table', 'CURATED_DEV.WORKDAY_DCIM.DIM_TEAMS'
                ) AS properties
            FROM CURATED_DEV.WORKDAY_DCIM.DIM_TEAMS
            WHERE TEAM_ID IS NOT NULL
        ) AS src
        ON tgt.node_id = src.node_id
        WHEN MATCHED THEN UPDATE SET
            tgt.display_name = src.display_name,
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
            VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

        SELECT COUNT(*) INTO :v_team_nodes
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
        WHERE node_type = 'TEAM' AND node_id LIKE 'DC_TEAM_%';
    END IF;

    -- ── 4. TECHNICIAN_HAS_CERTIFICATION Edges (tech → cert) ────────────────
    IF (:v_cert_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
        USING (
            SELECT
                'DC_THC_' || MD5(CERTIFICATION_ID) AS edge_id,
                'DC_TECH_' || MD5(WORKER_ID) AS source_node_id,
                'DC_CERT_' || MD5(CERTIFICATION_ID) AS target_node_id,
                'TECHNICIAN_HAS_CERTIFICATION' AS edge_type,
                'BUSINESS' AS layer,
                1.0 AS weight,
                OBJECT_CONSTRUCT(
                    'status', STATUS,
                    'expiry_date', EXPIRY_DATE
                ) AS properties
            FROM CURATED_DEV.WORKDAY_DCIM.FACT_CERTIFICATIONS
            WHERE WORKER_ID IS NOT NULL AND CERTIFICATION_ID IS NOT NULL
        ) AS src
        ON tgt.edge_id = src.edge_id
        WHEN MATCHED THEN UPDATE SET
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight, properties)
            VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight, src.properties);

        SELECT COUNT(*) INTO :v_cert_edges
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
        WHERE edge_type = 'TECHNICIAN_HAS_CERTIFICATION' AND edge_id LIKE 'DC_THC_%';
    END IF;

    -- ── 5. TECHNICIAN_ASSIGNED_TO_INCIDENT Edges (tech → incident) ─────────
    -- Cross-system: Workday technicians linked to ServiceNow incidents
    -- via matching technician_id (uuid5 deterministic)
    LET v_inc_exists INTEGER := 0;
    SELECT COUNT(*) INTO :v_inc_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'SERVICENOW' AND table_name = 'FACT_INCIDENTS';

    IF (:v_table_exists > 0 AND :v_inc_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
        USING (
            SELECT
                'DC_TAI_' || MD5(i.INCIDENT_ID) AS edge_id,
                'DC_TECH_' || MD5(i.ASSIGNED_TECHNICIAN_ID) AS source_node_id,
                'DC_INC_' || MD5(i.INCIDENT_ID) AS target_node_id,
                'TECHNICIAN_ASSIGNED_TO_INCIDENT' AS edge_type,
                'BUSINESS' AS layer,
                1.0 AS weight,
                OBJECT_CONSTRUCT(
                    'priority', i.PRIORITY,
                    'category', i.CATEGORY,
                    'resolution_time_hours', i.RESOLUTION_TIME_HOURS
                ) AS properties
            FROM CURATED_DEV.SERVICENOW.FACT_INCIDENTS i
            INNER JOIN CURATED_DEV.WORKDAY_DCIM.DIM_TECHNICIANS t
                ON i.ASSIGNED_TECHNICIAN_ID = t.WORKER_ID
            WHERE i.ASSIGNED_TECHNICIAN_ID IS NOT NULL
              AND i.INCIDENT_ID IS NOT NULL
        ) AS src
        ON tgt.edge_id = src.edge_id
        WHEN MATCHED THEN UPDATE SET
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight, properties)
            VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight, src.properties);

        SELECT COUNT(*) INTO :v_assignment_edges
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
        WHERE edge_type = 'TECHNICIAN_ASSIGNED_TO_INCIDENT' AND edge_id LIKE 'DC_TAI_%';
    END IF;

    -- ── 6. TECHNICIAN_IN_TEAM Edges (tech → team) ─────────────────────────
    LET v_membership_exists INTEGER := 0;
    SELECT COUNT(*) INTO :v_membership_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'WORKDAY_DCIM' AND table_name = 'FACT_TEAM_MEMBERSHIPS';

    IF (:v_membership_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
        USING (
            SELECT
                'DC_TIT_' || MD5(WORKER_ID || TEAM_ID) AS edge_id,
                'DC_TECH_' || MD5(WORKER_ID) AS source_node_id,
                'DC_TEAM_' || MD5(TEAM_ID) AS target_node_id,
                'TECHNICIAN_IN_TEAM' AS edge_type,
                'BUSINESS' AS layer,
                1.0 AS weight,
                OBJECT_CONSTRUCT(
                    'role_in_team', ROLE_IN_TEAM,
                    'start_date', START_DATE
                ) AS properties
            FROM CURATED_DEV.WORKDAY_DCIM.FACT_TEAM_MEMBERSHIPS
            WHERE WORKER_ID IS NOT NULL AND TEAM_ID IS NOT NULL
        ) AS src
        ON tgt.edge_id = src.edge_id
        WHEN MATCHED THEN UPDATE SET
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight, properties)
            VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight, src.properties);

        SELECT COUNT(*) INTO :v_team_edges
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
        WHERE edge_type = 'TECHNICIAN_IN_TEAM' AND edge_id LIKE 'DC_TIT_%';
    END IF;

    -- ── 7. SAME_AS Edges (cross-system entity resolution) ──────────────────
    -- Links Workday technician nodes to ServiceNow incident assignees
    -- via deterministic technician_id (uuid5) match
    IF (:v_table_exists > 0 AND :v_inc_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
        USING (
            SELECT DISTINCT
                'DC_MATCH_' || MD5(t.WORKER_ID || i.ASSIGNED_TECHNICIAN_ID) AS edge_id,
                'DC_TECH_' || MD5(t.WORKER_ID) AS source_node_id,
                'DC_INC_' || MD5(i.INCIDENT_ID) AS target_node_id,
                'SAME_AS' AS edge_type,
                'CROSS' AS layer,
                1.0 AS weight,
                OBJECT_CONSTRUCT(
                    'match_method', 'TECHNICIAN_ID',
                    'confidence', 0.99,
                    'workday_worker_id', t.WORKER_ID,
                    'servicenow_technician_id', i.ASSIGNED_TECHNICIAN_ID
                ) AS properties
            FROM CURATED_DEV.WORKDAY_DCIM.DIM_TECHNICIANS t
            INNER JOIN CURATED_DEV.SERVICENOW.FACT_INCIDENTS i
                ON t.WORKER_ID = i.ASSIGNED_TECHNICIAN_ID
            WHERE t.WORKER_ID IS NOT NULL
              AND i.ASSIGNED_TECHNICIAN_ID IS NOT NULL
        ) AS src
        ON tgt.edge_id = src.edge_id
        WHEN MATCHED THEN UPDATE SET
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight, properties)
            VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight, src.properties);

        SELECT COUNT(*) INTO :v_sameas_edges
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
        WHERE edge_type = 'SAME_AS' AND edge_id LIKE 'DC_MATCH_%';
    END IF;

    -- ── 8. CROSS-LAYER STORED_IN Edges ─────────────────────────────────────

    -- TECHNICIAN nodes → DIM_TECHNICIANS table metadata node
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
    USING (
        SELECT DISTINCT
            'DC_WD_EDGE_' || MD5(
                n.node_id ||
                'META_' || MD5('CURATED_DEV.WORKDAY_DCIM.DIM_TECHNICIANS') ||
                'STORED_IN'
            ) AS edge_id,
            n.node_id AS source_node_id,
            'META_' || MD5('CURATED_DEV.WORKDAY_DCIM.DIM_TECHNICIANS') AS target_node_id,
            'STORED_IN' AS edge_type,
            'CROSS' AS layer,
            1.0 AS weight
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n
        WHERE n.node_id LIKE 'DC_TECH_%'
          AND n.node_type = 'TECHNICIAN'
    ) AS src
    ON tgt.edge_id = src.edge_id
    WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
        VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);

    -- CERTIFICATION nodes → FACT_CERTIFICATIONS table metadata node
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
    USING (
        SELECT DISTINCT
            'DC_WD_EDGE_' || MD5(
                n.node_id ||
                'META_' || MD5('CURATED_DEV.WORKDAY_DCIM.FACT_CERTIFICATIONS') ||
                'STORED_IN'
            ) AS edge_id,
            n.node_id AS source_node_id,
            'META_' || MD5('CURATED_DEV.WORKDAY_DCIM.FACT_CERTIFICATIONS') AS target_node_id,
            'STORED_IN' AS edge_type,
            'CROSS' AS layer,
            1.0 AS weight
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n
        WHERE n.node_id LIKE 'DC_CERT_%'
          AND n.node_type = 'CERTIFICATION'
    ) AS src
    ON tgt.edge_id = src.edge_id
    WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
        VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);

    SELECT COUNT(*) INTO :v_cross_edges
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
    WHERE (edge_id LIKE 'DC_WD_EDGE_%' OR edge_id LIKE 'DC_MATCH_%')
      AND layer = 'CROSS';

    -- ── Final summary ─────────────────────────────────────────────────────
    RETURN 'DCIM Workday Graph populated. Nodes — Technicians: ' || :v_tech_nodes ||
           ', Certifications: ' || :v_cert_nodes ||
           ', Teams: ' || :v_team_nodes ||
           '. Edges — Certifications: ' || :v_cert_edges ||
           ', Incident Assignments: ' || :v_assignment_edges ||
           ', Team Memberships: ' || :v_team_edges ||
           ', Same-As (cross-system): ' || :v_sameas_edges ||
           ', Cross-layer: ' || :v_cross_edges;
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

SELECT 'DCIM Workday graph population procedure created' AS status;

SELECT node_type, COUNT(*) AS node_count
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
WHERE node_id LIKE 'DC_%'
  AND source_system = 'WORKDAY_DCIM'
GROUP BY node_type
ORDER BY node_type;

SELECT edge_type, layer, COUNT(*) AS edge_count
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
WHERE edge_id LIKE 'DC_T%' OR edge_id LIKE 'DC_MATCH_%' OR edge_id LIKE 'DC_WD_EDGE_%'
GROUP BY edge_type, layer
ORDER BY layer, edge_type;

-- ═══════════════════════════════════════════════════════════════════════════
-- GRANTS
-- ═══════════════════════════════════════════════════════════════════════════

GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_DCIM_POPULATE_WORKDAY_GRAPH() TO ROLE ONTOLOGY_ADMIN;
