-- ============================================================================
-- HCLS KNOWLEDGE GRAPH — CLINICAL RAI INFERENCE
-- ============================================================================
-- Extends the base RAI inference with HCLS-specific detection rules:
--   1. PHI detection using column naming patterns + lineage
--   2. Patient entity resolution across FHIR + Workday
--   3. Care pathway construction from temporal encounter sequences
--   4. HIPAA-specific compliance scoring
--
-- Prerequisites: 01_hcls_graph_populate.sql and 02_hcls_hipaa_gaps.sql
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE DCA_DEMO;
USE SCHEMA GOVERNANCE;
USE WAREHOUSE COMPUTE_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 1: SP_HCLS_PHI_DETECTION
-- ═══════════════════════════════════════════════════════════════════════════
-- Scans METADATA-layer COLUMN nodes for PHI indicators by name pattern.
-- Flags columns that match PHI patterns but lack HIPAA/PII tags.
-- Also detects untagged columns that receive data from tagged PHI sources.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_PHI_DETECTION()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_findings_direct INTEGER DEFAULT 0;
    v_findings_lineage INTEGER DEFAULT 0;
BEGIN
    -- Direct PHI detection: columns matching PHI name patterns without HIPAA tags
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS AS tgt
    USING (
        SELECT
            'HCLS_PHI_' || MD5(n.node_id) AS recommendation_id,
            n.node_id AS target_node_id,
            'PII_PROPAGATION' AS recommendation_type,
            CASE
                WHEN UPPER(n.display_name) LIKE '%SSN%' OR UPPER(n.display_name) LIKE '%MRN%'
                    THEN 'HIGH'
                WHEN UPPER(n.display_name) LIKE '%BIRTH%' OR UPPER(n.display_name) LIKE '%DOB%'
                    THEN 'HIGH'
                ELSE 'MEDIUM'
            END AS severity,
            'Column "' || n.display_name || '" in ' || n.fqn ||
            ' matches PHI naming pattern but has no HIPAA_CATEGORY or PII tag.' AS description,
            OBJECT_CONSTRUCT(
                'pattern_matched', n.display_name,
                'fqn', n.fqn,
                'detection_method', 'name_pattern',
                'remediation', 'Apply HIPAA_CATEGORY tag and masking policy'
            ) AS metadata,
            CURRENT_TIMESTAMP() AS detected_at
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n
        WHERE n.layer = 'METADATA'
          AND n.node_type = 'COLUMN'
          AND (
              UPPER(n.display_name) LIKE '%BIRTH%'
              OR UPPER(n.display_name) LIKE '%DOB%'
              OR UPPER(n.display_name) LIKE '%SSN%'
              OR UPPER(n.display_name) LIKE '%MRN%'
              OR UPPER(n.display_name) LIKE '%PATIENT_NAME%'
              OR UPPER(n.display_name) LIKE '%ADDRESS%'
              OR UPPER(n.display_name) LIKE '%PHONE%'
              OR UPPER(n.display_name) LIKE '%EMAIL%'
          )
          -- Exclude columns that already have a TAGGED_WITH edge to a PII/HIPAA tag
          AND NOT EXISTS (
              SELECT 1
              FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
              JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES tag_node
                ON e.target_node_id = tag_node.node_id
              WHERE e.source_node_id = n.node_id
                AND e.edge_type = 'TAGGED_WITH'
                AND (UPPER(tag_node.display_name) LIKE '%PII%'
                     OR UPPER(tag_node.display_name) LIKE '%HIPAA%'
                     OR UPPER(tag_node.display_name) LIKE '%PHI%')
          )
    ) AS src
    ON tgt.recommendation_id = src.recommendation_id
    WHEN MATCHED THEN UPDATE SET
        tgt.severity = src.severity,
        tgt.description = src.description,
        tgt.metadata = src.metadata,
        tgt.detected_at = src.detected_at
    WHEN NOT MATCHED THEN INSERT (recommendation_id, target_node_id, recommendation_type, severity, description, metadata, detected_at)
        VALUES (src.recommendation_id, src.target_node_id, src.recommendation_type, src.severity, src.description, src.metadata, src.detected_at);

    SELECT COUNT(*) INTO :v_findings_direct
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS
    WHERE recommendation_id LIKE 'HCLS_PHI_%';

    -- Lineage-based PHI detection: columns receiving data from tagged PHI sources
    -- that are themselves untagged
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS AS tgt
    USING (
        SELECT
            'HCLS_PHI_LIN_' || MD5(downstream.node_id) AS recommendation_id,
            downstream.node_id AS target_node_id,
            'PII_PROPAGATION' AS recommendation_type,
            'HIGH' AS severity,
            'Column "' || downstream.display_name || '" receives data from PHI-tagged source "' ||
            upstream.display_name || '" via lineage but has no HIPAA tag itself.' AS description,
            OBJECT_CONSTRUCT(
                'downstream_fqn', downstream.fqn,
                'upstream_fqn', upstream.fqn,
                'detection_method', 'lineage_propagation',
                'remediation', 'Propagate HIPAA_CATEGORY tag to downstream column or apply masking'
            ) AS metadata,
            CURRENT_TIMESTAMP() AS detected_at
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES lineage_edge
        JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES upstream
            ON lineage_edge.source_node_id = upstream.node_id
        JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES downstream
            ON lineage_edge.target_node_id = downstream.node_id
        WHERE lineage_edge.edge_type = 'LINEAGE_FROM'
          AND upstream.node_type = 'COLUMN'
          AND downstream.node_type = 'COLUMN'
          -- Upstream IS tagged with PHI/PII/HIPAA
          AND EXISTS (
              SELECT 1
              FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e2
              JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES tag2
                ON e2.target_node_id = tag2.node_id
              WHERE e2.source_node_id = upstream.node_id
                AND e2.edge_type = 'TAGGED_WITH'
                AND (UPPER(tag2.display_name) LIKE '%PII%'
                     OR UPPER(tag2.display_name) LIKE '%HIPAA%'
                     OR UPPER(tag2.display_name) LIKE '%PHI%')
          )
          -- Downstream is NOT tagged
          AND NOT EXISTS (
              SELECT 1
              FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e3
              JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES tag3
                ON e3.target_node_id = tag3.node_id
              WHERE e3.source_node_id = downstream.node_id
                AND e3.edge_type = 'TAGGED_WITH'
                AND (UPPER(tag3.display_name) LIKE '%PII%'
                     OR UPPER(tag3.display_name) LIKE '%HIPAA%'
                     OR UPPER(tag3.display_name) LIKE '%PHI%')
          )
    ) AS src
    ON tgt.recommendation_id = src.recommendation_id
    WHEN MATCHED THEN UPDATE SET
        tgt.severity = src.severity,
        tgt.description = src.description,
        tgt.metadata = src.metadata,
        tgt.detected_at = src.detected_at
    WHEN NOT MATCHED THEN INSERT (recommendation_id, target_node_id, recommendation_type, severity, description, metadata, detected_at)
        VALUES (src.recommendation_id, src.target_node_id, src.recommendation_type, src.severity, src.description, src.metadata, src.detected_at);

    SELECT COUNT(*) INTO :v_findings_lineage
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS
    WHERE recommendation_id LIKE 'HCLS_PHI_LIN_%';

    RETURN 'PHI Detection complete. Direct findings: ' || :v_findings_direct ||
           ', Lineage-propagation findings: ' || :v_findings_lineage;
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 2: SP_HCLS_PATIENT_RESOLUTION
-- ═══════════════════════════════════════════════════════════════════════════
-- Cross-system entity matching between FHIR PATIENT and Workday EMPLOYEE.
-- Uses simplified name-matching (last name + first initial) for demo.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_PATIENT_RESOLUTION()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_matches INTEGER DEFAULT 0;
    v_cross_edges INTEGER DEFAULT 0;
