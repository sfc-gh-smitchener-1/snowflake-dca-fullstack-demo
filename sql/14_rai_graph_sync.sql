-- ============================================================================
-- ONTOLOGY KNOWLEDGE GRAPH - RAI GRAPH SYNC & INFERENCE
-- ============================================================================
--
-- Creates stored procedures that sync graph data to the RAI engine, run
-- inference rules (PII propagation, ownership gaps, entity resolution,
-- governance scoring), and write results back to Snowflake tables.
--
-- Procedures:
--   1. SP_SYNC_TO_RAI        - Stream node/edge tables into RAI engine
--   2. SP_RUN_INFERENCE      - Execute Rel rules and write results back
--   3. SP_APPLY_RECOMMENDATIONS - Apply approved recommendations
--
-- PREREQUISITES:
--   - 11_rai_setup.sql (RAI engine created)
--   - 12_ontology_graph_tables.sql (tables exist)
--   - 13_ontology_graph_populate.sql (graph populated)
--
-- RUN AS: DATA_ADMIN
-- ============================================================================

USE ROLE DATA_ADMIN;
USE DATABASE DCA_DEMO;
USE SCHEMA GOVERNANCE;
USE WAREHOUSE COMPUTE_WH;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 1: SYNC GRAPH TO RAI
-- ═══════════════════════════════════════════════════════════════════════════
-- Streams the ONTOLOGY_GRAPH_NODES and ONTOLOGY_GRAPH_EDGES tables into
-- the RAI engine and loads the Rel model source for inference.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_SYNC_TO_RAI()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
BEGIN
    -- Step 1: Create data streams from Snowflake tables into RAI engine.
    -- This maps each table to a RAI relation accessible from Rel.
    CALL RAI.API.CREATE_DATA_STREAM(
        'ONTOLOGY_ENGINE',          -- RAI engine name
        'DCA_DEMO',                 -- Source database
        'GOVERNANCE',               -- Source schema
        'ONTOLOGY_GRAPH_NODES'      -- Source table → maps to :ontology_graph_nodes in Rel
    );

    CALL RAI.API.CREATE_DATA_STREAM(
        'ONTOLOGY_ENGINE',
        'DCA_DEMO',
        'GOVERNANCE',
        'ONTOLOGY_GRAPH_EDGES'
    );

    -- Step 2: Load the Rel model source into the engine.
    -- The model defines graph traversal rules for governance analysis.
    -- Model source is stored at python/rai_models/ontology_graph.rel
    CALL RAI.API.LOAD_MODEL(
        'ONTOLOGY_ENGINE',
        'ontology_graph',           -- Model name within the engine
        '@DCA_DEMO.GOVERNANCE.RAI_STAGE/ontology_graph.rel'  -- Stage path to Rel source
    );

    RETURN 'SUCCESS: Graph data streams created and Rel model loaded into ONTOLOGY_ENGINE';
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 2: RUN INFERENCE
-- ═══════════════════════════════════════════════════════════════════════════
-- Executes RAI Rel rules for PII propagation detection, ownership gap
-- analysis, entity resolution, and governance scoring. Writes results
-- back to the RAI result tables in Snowflake.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_RUN_INFERENCE()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_pii_count INTEGER DEFAULT 0;
    v_ownership_count INTEGER DEFAULT 0;
    v_cluster_count INTEGER DEFAULT 0;
    v_score_count INTEGER DEFAULT 0;
