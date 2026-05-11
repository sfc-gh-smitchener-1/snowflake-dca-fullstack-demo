-- ============================================================================
-- HCLS KNOWLEDGE GRAPH — CLINICAL GRAPH POPULATION
-- ============================================================================
-- Extends the base Ontology Knowledge Graph with deeper FHIR clinical nodes
-- and healthcare-specific edge types for care pathway analysis.
--
-- Prerequisites: scripts 11-15 deployed, SP_REFRESH_GRAPH() has run
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE DCA_DEMO;
USE SCHEMA GOVERNANCE;
USE WAREHOUSE COMPUTE_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE: SP_HCLS_POPULATE_CLINICAL_GRAPH
-- ═══════════════════════════════════════════════════════════════════════════
-- Populates ENCOUNTER, CONDITION, MEDICATION, and PRACTITIONER nodes
-- along with clinical relationship edges for care pathway analysis.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_POPULATE_CLINICAL_GRAPH()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_encounter_nodes INTEGER DEFAULT 0;
    v_condition_nodes INTEGER DEFAULT 0;
    v_medication_nodes INTEGER DEFAULT 0;
    v_practitioner_nodes INTEGER DEFAULT 0;
    v_clinical_edges INTEGER DEFAULT 0;
    v_cross_edges INTEGER DEFAULT 0;
    v_table_exists INTEGER DEFAULT 0;