BEGIN
    -- Find matches between PATIENT and EMPLOYEE nodes on name similarity
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_ENTITY_CLUSTERS AS tgt
    USING (
        SELECT
            'HCLS_MATCH_' || MD5(pat.node_id || emp.node_id) AS cluster_id,
            pat.node_id AS entity_a_node_id,
            emp.node_id AS entity_b_node_id,
            'PATIENT_EMPLOYEE' AS cluster_type,
            -- Confidence: exact last name + first initial = 0.85; exact full match = 0.95
            CASE
                WHEN UPPER(pat.display_name) = UPPER(emp.display_name) THEN 0.95
                ELSE 0.85
            END AS confidence_score,
            OBJECT_CONSTRUCT(
                'patient_fqn', pat.fqn,
                'employee_fqn', emp.fqn,
                'patient_display', pat.display_name,
                'employee_display', emp.display_name,
                'match_method', 'name_token_match',
                'match_criteria', 'last_name + first_initial'
            ) AS metadata,
            CURRENT_TIMESTAMP() AS resolved_at
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES pat
        JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES emp
            ON pat.node_type = 'PATIENT'
            AND emp.node_type = 'EMPLOYEE'
            AND pat.source_system = 'FHIR'
            AND emp.source_system = 'WORKDAY'
            -- Match on: same last name token AND same first initial
            AND SPLIT_PART(UPPER(TRIM(pat.display_name)), ' ', -1) =
                SPLIT_PART(UPPER(TRIM(emp.display_name)), ' ', -1)
            AND LEFT(UPPER(TRIM(pat.display_name)), 1) =
                LEFT(UPPER(TRIM(emp.display_name)), 1)
    ) AS src
    ON tgt.cluster_id = src.cluster_id
    WHEN MATCHED THEN UPDATE SET
        tgt.confidence_score = src.confidence_score,
        tgt.metadata = src.metadata,
        tgt.resolved_at = src.resolved_at
    WHEN NOT MATCHED THEN INSERT (cluster_id, entity_a_node_id, entity_b_node_id, cluster_type, confidence_score, metadata, resolved_at)
        VALUES (src.cluster_id, src.entity_a_node_id, src.entity_b_node_id, src.cluster_type, src.confidence_score, src.metadata, src.resolved_at);

    SELECT COUNT(*) INTO :v_matches
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_ENTITY_CLUSTERS
    WHERE cluster_type = 'PATIENT_EMPLOYEE';

    -- Create CROSS edges between matched entities (SAME_AS)
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
    USING (
        SELECT
            'HCLS_EDGE_' || MD5(
                entity_a_node_id || entity_b_node_id || 'SAME_AS'
            ) AS edge_id,
            entity_a_node_id AS source_node_id,
            entity_b_node_id AS target_node_id,
            'SAME_AS' AS edge_type,
            'CROSS' AS layer,
            confidence_score AS weight
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_ENTITY_CLUSTERS
        WHERE cluster_type = 'PATIENT_EMPLOYEE'
          AND confidence_score >= 0.80
    ) AS src
    ON tgt.edge_id = src.edge_id
    WHEN MATCHED THEN UPDATE SET tgt.weight = src.weight
    WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
        VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);

    SELECT COUNT(*) INTO :v_cross_edges
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
    WHERE edge_type = 'SAME_AS' AND edge_id LIKE 'HCLS_EDGE_%';

    RETURN 'Patient resolution complete. Matches found: ' || :v_matches ||
           ', Cross-entity edges created: ' || :v_cross_edges;
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 3: SP_HCLS_CARE_PATHWAY
-- ═══════════════════════════════════════════════════════════════════════════
-- Builds temporal care pathway edges:
--   - Sequential NEXT_ENCOUNTER edges between patient encounters
--   - RESULTED_IN edges from encounters to conditions
--   - TREATMENT_PLAN edges linking conditions to medications
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_CARE_PATHWAY()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_sequence_edges INTEGER DEFAULT 0;
    v_treatment_edges INTEGER DEFAULT 0;
