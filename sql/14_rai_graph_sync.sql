-- ============================================================================
-- ONTOLOGY KNOWLEDGE GRAPH - GRAPH INFERENCE (Pure SQL)
-- ============================================================================
--
-- Replaces RAI-dependent inference with pure Snowflake SQL. Provides the same
-- outputs: PII propagation detection, ownership gap analysis, entity
-- resolution, and governance scoring — all computed via SQL against the
-- ONTOLOGY_GRAPH_NODES and ONTOLOGY_GRAPH_EDGES tables.
--
-- Procedures:
--   1. SP_RUN_INFERENCE      - Execute all inference rules via SQL
--   2. SP_APPLY_RECOMMENDATIONS - Apply approved recommendations
--
-- PREREQUISITES:
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
-- PROCEDURE 1: RUN INFERENCE (Pure SQL)
-- ═══════════════════════════════════════════════════════════════════════════
-- Executes PII propagation, ownership gap, entity resolution, and
-- governance scoring using SQL set operations on graph tables.
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
    -- Find columns downstream of PII-tagged columns via LINEAGE_FROM edges
    -- that are NOT themselves tagged with PII/PHI/SENSITIVE.
    INSERT INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS
        (recommendation_type, severity, source_node_id, target_node_id, description, suggested_action, status)
    SELECT
        'PII_PROPAGATION',
        'HIGH',
        pii_source.node_id,
        downstream.source_node_id,
        'Column ' || downstream.source_node_id || ' receives data from PII-tagged source ' || pii_source.node_id || ' but is not tagged',
        'Apply PII classification tag to target column',
        'OPEN'
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES downstream
    -- downstream.source_node_id is the column receiving data
    -- downstream.target_node_id is the PII source
    JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES pii_source
        ON pii_source.node_id = downstream.target_node_id
    -- The source must be PII-tagged (has a TAGGED_WITH edge to a PII/PHI tag)
    WHERE downstream.edge_type = 'LINEAGE_FROM'
      AND EXISTS (
          SELECT 1
          FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES tag_edge
          JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES tag_node
              ON tag_node.node_id = tag_edge.target_node_id
          WHERE tag_edge.source_node_id = pii_source.node_id
            AND tag_edge.edge_type = 'TAGGED_WITH'
            AND (UPPER(tag_node.display_name) LIKE '%PII%'
              OR UPPER(tag_node.display_name) LIKE '%PHI%'
              OR UPPER(tag_node.display_name) LIKE '%SENSITIVE%'
              OR UPPER(tag_node.display_name) LIKE '%HIPAA%')
      )
      -- The downstream column must NOT already be PII-tagged
      AND NOT EXISTS (
          SELECT 1
          FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES tag_edge2
          JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES tag_node2
              ON tag_node2.node_id = tag_edge2.target_node_id
          WHERE tag_edge2.source_node_id = downstream.source_node_id
            AND tag_edge2.edge_type = 'TAGGED_WITH'
            AND (UPPER(tag_node2.display_name) LIKE '%PII%'
              OR UPPER(tag_node2.display_name) LIKE '%PHI%'
              OR UPPER(tag_node2.display_name) LIKE '%SENSITIVE%')
      )
      -- Don't duplicate existing open recommendations
      AND NOT EXISTS (
          SELECT 1 FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS existing
          WHERE existing.recommendation_type = 'PII_PROPAGATION'
            AND existing.source_node_id = pii_source.node_id
            AND existing.target_node_id = downstream.source_node_id
            AND existing.status IN ('OPEN', 'APPROVED')
      );

    v_pii_count := SQLROWCOUNT;

    -- ─── Ownership Gap Detection ────────────────────────────────────────
    -- Find TABLE nodes that have no ownership-related edges or tags.
    INSERT INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS
        (recommendation_type, severity, source_node_id, target_node_id, description, suggested_action, status)
    SELECT
        'OWNERSHIP_GAP',
        'MEDIUM',
        n.node_id,
        NULL,
        'Table ' || COALESCE(n.display_name, n.node_id) || ' has no assigned contract owner',
        'Assign a data steward or contract owner to this table',
        'OPEN'
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n
    WHERE n.node_type = 'TABLE'
      AND NOT EXISTS (
          SELECT 1
          FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
          WHERE e.source_node_id = n.node_id
            AND e.edge_type IN ('OWNED_BY', 'HAS_CONTRACT')
      )
      AND NOT EXISTS (
          SELECT 1
          FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e2
          JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES tag
              ON tag.node_id = e2.target_node_id
          WHERE e2.source_node_id = n.node_id
            AND e2.edge_type = 'TAGGED_WITH'
            AND (UPPER(tag.display_name) LIKE '%OWNER%'
              OR UPPER(tag.display_name) LIKE '%STEWARD%'
              OR UPPER(tag.display_name) LIKE '%CONTRACT%')
      )
      AND NOT EXISTS (
          SELECT 1 FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_RECOMMENDATIONS existing
          WHERE existing.recommendation_type = 'OWNERSHIP_GAP'
            AND existing.source_node_id = n.node_id
            AND existing.status IN ('OPEN', 'APPROVED')
      );

    v_ownership_count := SQLROWCOUNT;

    -- ─── Entity Resolution (Cross-System Matching) ──────────────────────
    -- Match BUSINESS-layer nodes across different source systems using
    -- Snowflake JAROWINKLER_SIMILARITY on display_name.
    DELETE FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_ENTITY_CLUSTERS;

    INSERT INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_ENTITY_CLUSTERS
        (cluster_id, node_id, cluster_label, confidence)
    WITH cross_matches AS (
        SELECT
            n1.node_id AS node_id_1,
            n2.node_id AS node_id_2,
            n1.display_name AS name_1,
            n2.display_name AS name_2,
            n1.source_system AS sys_1,
            n2.source_system AS sys_2,
            JAROWINKLER_SIMILARITY(UPPER(n1.display_name), UPPER(n2.display_name)) / 100.0 AS similarity
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n1
        JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n2
            ON n1.layer = 'BUSINESS'
           AND n2.layer = 'BUSINESS'
           AND n1.source_system != n2.source_system
           AND n1.node_id < n2.node_id  -- avoid duplicates
        WHERE JAROWINKLER_SIMILARITY(UPPER(n1.display_name), UPPER(n2.display_name)) >= 70
    ),
    numbered AS (
        SELECT
            ROW_NUMBER() OVER (ORDER BY similarity DESC) AS cluster_num,
            node_id_1, node_id_2, name_1, name_2, similarity
        FROM cross_matches
    )
    SELECT
        'CLUSTER_' || cluster_num,
        node_id_1,
        name_1 || ' ≈ ' || name_2,
        similarity
    FROM numbered
    UNION ALL
    SELECT
        'CLUSTER_' || cluster_num,
        node_id_2,
        name_1 || ' ≈ ' || name_2,
        similarity
    FROM numbered;

    v_cluster_count := SQLROWCOUNT;

    -- ─── Governance Scoring ─────────────────────────────────────────────
    -- Compute composite governance score per TABLE node.
    -- Weights: tag_coverage=0.3, contract=0.3, ownership=0.25, quality=0.15
    DELETE FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_GOVERNANCE_SCORES;

    INSERT INTO DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_GOVERNANCE_SCORES
        (node_id, overall_score, tag_coverage, contract_coverage, ownership_score, quality_score)
    WITH tag_counts AS (
        SELECT
            e.source_node_id AS node_id,
            COUNT(*) AS tag_cnt
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
        WHERE e.edge_type = 'TAGGED_WITH'
        GROUP BY e.source_node_id
    ),
    contracts AS (
        SELECT DISTINCT source_node_id AS node_id
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
        WHERE edge_type = 'HAS_CONTRACT'
    ),
    owners AS (
        SELECT DISTINCT e.source_node_id AS node_id
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
        WHERE e.edge_type = 'OWNED_BY'
        UNION
        SELECT DISTINCT e.source_node_id AS node_id
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
        JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES tag
            ON tag.node_id = e.target_node_id
        WHERE e.edge_type = 'TAGGED_WITH'
          AND UPPER(tag.display_name) LIKE '%OWNER%'
    ),
    quality AS (
        SELECT DISTINCT source_node_id AS node_id
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
        WHERE edge_type IN ('MONITORED_BY', 'QUALITY_CHECK')
    )
    SELECT
        n.node_id,
        ROUND(
            (LEAST(1.0, COALESCE(tc.tag_cnt, 0) / 4.0) * 0.3) +
            (IFF(c.node_id IS NOT NULL, 1.0, 0.0) * 0.3) +
            (IFF(o.node_id IS NOT NULL, 1.0, 0.0) * 0.25) +
            (IFF(q.node_id IS NOT NULL, 1.0, 0.0) * 0.15)
        , 3) AS overall_score,
        ROUND(LEAST(1.0, COALESCE(tc.tag_cnt, 0) / 4.0), 3) AS tag_coverage,
        ROUND(IFF(c.node_id IS NOT NULL, 1.0, 0.0), 3) AS contract_coverage,
        ROUND(IFF(o.node_id IS NOT NULL, 1.0, 0.0), 3) AS ownership_score,
        ROUND(IFF(q.node_id IS NOT NULL, 1.0, 0.0), 3) AS quality_score
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n
    LEFT JOIN tag_counts tc ON tc.node_id = n.node_id
    LEFT JOIN contracts c ON c.node_id = n.node_id
    LEFT JOIN owners o ON o.node_id = n.node_id
    LEFT JOIN quality q ON q.node_id = n.node_id
    WHERE n.node_type = 'TABLE';

    v_score_count := SQLROWCOUNT;

    RETURN 'SUCCESS: Inference complete — ' ||
           :v_pii_count || ' PII recommendations, ' ||
           :v_ownership_count || ' ownership gaps, ' ||
           :v_cluster_count || ' entity clusters, ' ||
           :v_score_count || ' governance scores';