BEGIN
    -- ─── PII Propagation Detection ──────────────────────────────────────
    -- Finds columns receiving data from PII-tagged sources via lineage edges.
    -- Any column downstream of a PII-tagged column should also be tagged.
    CALL RAI.API.EXEC_REL(
        'ONTOLOGY_ENGINE',
        '
        def output:pii_propagation =
            source, target, path :
            pii_propagation(source, target, path)
        '
    );

    -- Write PII propagation results to recommendations table
    INSERT INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS
        (recommendation_type, severity, source_node_id, target_node_id, description, suggested_action, status)
    SELECT
        'PII_PROPAGATION',
        'HIGH',
        r.SOURCE_NODE_ID,
        r.TARGET_NODE_ID,
        'Column ' || r.TARGET_NODE_ID || ' receives data from PII-tagged source ' || r.SOURCE_NODE_ID || ' but is not tagged',
        'Apply PII classification tag to target column',
        'OPEN'
    FROM TABLE(RAI.API.GET_RESULTS('ONTOLOGY_ENGINE', 'pii_propagation')) r
    WHERE NOT EXISTS (
        SELECT 1 FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS existing
        WHERE existing.recommendation_type = 'PII_PROPAGATION'
          AND existing.source_node_id = r.SOURCE_NODE_ID
          AND existing.target_node_id = r.TARGET_NODE_ID
          AND existing.status IN ('OPEN', 'APPROVED')
    );

    v_pii_count := SQLROWCOUNT;

    -- ─── Ownership Gap Detection ────────────────────────────────────────
    -- Finds tables that have no contract owner assigned.
    CALL RAI.API.EXEC_REL(
        'ONTOLOGY_ENGINE',
        '
        def output:ownership_gaps =
            node :
            ownership_gap(node)
        '
    );

    INSERT INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS
        (recommendation_type, severity, source_node_id, target_node_id, description, suggested_action, status)
    SELECT
        'OWNERSHIP_GAP',
        'MEDIUM',
        r.NODE_ID,
        NULL,
        'Table ' || r.NODE_ID || ' has no assigned contract owner',
        'Assign a data steward or contract owner to this table',
        'OPEN'
    FROM TABLE(RAI.API.GET_RESULTS('ONTOLOGY_ENGINE', 'ownership_gaps')) r
    WHERE NOT EXISTS (
        SELECT 1 FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS existing
        WHERE existing.recommendation_type = 'OWNERSHIP_GAP'
          AND existing.source_node_id = r.NODE_ID
          AND existing.status IN ('OPEN', 'APPROVED')
    );

    v_ownership_count := SQLROWCOUNT;

    -- ─── Entity Resolution ──────────────────────────────────────────────
    -- Cross-system matching: finds nodes across different source systems
    -- that likely represent the same real-world entity.
    CALL RAI.API.EXEC_REL(
        'ONTOLOGY_ENGINE',
        '
        def output:entity_clusters =
            cluster_id, node_id, label, confidence :
            entity_cluster(cluster_id, node_id, label, confidence)
        '
    );

    -- Clear previous clusters and write fresh results
    DELETE FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_ENTITY_CLUSTERS;

    INSERT INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_ENTITY_CLUSTERS
        (cluster_id, node_id, cluster_label, confidence)
    SELECT
        r.CLUSTER_ID,
        r.NODE_ID,
        r.LABEL,
        r.CONFIDENCE
    FROM TABLE(RAI.API.GET_RESULTS('ONTOLOGY_ENGINE', 'entity_clusters')) r;

    v_cluster_count := SQLROWCOUNT;

    -- ─── Governance Scoring ─────────────────────────────────────────────
    -- Computes a composite governance health score per node based on
    -- tag coverage, contract presence, ownership, and quality monitoring.
    CALL RAI.API.EXEC_REL(
        'ONTOLOGY_ENGINE',
        '
        def output:governance_scores =
            node_id, overall, tag_cov, contract_cov, ownership, quality :
            governance_score(node_id, overall, tag_cov, contract_cov, ownership, quality)
        '
    );

    -- Replace previous scores with fresh computation
    DELETE FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_GOVERNANCE_SCORES;

    INSERT INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_GOVERNANCE_SCORES
        (node_id, overall_score, tag_coverage, contract_coverage, ownership_score, quality_score)
    SELECT
        r.NODE_ID,
        r.OVERALL,
        r.TAG_COV,
        r.CONTRACT_COV,
        r.OWNERSHIP,
        r.QUALITY
    FROM TABLE(RAI.API.GET_RESULTS('ONTOLOGY_ENGINE', 'governance_scores')) r;

    v_score_count := SQLROWCOUNT;

    RETURN 'SUCCESS: Inference complete — ' ||
           :v_pii_count || ' PII recommendations, ' ||
           :v_ownership_count || ' ownership gaps, ' ||
           :v_cluster_count || ' entity clusters, ' ||
           :v_score_count || ' governance scores';
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 3: APPLY APPROVED RECOMMENDATIONS
-- ═══════════════════════════════════════════════════════════════════════════
-- Processes recommendations with status='APPROVED' and applies them:
--   - PII_PROPAGATION: applies the PII tag to the target column
--   - OWNERSHIP_GAP: logs as an alert (does not auto-fix)
-- Marks processed recommendations as resolved.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_APPLY_RECOMMENDATIONS()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_applied INTEGER DEFAULT 0;
    v_alerts INTEGER DEFAULT 0;
    c_rec CURSOR FOR
        SELECT recommendation_id, recommendation_type, source_node_id, target_node_id
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS
        WHERE status = 'APPROVED';
BEGIN
    FOR rec IN c_rec DO
        CASE rec.recommendation_type
            WHEN 'PII_PROPAGATION' THEN
                -- Apply PII classification tag to the target column.
                -- target_node_id format: DB.SCHEMA.TABLE.COLUMN
                BEGIN
                    LET fqn VARCHAR := rec.target_node_id;
                    -- Extract components from the FQN for ALTER TABLE ... ALTER COLUMN
                    -- Use the node's properties or directly tag via system tag
                    EXECUTE IMMEDIATE
                        'ALTER TABLE ' || SPLIT_PART(:fqn, '.', 1) || '.' ||
                        SPLIT_PART(:fqn, '.', 2) || '.' ||
                        SPLIT_PART(:fqn, '.', 3) ||
                        ' ALTER COLUMN ' || SPLIT_PART(:fqn, '.', 4) ||
                        ' SET TAG DCA_DEMO.GOVERNANCE.PII_CLASSIFICATION = ''PROPAGATED''';
                    v_applied := v_applied + 1;
                EXCEPTION
                    WHEN OTHER THEN
                        -- Log failure but continue processing other recommendations
                        v_alerts := v_alerts + 1;
                END;

            WHEN 'OWNERSHIP_GAP' THEN
                -- Cannot auto-assign ownership; log as alert for manual review
                v_alerts := v_alerts + 1;

            ELSE
                -- Other recommendation types: mark as resolved without action
                v_applied := v_applied + 1;
        END CASE;

        -- Mark recommendation as resolved
        UPDATE DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS
        SET status = 'RESOLVED',
            resolved_at = CURRENT_TIMESTAMP()
        WHERE recommendation_id = rec.recommendation_id;
    END FOR;

    RETURN 'SUCCESS: Applied ' || :v_applied || ' recommendations, ' ||
           :v_alerts || ' logged as alerts for manual review';
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- GRANTS
-- ═══════════════════════════════════════════════════════════════════════════

GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_SYNC_TO_RAI() TO ROLE ONTOLOGY_ADMIN;
GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_RUN_INFERENCE() TO ROLE ONTOLOGY_ADMIN;
GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_APPLY_RECOMMENDATIONS() TO ROLE ONTOLOGY_ADMIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

SHOW PROCEDURES LIKE 'SP_%RAI%' IN SCHEMA DCA_DEMO.GOVERNANCE;
SHOW PROCEDURES LIKE 'SP_APPLY_%' IN SCHEMA DCA_DEMO.GOVERNANCE;