BEGIN
    -- Temporal sequencing: NEXT_ENCOUNTER edges between consecutive encounters per patient
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
    USING (
        WITH ordered_encounters AS (
            SELECT
                n.node_id,
                n.properties:encounter_id::VARCHAR AS encounter_id,
                n.properties:period_start::TIMESTAMP AS period_start,
                -- Derive patient_id from encounter data
                e.source_node_id AS patient_node_id,
                ROW_NUMBER() OVER (
                    PARTITION BY e.source_node_id
                    ORDER BY n.properties:period_start::TIMESTAMP
                ) AS seq_num
            FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n
            JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
                ON e.target_node_id = n.node_id
                AND e.edge_type = 'HAS_ENCOUNTER'
            WHERE n.node_type = 'ENCOUNTER'
              AND n.node_id LIKE 'HCLS_ENC_%'
        )
        SELECT
            'HCLS_EDGE_' || MD5(
                curr.node_id || nxt.node_id || 'NEXT_ENCOUNTER'
            ) AS edge_id,
            curr.node_id AS source_node_id,
            nxt.node_id AS target_node_id,
            'NEXT_ENCOUNTER' AS edge_type,
            'BUSINESS' AS layer,
            1.0 AS weight
        FROM ordered_encounters curr
        JOIN ordered_encounters nxt
            ON curr.patient_node_id = nxt.patient_node_id
            AND nxt.seq_num = curr.seq_num + 1
    ) AS src
    ON tgt.edge_id = src.edge_id
    WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
        VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);

    SELECT COUNT(*) INTO :v_sequence_edges
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
    WHERE edge_type = 'NEXT_ENCOUNTER' AND edge_id LIKE 'HCLS_EDGE_%';

    -- TREATMENT_PLAN edges: CONDITION → MEDICATION (via medication requests linked to encounters)
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES AS tgt
    USING (
        SELECT DISTINCT
            'HCLS_EDGE_' || MD5(
                'HCLS_DX_' || MD5(c.CONDITION_ID) ||
                'HCLS_MED_' || MD5(m.MEDICATION_CODE) ||
                'TREATMENT_PLAN'
            ) AS edge_id,
            'HCLS_DX_' || MD5(c.CONDITION_ID) AS source_node_id,
            'HCLS_MED_' || MD5(m.MEDICATION_CODE) AS target_node_id,
            'TREATMENT_PLAN' AS edge_type,
            'BUSINESS' AS layer,
            1.0 AS weight
        FROM CURATED_DEV.FHIR.FACT_CONDITIONS c
        JOIN CURATED_DEV.FHIR.FACT_MEDICATION_REQUESTS m
            ON c.ENCOUNTER_KEY = m.ENCOUNTER_KEY
        WHERE c.CONDITION_ID IS NOT NULL
          AND m.MEDICATION_CODE IS NOT NULL
          AND c.ENCOUNTER_KEY IS NOT NULL
    ) AS src
    ON tgt.edge_id = src.edge_id
    WHEN NOT MATCHED THEN INSERT (edge_id, source_node_id, target_node_id, edge_type, layer, weight)
        VALUES (src.edge_id, src.source_node_id, src.target_node_id, src.edge_type, src.layer, src.weight);

    SELECT COUNT(*) INTO :v_treatment_edges
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
    WHERE edge_type = 'TREATMENT_PLAN' AND edge_id LIKE 'HCLS_EDGE_%';

    RETURN 'Care pathway complete. Sequence edges: ' || :v_sequence_edges ||
           ', Treatment plan edges: ' || :v_treatment_edges;
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 4: SP_HCLS_HIPAA_SCORING
-- ═══════════════════════════════════════════════════════════════════════════
-- HIPAA-specific governance scoring for FHIR-sourced nodes.
-- Evaluates: classification, access controls, BAA coverage,
-- audit trail, and de-identification status.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_HIPAA_SCORING()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_scored_nodes INTEGER DEFAULT 0;
BEGIN
    -- Score each FHIR-sourced node on HIPAA compliance dimensions
    MERGE INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_GOVERNANCE_SCORES AS tgt
    USING (
        SELECT
            n.node_id,
            n.node_type,
            n.display_name,
            -- Dimension 1: HIPAA Classification (has HIPAA_CATEGORY tag?)
            CASE WHEN EXISTS (
                SELECT 1 FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
                JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES tag ON e.target_node_id = tag.node_id
                WHERE e.source_node_id = n.node_id
                  AND e.edge_type = 'TAGGED_WITH'
                  AND (UPPER(tag.display_name) LIKE '%HIPAA%' OR UPPER(tag.display_name) LIKE '%PHI%')
            ) THEN 1.0 ELSE 0.0 END AS hipaa_classification,
            -- Dimension 2: Access Controls (restricted to HEALTHCARE_CONSUMER or equivalent?)
            CASE WHEN NOT EXISTS (
                SELECT 1 FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
                JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES role_node ON e.source_node_id = role_node.node_id
                WHERE e.target_node_id = n.node_id
                  AND e.edge_type = 'GRANTED_TO'
                  AND role_node.node_type = 'ROLE'
                  AND UPPER(role_node.display_name) NOT LIKE '%HEALTH%'
                  AND UPPER(role_node.display_name) NOT LIKE '%CLINICAL%'
                  AND UPPER(role_node.display_name) NOT LIKE '%FHIR%'
                  AND UPPER(role_node.display_name) NOT IN ('SYSADMIN', 'ACCOUNTADMIN', 'DATA_ADMIN')
            ) THEN 1.0 ELSE 0.0 END AS access_controls,
            -- Dimension 3: BAA Coverage (if accessed by external roles, BAA edge exists?)
            CASE
                WHEN NOT EXISTS (
                    SELECT 1 FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
                    JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES role_node ON e.source_node_id = role_node.node_id
                    WHERE e.target_node_id = n.node_id
                      AND e.edge_type = 'GRANTED_TO'
                      AND (UPPER(role_node.display_name) LIKE '%EXTERNAL%'
                           OR UPPER(role_node.display_name) LIKE '%PARTNER%'
                           OR UPPER(role_node.display_name) LIKE '%MARKETPLACE%')
                ) THEN 1.0  -- No external access, BAA not needed
                WHEN EXISTS (
                    SELECT 1 FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES baa
                    WHERE baa.source_node_id = n.node_id
                      AND baa.edge_type = 'COVERED_BY_BAA'
                ) THEN 1.0  -- External access exists AND BAA exists
                ELSE 0.0    -- External access without BAA
            END AS baa_coverage,
            -- Dimension 4: Audit Trail (ACCESS_HISTORY shows queries?)
            CASE WHEN EXISTS (
                SELECT 1 FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
                WHERE e.target_node_id = n.node_id
                  AND e.edge_type IN ('QUERIED', 'ACCESSED_BY')
            ) THEN 1.0 ELSE 0.5 END AS audit_trail,  -- 0.5 = no evidence either way
            -- Dimension 5: De-identification (if shared externally, DE_IDENTIFIED_FROM edge?)
            CASE
                WHEN NOT EXISTS (
                    SELECT 1 FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
                    JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES role_node ON e.source_node_id = role_node.node_id
                    WHERE e.target_node_id = n.node_id
                      AND e.edge_type = 'GRANTED_TO'
                      AND (UPPER(role_node.display_name) LIKE '%EXTERNAL%'
                           OR UPPER(role_node.display_name) LIKE '%RESEARCH%')
                ) THEN 1.0  -- Not shared externally, de-id not required
                WHEN EXISTS (
                    SELECT 1 FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES de
                    WHERE de.target_node_id = n.node_id
                      AND de.edge_type = 'DE_IDENTIFIED_FROM'
                ) THEN 1.0  -- Shared externally AND has de-identification lineage
                ELSE 0.0    -- Shared externally without de-identification
            END AS de_identification,
            -- Weighted composite score
            ROUND(
                (0.25 * CASE WHEN EXISTS (
                    SELECT 1 FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
                    JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES tag ON e.target_node_id = tag.node_id
                    WHERE e.source_node_id = n.node_id AND e.edge_type = 'TAGGED_WITH'
                      AND (UPPER(tag.display_name) LIKE '%HIPAA%' OR UPPER(tag.display_name) LIKE '%PHI%')
                ) THEN 1.0 ELSE 0.0 END) +
                (0.25 * CASE WHEN NOT EXISTS (
                    SELECT 1 FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
                    JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES role_node ON e.source_node_id = role_node.node_id
                    WHERE e.target_node_id = n.node_id AND e.edge_type = 'GRANTED_TO'
                      AND role_node.node_type = 'ROLE'
                      AND UPPER(role_node.display_name) NOT LIKE '%HEALTH%'
                      AND UPPER(role_node.display_name) NOT LIKE '%CLINICAL%'
                      AND UPPER(role_node.display_name) NOT LIKE '%FHIR%'
                      AND UPPER(role_node.display_name) NOT IN ('SYSADMIN', 'ACCOUNTADMIN', 'DATA_ADMIN')
                ) THEN 1.0 ELSE 0.0 END) +
                (0.20 * CASE WHEN NOT EXISTS (
                    SELECT 1 FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
                    JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES rn ON e.source_node_id = rn.node_id
                    WHERE e.target_node_id = n.node_id AND e.edge_type = 'GRANTED_TO'
                      AND (UPPER(rn.display_name) LIKE '%EXTERNAL%' OR UPPER(rn.display_name) LIKE '%PARTNER%'
                           OR UPPER(rn.display_name) LIKE '%MARKETPLACE%')
                ) THEN 1.0 WHEN EXISTS (
                    SELECT 1 FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES baa
                    WHERE baa.source_node_id = n.node_id AND baa.edge_type = 'COVERED_BY_BAA'
                ) THEN 1.0 ELSE 0.0 END) +
                (0.15 * CASE WHEN EXISTS (
                    SELECT 1 FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
                    WHERE e.target_node_id = n.node_id AND e.edge_type IN ('QUERIED', 'ACCESSED_BY')
                ) THEN 1.0 ELSE 0.5 END) +
                (0.15 * CASE WHEN NOT EXISTS (
                    SELECT 1 FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
                    JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES rn ON e.source_node_id = rn.node_id
                    WHERE e.target_node_id = n.node_id AND e.edge_type = 'GRANTED_TO'
                      AND (UPPER(rn.display_name) LIKE '%EXTERNAL%' OR UPPER(rn.display_name) LIKE '%RESEARCH%')
                ) THEN 1.0 WHEN EXISTS (
                    SELECT 1 FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES de
                    WHERE de.target_node_id = n.node_id AND de.edge_type = 'DE_IDENTIFIED_FROM'
                ) THEN 1.0 ELSE 0.0 END)
            , 3) AS composite_score,
            CURRENT_TIMESTAMP() AS scored_at
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n
        WHERE n.source_system = 'FHIR'
          AND n.layer IN ('METADATA', 'BUSINESS')
          AND n.node_type IN ('TABLE', 'ENCOUNTER', 'CONDITION', 'MEDICATION', 'PRACTITIONER', 'PATIENT')
    ) AS src
    ON tgt.node_id = src.node_id
    WHEN MATCHED THEN UPDATE SET
        tgt.hipaa_classification = src.hipaa_classification,
        tgt.access_controls = src.access_controls,
        tgt.baa_coverage = src.baa_coverage,
        tgt.audit_trail = src.audit_trail,
        tgt.de_identification = src.de_identification,
        tgt.composite_score = src.composite_score,
        tgt.scored_at = src.scored_at
    WHEN NOT MATCHED THEN INSERT (node_id, node_type, display_name, hipaa_classification, access_controls, baa_coverage, audit_trail, de_identification, composite_score, scored_at)
        VALUES (src.node_id, src.node_type, src.display_name, src.hipaa_classification, src.access_controls, src.baa_coverage, src.audit_trail, src.de_identification, src.composite_score, src.scored_at);

    SELECT COUNT(*) INTO :v_scored_nodes
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_GOVERNANCE_SCORES
    WHERE node_id IN (
        SELECT node_id FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES WHERE source_system = 'FHIR'
    );

    RETURN 'HIPAA scoring complete. Scored nodes: ' || :v_scored_nodes;
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 5: SP_HCLS_RUN_ALL (Orchestrator)
-- ═══════════════════════════════════════════════════════════════════════════
-- Runs all HCLS RAI procedures in sequence and records a snapshot.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_RUN_ALL()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_result_graph VARCHAR;
    v_result_phi VARCHAR;
    v_result_resolution VARCHAR;
    v_result_pathway VARCHAR;
    v_result_scoring VARCHAR;
    v_snapshot_id VARCHAR;