BEGIN

    -- ── 1. ENCOUNTER nodes from FHIR FACT_ENCOUNTERS ──────────────────────
    SELECT COUNT(*) INTO :v_table_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'FHIR' AND table_name = 'FACT_ENCOUNTERS';

    IF (:v_table_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
        USING (
            SELECT
                'HCLS_ENC_' || MD5(ENCOUNTER_ID) AS node_id,
                'ENCOUNTER' AS node_type,
                'BUSINESS' AS layer,
                'FHIR' AS source_system,
                ENCOUNTER_ID AS fqn,
                COALESCE(CLASS, 'unknown') || ' - ' || COALESCE(STATUS, 'unknown') AS display_name,
                OBJECT_CONSTRUCT(
                    'encounter_id', ENCOUNTER_ID,
                    'class', CLASS,
                    'status', STATUS,
                    'period_start', PERIOD_START,
                    'period_end', PERIOD_END,
                    'source_table', 'CURATED_DEV.FHIR.FACT_ENCOUNTERS'
                ) AS properties
            FROM CURATED_DEV.FHIR.FACT_ENCOUNTERS
            WHERE ENCOUNTER_ID IS NOT NULL
        ) AS src
        ON tgt.node_id = src.node_id
        WHEN MATCHED THEN UPDATE SET
            tgt.display_name = src.display_name,
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
            VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

        SELECT COUNT(*) INTO :v_encounter_nodes
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
        WHERE node_type = 'ENCOUNTER' AND node_id LIKE 'HCLS_ENC_%';
    END IF;

    -- ── 2. CONDITION nodes from FHIR FACT_CONDITIONS ──────────────────────
    LET v_cond_exists INTEGER := 0;
    SELECT COUNT(*) INTO :v_cond_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'FHIR' AND table_name = 'FACT_CONDITIONS';

    IF (:v_cond_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
        USING (
            SELECT
                'HCLS_DX_' || MD5(CONDITION_ID) AS node_id,
                'CONDITION' AS node_type,
                'BUSINESS' AS layer,
                'FHIR' AS source_system,
                CONDITION_ID AS fqn,
                COALESCE(CODE_DISPLAY, CODE, CONDITION_ID) AS display_name,
                OBJECT_CONSTRUCT(
                    'condition_id', CONDITION_ID,
                    'code', CODE,
                    'code_display', CODE_DISPLAY,
                    'clinical_status', CLINICAL_STATUS,
                    'category', CATEGORY,
                    'source_table', 'CURATED_DEV.FHIR.FACT_CONDITIONS'
                ) AS properties
            FROM CURATED_DEV.FHIR.FACT_CONDITIONS
            WHERE CONDITION_ID IS NOT NULL
        ) AS src
        ON tgt.node_id = src.node_id
        WHEN MATCHED THEN UPDATE SET
            tgt.display_name = src.display_name,
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
            VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

        SELECT COUNT(*) INTO :v_condition_nodes
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
        WHERE node_type = 'CONDITION' AND node_id LIKE 'HCLS_DX_%';
    END IF;

    -- ── 3. MEDICATION nodes from FHIR FACT_MEDICATION_REQUESTS ────────────
    LET v_med_exists INTEGER := 0;
    SELECT COUNT(*) INTO :v_med_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'FHIR' AND table_name = 'FACT_MEDICATION_REQUESTS';

    IF (:v_med_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
        USING (
            SELECT DISTINCT
                'HCLS_MED_' || MD5(MEDICATION_CODE) AS node_id,
                'MEDICATION' AS node_type,
                'BUSINESS' AS layer,
                'FHIR' AS source_system,
                MEDICATION_CODE AS fqn,
                COALESCE(MEDICATION_NAME, MEDICATION_CODE) AS display_name,
                OBJECT_CONSTRUCT(
                    'medication_code', MEDICATION_CODE,
                    'medication_name', MEDICATION_NAME,
                    'source_table', 'CURATED_DEV.FHIR.FACT_MEDICATION_REQUESTS'
                ) AS properties
            FROM CURATED_DEV.FHIR.FACT_MEDICATION_REQUESTS
            WHERE MEDICATION_CODE IS NOT NULL
        ) AS src
        ON tgt.node_id = src.node_id
        WHEN MATCHED THEN UPDATE SET
            tgt.display_name = src.display_name,
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
            VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

        SELECT COUNT(*) INTO :v_medication_nodes
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
        WHERE node_type = 'MEDICATION' AND node_id LIKE 'HCLS_MED_%';
    END IF;

    -- ── 4. PRACTITIONER nodes from FHIR DIM_PRACTITIONER ──────────────────
    LET v_prac_exists INTEGER := 0;
    SELECT COUNT(*) INTO :v_prac_exists
    FROM CURATED_DEV.INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'FHIR' AND table_name = 'DIM_PRACTITIONER';

    IF (:v_prac_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES AS tgt
        USING (
            SELECT
                'HCLS_PRAC_' || MD5(PRACTITIONER_ID) AS node_id,
                'PRACTITIONER' AS node_type,
                'BUSINESS' AS layer,
                'FHIR' AS source_system,
                PRACTITIONER_ID AS fqn,
                COALESCE(NAME, PRACTITIONER_ID) AS display_name,
                OBJECT_CONSTRUCT(
                    'practitioner_id', PRACTITIONER_ID,
                    'name', NAME,
                    'specialty', SPECIALTY,
                    'source_table', 'CURATED_DEV.FHIR.DIM_PRACTITIONER'
                ) AS properties
            FROM CURATED_DEV.FHIR.DIM_PRACTITIONER
            WHERE PRACTITIONER_ID IS NOT NULL
        ) AS src
        ON tgt.node_id = src.node_id
        WHEN MATCHED THEN UPDATE SET
            tgt.display_name = src.display_name,
            tgt.properties = src.properties
        WHEN NOT MATCHED THEN INSERT (node_id, node_type, layer, source_system, fqn, display_name, properties)
            VALUES (src.node_id, src.node_type, src.layer, src.source_system, src.fqn, src.display_name, src.properties);

        SELECT COUNT(*) INTO :v_practitioner_nodes
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
        WHERE node_type = 'PRACTITIONER' AND node_id LIKE 'HCLS_PRAC_%';
    END IF;

    -- ── 5. CLINICAL EDGES ─────────────────────────────────────────────────

    -- ENCOUNTER → CONDITION (RESULTED_IN)
    IF (:v_cond_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
        USING (
            SELECT DISTINCT
                'HCLS_EDGE_' || MD5(
                    'HCLS_ENC_' || MD5(ENCOUNTER_KEY) ||
                    'HCLS_DX_' || MD5(CONDITION_ID) ||
                    'RESULTED_IN'
                ) AS edge_id,
                'HCLS_ENC_' || MD5(ENCOUNTER_KEY) AS source_node_id,
                'HCLS_DX_' || MD5(CONDITION_ID) AS target_node_id,
                'RESULTED_IN' AS edge_type,
                'BUSINESS' AS layer,
                1.0 AS weight
            FROM CURATED_DEV.FHIR.FACT_CONDITIONS
            WHERE ENCOUNTER_KEY IS NOT NULL AND CONDITION_ID IS NOT NULL
        ) AS src
        ON tgt.edge_id = src.edge_id
        WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
            VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);
    END IF;

    -- PATIENT → CONDITION (DIAGNOSED_WITH)
    IF (:v_cond_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
        USING (
            SELECT DISTINCT
                'HCLS_EDGE_' || MD5(
                    'BIZ_PAT_' || MD5(PATIENT_KEY) ||
                    'HCLS_DX_' || MD5(CONDITION_ID) ||
                    'DIAGNOSED_WITH'
                ) AS edge_id,
                'BIZ_PAT_' || MD5(PATIENT_KEY) AS source_node_id,
                'HCLS_DX_' || MD5(CONDITION_ID) AS target_node_id,
                'DIAGNOSED_WITH' AS edge_type,
                'BUSINESS' AS layer,
                1.0 AS weight
            FROM CURATED_DEV.FHIR.FACT_CONDITIONS
            WHERE PATIENT_KEY IS NOT NULL AND CONDITION_ID IS NOT NULL
        ) AS src
        ON tgt.edge_id = src.edge_id
        WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
            VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);
    END IF;

    -- PRACTITIONER → MEDICATION (PRESCRIBED) via medication requests
    IF (:v_med_exists > 0 AND :v_prac_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
        USING (
            SELECT DISTINCT
                'HCLS_EDGE_' || MD5(
                    'HCLS_PRAC_' || MD5(PRESCRIBER_ID) ||
                    'HCLS_MED_' || MD5(MEDICATION_CODE) ||
                    'PRESCRIBED'
                ) AS edge_id,
                'HCLS_PRAC_' || MD5(PRESCRIBER_ID) AS source_node_id,
                'HCLS_MED_' || MD5(MEDICATION_CODE) AS target_node_id,
                'PRESCRIBED' AS edge_type,
                'BUSINESS' AS layer,
                1.0 AS weight
            FROM CURATED_DEV.FHIR.FACT_MEDICATION_REQUESTS
            WHERE PRESCRIBER_ID IS NOT NULL AND MEDICATION_CODE IS NOT NULL
        ) AS src
        ON tgt.edge_id = src.edge_id
        WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
            VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);
    END IF;

    -- ENCOUNTER → PRACTITIONER (PERFORMED_BY) if performer data exists
    IF (:v_table_exists > 0 AND :v_prac_exists > 0) THEN
        MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
        USING (
            SELECT DISTINCT
                'HCLS_EDGE_' || MD5(
                    'HCLS_ENC_' || MD5(ENCOUNTER_ID) ||
                    'HCLS_PRAC_' || MD5(PERFORMER_ID) ||
                    'PERFORMED_BY'
                ) AS edge_id,
                'HCLS_ENC_' || MD5(ENCOUNTER_ID) AS source_node_id,
                'HCLS_PRAC_' || MD5(PERFORMER_ID) AS target_node_id,
                'PERFORMED_BY' AS edge_type,
                'BUSINESS' AS layer,
                1.0 AS weight
            FROM CURATED_DEV.FHIR.FACT_ENCOUNTERS
            WHERE PERFORMER_ID IS NOT NULL AND ENCOUNTER_ID IS NOT NULL
        ) AS src
        ON tgt.edge_id = src.edge_id
        WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
            VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);
    END IF;

    SELECT COUNT(*) INTO :v_clinical_edges
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
    WHERE edge_id LIKE 'HCLS_EDGE_%';

    -- ── 6. CROSS-LAYER EDGES (Clinical → Metadata) ───────────────────────
    -- ENCOUNTER nodes → FACT_ENCOUNTERS table metadata node (STORED_IN)
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
    USING (
        SELECT DISTINCT
            'HCLS_EDGE_' || MD5(
                n.node_id ||
                'META_' || MD5('CURATED_DEV.FHIR.FACT_ENCOUNTERS') ||
                'STORED_IN'
            ) AS edge_id,
            n.node_id AS source_node_id,
            'META_' || MD5('CURATED_DEV.FHIR.FACT_ENCOUNTERS') AS target_node_id,
            'STORED_IN' AS edge_type,
            'CROSS' AS layer,
            1.0 AS weight
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n
        WHERE n.node_id LIKE 'HCLS_ENC_%'
          AND n.node_type = 'ENCOUNTER'
    ) AS src
    ON tgt.edge_id = src.edge_id
    WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
        VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);

    -- CONDITION nodes → FACT_CONDITIONS table metadata node (STORED_IN)
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
    USING (
        SELECT DISTINCT
            'HCLS_EDGE_' || MD5(
                n.node_id ||
                'META_' || MD5('CURATED_DEV.FHIR.FACT_CONDITIONS') ||
                'STORED_IN'
            ) AS edge_id,
            n.node_id AS source_node_id,
            'META_' || MD5('CURATED_DEV.FHIR.FACT_CONDITIONS') AS target_node_id,
            'STORED_IN' AS edge_type,
            'CROSS' AS layer,
            1.0 AS weight
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n
        WHERE n.node_id LIKE 'HCLS_DX_%'
          AND n.node_type = 'CONDITION'
    ) AS src
    ON tgt.edge_id = src.edge_id
    WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
        VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);

    SELECT COUNT(*) INTO :v_cross_edges
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
    WHERE edge_id LIKE 'HCLS_EDGE_%' AND layer = 'CROSS';

    -- ── Final summary ─────────────────────────────────────────────────────
    RETURN 'HCLS Clinical Graph populated. Nodes — Encounters: ' || :v_encounter_nodes ||
           ', Conditions: ' || :v_condition_nodes ||
           ', Medications: ' || :v_medication_nodes ||
           ', Practitioners: ' || :v_practitioner_nodes ||
           '. Edges — Clinical: ' || :v_clinical_edges ||
           ', Cross-layer: ' || :v_cross_edges;
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

SELECT 'HCLS clinical graph population procedure created' AS status;

SELECT node_type, COUNT(*) AS node_count
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
WHERE node_id LIKE 'HCLS_%'
GROUP BY node_type
ORDER BY node_type;

SELECT edge_type, layer, COUNT(*) AS edge_count
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
WHERE edge_id LIKE 'HCLS_EDGE_%'
GROUP BY edge_type, layer
ORDER BY layer, edge_type;

-- ═══════════════════════════════════════════════════════════════════════════
-- GRANTS
-- ═══════════════════════════════════════════════════════════════════════════

GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_POPULATE_CLINICAL_GRAPH() TO ROLE ONTOLOGY_ADMIN;