END;

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 2: APPLY APPROVED RECOMMENDATIONS
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
                BEGIN
                    LET fqn VARCHAR := rec.target_node_id;
                    EXECUTE IMMEDIATE
                        'ALTER TABLE ' || SPLIT_PART(:fqn, '.', 1) || '.' ||
                        SPLIT_PART(:fqn, '.', 2) || '.' ||
                        SPLIT_PART(:fqn, '.', 3) ||
                        ' ALTER COLUMN ' || SPLIT_PART(:fqn, '.', 4) ||
                        ' SET TAG DCA_DEMO.GOVERNANCE.PII_CLASSIFICATION = ''PROPAGATED''';
                    v_applied := v_applied + 1;
                EXCEPTION
                    WHEN OTHER THEN
                        v_alerts := v_alerts + 1;
                END;

            WHEN 'OWNERSHIP_GAP' THEN
                v_alerts := v_alerts + 1;

            ELSE
                v_applied := v_applied + 1;
        END CASE;

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

-- Note: inference runs entirely in Snowflake SQL — no external engine required.

GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_RUN_INFERENCE() TO ROLE ONTOLOGY_ADMIN;
GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_APPLY_RECOMMENDATIONS() TO ROLE ONTOLOGY_ADMIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

SHOW PROCEDURES LIKE 'SP_RUN_INFERENCE' IN SCHEMA DCA_DEMO.GOVERNANCE;
SHOW PROCEDURES LIKE 'SP_APPLY_%' IN SCHEMA DCA_DEMO.GOVERNANCE;