BEGIN
    -- Step 1: Populate clinical graph nodes and edges
    CALL DCA_DEMO.GOVERNANCE.SP_HCLS_POPULATE_CLINICAL_GRAPH();
    SELECT * INTO :v_result_graph FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

    -- Step 2: PHI Detection
    CALL DCA_DEMO.GOVERNANCE.SP_HCLS_PHI_DETECTION();
    SELECT * INTO :v_result_phi FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

    -- Step 3: Patient Entity Resolution
    CALL DCA_DEMO.GOVERNANCE.SP_HCLS_PATIENT_RESOLUTION();
    SELECT * INTO :v_result_resolution FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

    -- Step 4: Care Pathway Construction
    CALL DCA_DEMO.GOVERNANCE.SP_HCLS_CARE_PATHWAY();
    SELECT * INTO :v_result_pathway FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

    -- Step 5: HIPAA Compliance Scoring
    CALL DCA_DEMO.GOVERNANCE.SP_HCLS_HIPAA_SCORING();
    SELECT * INTO :v_result_scoring FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

    -- Record snapshot
    LET v_snapshot_id := 'HCLS_SNAPSHOT_' || TO_VARCHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS');

    INSERT INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_SNAPSHOTS (snapshot_id, snapshot_type, created_at, metadata)
    SELECT
        :v_snapshot_id,
        'HCLS_RAI_RUN',
        CURRENT_TIMESTAMP(),
        OBJECT_CONSTRUCT(
            'graph_result', :v_result_graph,
            'phi_result', :v_result_phi,
            'resolution_result', :v_result_resolution,
            'pathway_result', :v_result_pathway,
            'scoring_result', :v_result_scoring,
            'node_count', (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES WHERE node_id LIKE 'HCLS_%'),
            'edge_count', (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES WHERE edge_id LIKE 'HCLS_EDGE_%'),
            'recommendations_count', (SELECT COUNT(*) FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS WHERE recommendation_id LIKE 'HCLS_%')
        );

    RETURN 'HCLS RAI pipeline complete. Snapshot: ' || :v_snapshot_id || CHR(10) ||
           '  Graph: ' || :v_result_graph || CHR(10) ||
           '  PHI: ' || :v_result_phi || CHR(10) ||
           '  Resolution: ' || :v_result_resolution || CHR(10) ||
           '  Pathway: ' || :v_result_pathway || CHR(10) ||
           '  Scoring: ' || :v_result_scoring;
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

SELECT 'HCLS Clinical RAI inference procedures created successfully' AS status;

-- ═══════════════════════════════════════════════════════════════════════════
-- GRANTS
-- ═══════════════════════════════════════════════════════════════════════════

GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_PHI_DETECTION() TO ROLE ONTOLOGY_ADMIN;
GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_PATIENT_RESOLUTION() TO ROLE ONTOLOGY_ADMIN;
GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_CARE_PATHWAY() TO ROLE ONTOLOGY_ADMIN;
GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_HIPAA_SCORING() TO ROLE ONTOLOGY_ADMIN;
GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_HCLS_RUN_ALL() TO ROLE ONTOLOGY_ADMIN;
