-- ============================================================================
-- ONTOLOGY KNOWLEDGE GRAPH - GRAPH ALGORITHMS (Pure SQL, On-Demand)
-- ============================================================================
--
-- Companion to sql/14_rai_graph_sync.sql.
--
-- Script 14 covers BATCH inference (PII propagation, ownership gaps, entity
-- resolution, governance scoring) and materializes results into recommendation
-- and score tables.
--
-- This script (16) covers ON-DEMAND GRAPH ALGORITHMS implemented entirely in
-- Snowflake SQL — any user can call them directly from a Snowsight Worksheet:
--
--     1. V_GRAPH_BIDIRECTIONAL_EDGES   -- undirected edge view (helper)
--     2. V_GRAPH_DEGREE_CENTRALITY     -- top-N hubs view
--     3. V_GRAPH_PII_PROPAGATION       -- live PII propagation findings
--     4. V_GRAPH_OWNERSHIP_GAPS        -- live ownership gap findings
--     5. V_GRAPH_GOVERNANCE_SCORES     -- live composite governance scores
--     6. SP_GRAPH_SHORTEST_PATH        -- shortest path between two node_ids
--     7. SP_GRAPH_CONNECTED_COMPONENTS -- weakly connected components
--     8. SP_GRAPH_NEIGHBORHOOD         -- k-hop neighborhood expansion
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
-- VIEW 1: BIDIRECTIONAL EDGES
-- ═══════════════════════════════════════════════════════════════════════════
-- Many graph algorithms treat edges as undirected. This view emits each edge
-- twice — once in each direction — so recursive CTEs can walk the graph as
-- an undirected graph without UNION ALL gymnastics in every query.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW DCA_DEMO.GOVERNANCE.V_GRAPH_BIDIRECTIONAL_EDGES AS
SELECT
    edge_id, edge_type, layer, weight,
    source_node_id AS from_node_id,
    target_node_id AS to_node_id,
    'FORWARD' AS direction
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES
UNION ALL
SELECT
    edge_id, edge_type, layer, weight,
    target_node_id AS from_node_id,
    source_node_id AS to_node_id,
    'REVERSE' AS direction
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES;

COMMENT ON VIEW DCA_DEMO.GOVERNANCE.V_GRAPH_BIDIRECTIONAL_EDGES IS
    'Helper view emitting each edge in both directions for undirected graph traversal';

-- ═══════════════════════════════════════════════════════════════════════════
-- VIEW 2: DEGREE CENTRALITY
-- ═══════════════════════════════════════════════════════════════════════════
-- Hub detection. Each node's degree is the count of distinct edges that
-- touch it. The centrality_score is normalized to the max degree in the
-- graph (so the most connected node has score 1.0).
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW DCA_DEMO.GOVERNANCE.V_GRAPH_DEGREE_CENTRALITY AS
WITH degrees AS (
    SELECT
        n.node_id,
        n.node_type,
        n.layer,
        n.source_system,
        n.display_name,
        COUNT(DISTINCT e.edge_id) AS degree
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n
    LEFT JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
        ON e.source_node_id = n.node_id
        OR e.target_node_id = n.node_id
    GROUP BY n.node_id, n.node_type, n.layer, n.source_system, n.display_name
)
SELECT
    node_id, node_type, layer, source_system, display_name, degree,
    ROUND(degree / NULLIF(MAX(degree) OVER (), 0), 4) AS centrality_score,
    RANK() OVER (ORDER BY degree DESC) AS centrality_rank
FROM degrees
WHERE degree > 0;

COMMENT ON VIEW DCA_DEMO.GOVERNANCE.V_GRAPH_DEGREE_CENTRALITY IS
    'Live degree centrality for every node; centrality_score normalized to max degree';

-- ═══════════════════════════════════════════════════════════════════════════
-- VIEW 3: PII PROPAGATION (LIVE)
-- ═══════════════════════════════════════════════════════════════════════════
-- Columns receiving data from PII/PHI-tagged sources but lacking their own
-- classification. Walks LINEAGE_FROM edges up to 10 hops upstream.
--
-- This is the live equivalent of the materialized recommendations produced by
-- SP_RUN_INFERENCE in script 14. Use this view when you want sub-second
-- "current state" rather than the snapshot from the last inference run.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW DCA_DEMO.GOVERNANCE.V_GRAPH_PII_PROPAGATION AS
WITH RECURSIVE phi_sources AS (
    SELECT DISTINCT n.node_id AS source_col, n.fqn AS source_fqn
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n
    JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
        ON e.source_node_id = n.node_id AND e.edge_type = 'TAGGED_WITH'
    JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES tag
        ON tag.node_id = e.target_node_id
    WHERE n.node_type = 'COLUMN'
      AND REGEXP_LIKE(tag.display_name, '.*(PII|PHI|SENSITIVE|HIPAA).*', 'i')
),
downstream AS (
    SELECT source_col, source_fqn, source_col AS current_col, 0 AS depth
    FROM phi_sources

    UNION ALL

    SELECT d.source_col, d.source_fqn, e.source_node_id, d.depth + 1
    FROM downstream d
    JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
        ON e.target_node_id = d.current_col
       AND e.edge_type = 'LINEAGE_FROM'
    WHERE d.depth < 10
)
SELECT DISTINCT
    d.current_col AS target_node_id,
    tn.fqn        AS target_fqn,
    d.source_col  AS source_node_id,
    d.source_fqn,
    d.depth       AS lineage_depth,
    'HIGH'        AS severity
FROM downstream d
JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES tn ON tn.node_id = d.current_col
WHERE d.depth > 0
  AND NOT EXISTS (
        SELECT 1
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e2
        JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES t2 ON t2.node_id = e2.target_node_id
        WHERE e2.source_node_id = d.current_col
          AND e2.edge_type = 'TAGGED_WITH'
          AND REGEXP_LIKE(t2.display_name, '.*(PII|PHI|SENSITIVE|HIPAA).*', 'i')
      );

COMMENT ON VIEW DCA_DEMO.GOVERNANCE.V_GRAPH_PII_PROPAGATION IS
    'Live PII/PHI propagation findings via recursive LINEAGE_FROM traversal (up to 10 hops)';

-- ═══════════════════════════════════════════════════════════════════════════
-- VIEW 4: OWNERSHIP GAPS (LIVE)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW DCA_DEMO.GOVERNANCE.V_GRAPH_OWNERSHIP_GAPS AS
SELECT
    t.node_id,
    t.display_name,
    t.fqn,
    t.source_system,
    'MEDIUM' AS severity
FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES t
WHERE t.node_type = 'TABLE'
  AND NOT EXISTS (
        SELECT 1 FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
        WHERE e.source_node_id = t.node_id AND e.edge_type = 'OWNED_BY'
      )
  AND NOT EXISTS (
        SELECT 1 FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
        WHERE e.source_node_id = t.node_id AND e.edge_type = 'HAS_CONTRACT'
      )
  AND NOT EXISTS (
        SELECT 1
        FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
        JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES tag ON tag.node_id = e.target_node_id
        WHERE e.source_node_id = t.node_id
          AND e.edge_type = 'TAGGED_WITH'
          AND REGEXP_LIKE(tag.display_name, '.*(OWNER|STEWARD|CONTRACT).*', 'i')
      );

COMMENT ON VIEW DCA_DEMO.GOVERNANCE.V_GRAPH_OWNERSHIP_GAPS IS
    'Live ownership gap findings: tables with no owner, contract, or steward edge';

-- ═══════════════════════════════════════════════════════════════════════════
-- VIEW 5: GOVERNANCE SCORES (LIVE)
-- ═══════════════════════════════════════════════════════════════════════════
-- Composite per-table governance score computed live from current edges
-- and tags.
--
-- Weights:   tag_coverage 30%, contract 30%, ownership 25%, quality 15%
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW DCA_DEMO.GOVERNANCE.V_GRAPH_GOVERNANCE_SCORES AS
WITH base AS (
    SELECT node_id, display_name, fqn, source_system
    FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES
    WHERE node_type = 'TABLE'
),
tag_counts AS (
    SELECT b.node_id, COUNT(DISTINCT e.target_node_id) AS tag_count
    FROM base b
    LEFT JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
        ON e.source_node_id = b.node_id AND e.edge_type = 'TAGGED_WITH'
    GROUP BY b.node_id
),
has_flags AS (
    SELECT
        b.node_id,
        MAX(CASE WHEN e.edge_type = 'HAS_CONTRACT' THEN 1 ELSE 0 END) AS has_contract,
        MAX(CASE WHEN e.edge_type = 'OWNED_BY'      THEN 1 ELSE 0 END) AS has_owner,
        MAX(CASE WHEN e.edge_type IN ('MONITORED_BY','QUALITY_CHECK') THEN 1 ELSE 0 END) AS has_quality
    FROM base b
    LEFT JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e ON e.source_node_id = b.node_id
    GROUP BY b.node_id
)
SELECT
    b.node_id,
    b.display_name,
    b.fqn,
    b.source_system,
    LEAST(tc.tag_count / 4.0, 1.0)                AS tag_coverage,
    hf.has_contract::FLOAT                        AS contract_coverage,
    hf.has_owner::FLOAT                           AS ownership_score,
    hf.has_quality::FLOAT                         AS quality_score,
    ROUND(
        LEAST(tc.tag_count / 4.0, 1.0) * 0.30
        + hf.has_contract * 0.30
        + hf.has_owner    * 0.25
        + hf.has_quality  * 0.15
    , 3) AS overall_score
FROM base b
JOIN tag_counts tc ON tc.node_id = b.node_id
JOIN has_flags  hf ON hf.node_id = b.node_id;

COMMENT ON VIEW DCA_DEMO.GOVERNANCE.V_GRAPH_GOVERNANCE_SCORES IS
    'Live composite governance scores per table (tag 30% / contract 30% / ownership 25% / quality 15%)';

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 1: SHORTEST PATH
-- ═══════════════════════════════════════════════════════════════════════════
-- Returns the shortest undirected path between two node_ids as a TABLE of
-- (position, node_id, node_type, display_name, source_system).
--
-- Implementation: BFS via recursive CTE with array-based cycle guard.
-- Performance: sub-second for paths up to ~10 hops on graphs < 1M edges.
-- Increase P_MAX_HOPS for deeper traversal (cost grows with depth and fan-out).
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_GRAPH_SHORTEST_PATH(
    P_FROM_ID  VARCHAR,
    P_TO_ID    VARCHAR,
    P_MAX_HOPS INTEGER DEFAULT 15
)
RETURNS TABLE (
    position      INTEGER,
    node_id       VARCHAR,
    node_type     VARCHAR,
    layer         VARCHAR,
    source_system VARCHAR,
    display_name  VARCHAR
)
LANGUAGE SQL
AS
DECLARE
    res RESULTSET;
BEGIN
    res := (
        WITH RECURSIVE paths AS (
            SELECT
                e.from_node_id                                 AS origin,
                e.to_node_id                                   AS current_node,
                ARRAY_CONSTRUCT(e.from_node_id, e.to_node_id)  AS path,
                1                                              AS depth
            FROM DCA_DEMO.GOVERNANCE.V_GRAPH_BIDIRECTIONAL_EDGES e
            WHERE e.from_node_id = :P_FROM_ID

            UNION ALL

            SELECT
                p.origin,
                e.to_node_id,
                ARRAY_APPEND(p.path, e.to_node_id),
                p.depth + 1
            FROM paths p
            JOIN DCA_DEMO.GOVERNANCE.V_GRAPH_BIDIRECTIONAL_EDGES e
              ON e.from_node_id = p.current_node
            WHERE p.depth < :P_MAX_HOPS
              AND NOT ARRAY_CONTAINS(e.to_node_id::VARIANT, p.path)
              AND p.current_node != :P_TO_ID
        ),
        winner AS (
            SELECT path, depth
            FROM paths
            WHERE current_node = :P_TO_ID
            ORDER BY depth ASC
            LIMIT 1
        ),
        exploded AS (
            SELECT idx::INTEGER AS position, value::VARCHAR AS node_id
            FROM winner, LATERAL FLATTEN(input => path)
        )
        SELECT
            ex.position,
            n.node_id,
            n.node_type,
            n.layer,
            n.source_system,
            n.display_name
        FROM exploded ex
        JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n ON n.node_id = ex.node_id
        ORDER BY ex.position
    );
    RETURN TABLE(res);
END;

COMMENT ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_GRAPH_SHORTEST_PATH(VARCHAR, VARCHAR, INTEGER) IS
    'BFS shortest path between two node_ids via recursive CTE (undirected, max P_MAX_HOPS)';

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 2: CONNECTED COMPONENTS
-- ═══════════════════════════════════════════════════════════════════════════
-- Weakly connected components via recursive reachability. For each seed node,
-- walk all reachable nodes up to P_MAX_DEPTH hops, then assign the minimum
-- reachable node_id as the component label.
--
-- Result: TABLE of (component_id, component_size, sample_node_ids).
-- Performance: O(V*E) at worst. Suitable for demo graphs <50k nodes; for much
-- larger graphs, materialize components incrementally rather than on-demand.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_GRAPH_CONNECTED_COMPONENTS(
    P_MAX_DEPTH INTEGER DEFAULT 20,
    P_TOP_N     INTEGER DEFAULT 50
)
RETURNS TABLE (
    component_id    VARCHAR,
    component_size  INTEGER,
    sample_nodes    ARRAY
)
LANGUAGE SQL
AS
DECLARE
    res RESULTSET;
BEGIN
    res := (
        WITH RECURSIVE reachable AS (
            SELECT node_id AS seed, node_id AS reached, 0 AS depth
            FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES

            UNION ALL

            SELECT r.seed, e.to_node_id, r.depth + 1
            FROM reachable r
            JOIN DCA_DEMO.GOVERNANCE.V_GRAPH_BIDIRECTIONAL_EDGES e
              ON e.from_node_id = r.reached
            WHERE r.depth < :P_MAX_DEPTH
        ),
        components AS (
            SELECT seed AS node_id,
                   MIN(reached) AS component_id
            FROM reachable
            GROUP BY seed
        ),
        sized AS (
            SELECT
                component_id,
                COUNT(DISTINCT node_id) AS comp_size,
                ARRAY_AGG(DISTINCT node_id) WITHIN GROUP (ORDER BY node_id) AS members
            FROM components
            GROUP BY component_id
        )
        SELECT
            component_id,
            comp_size AS component_size,
            ARRAY_SLICE(members, 0, 20) AS sample_nodes
        FROM sized
        ORDER BY comp_size DESC
        LIMIT :P_TOP_N
    );
    RETURN TABLE(res);
END;

COMMENT ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_GRAPH_CONNECTED_COMPONENTS(INTEGER, INTEGER) IS
    'Weakly connected components via recursive reachability + min(node_id) labelling';

-- ═══════════════════════════════════════════════════════════════════════════
-- PROCEDURE 3: K-HOP NEIGHBORHOOD
-- ═══════════════════════════════════════════════════════════════════════════
-- Returns every node reachable from P_START_ID within P_K hops, along with
-- the minimum hop distance to reach it.
--
-- Useful for "show me everything within 3 hops of this patient" style queries.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE DCA_DEMO.GOVERNANCE.SP_GRAPH_NEIGHBORHOOD(
    P_START_ID VARCHAR,
    P_K        INTEGER DEFAULT 3
)
RETURNS TABLE (
    node_id       VARCHAR,
    node_type     VARCHAR,
    layer         VARCHAR,
    source_system VARCHAR,
    display_name  VARCHAR,
    hop_distance  INTEGER
)
LANGUAGE SQL
AS
DECLARE
    res RESULTSET;
BEGIN
    res := (
        WITH RECURSIVE walk AS (
            SELECT :P_START_ID AS node_id, 0 AS hop

            UNION ALL

            SELECT e.to_node_id, w.hop + 1
            FROM walk w
            JOIN DCA_DEMO.GOVERNANCE.V_GRAPH_BIDIRECTIONAL_EDGES e
              ON e.from_node_id = w.node_id
            WHERE w.hop < :P_K
        ),
        min_hops AS (
            SELECT node_id, MIN(hop) AS hop_distance
            FROM walk
            GROUP BY node_id
        )
        SELECT
            n.node_id,
            n.node_type,
            n.layer,
            n.source_system,
            n.display_name,
            mh.hop_distance
        FROM min_hops mh
        JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n ON n.node_id = mh.node_id
        ORDER BY mh.hop_distance, n.display_name
    );
    RETURN TABLE(res);
END;

COMMENT ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_GRAPH_NEIGHBORHOOD(VARCHAR, INTEGER) IS
    'k-hop neighborhood expansion from a starting node, returning min hop distance to each reachable node';

-- ═══════════════════════════════════════════════════════════════════════════
-- GRANTS
-- ═══════════════════════════════════════════════════════════════════════════

GRANT SELECT ON VIEW DCA_DEMO.GOVERNANCE.V_GRAPH_BIDIRECTIONAL_EDGES  TO ROLE ONTOLOGY_CONSUMER;
GRANT SELECT ON VIEW DCA_DEMO.GOVERNANCE.V_GRAPH_DEGREE_CENTRALITY    TO ROLE ONTOLOGY_CONSUMER;
GRANT SELECT ON VIEW DCA_DEMO.GOVERNANCE.V_GRAPH_PII_PROPAGATION      TO ROLE ONTOLOGY_CONSUMER;
GRANT SELECT ON VIEW DCA_DEMO.GOVERNANCE.V_GRAPH_OWNERSHIP_GAPS       TO ROLE ONTOLOGY_CONSUMER;
GRANT SELECT ON VIEW DCA_DEMO.GOVERNANCE.V_GRAPH_GOVERNANCE_SCORES    TO ROLE ONTOLOGY_CONSUMER;

GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_GRAPH_SHORTEST_PATH(VARCHAR, VARCHAR, INTEGER)
    TO ROLE ONTOLOGY_CONSUMER;
GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_GRAPH_CONNECTED_COMPONENTS(INTEGER, INTEGER)
    TO ROLE ONTOLOGY_CONSUMER;
GRANT USAGE ON PROCEDURE DCA_DEMO.GOVERNANCE.SP_GRAPH_NEIGHBORHOOD(VARCHAR, INTEGER)
    TO ROLE ONTOLOGY_CONSUMER;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICATION
-- ═══════════════════════════════════════════════════════════════════════════

SHOW VIEWS LIKE 'V_GRAPH_%' IN SCHEMA DCA_DEMO.GOVERNANCE;
SHOW PROCEDURES LIKE 'SP_GRAPH_%' IN SCHEMA DCA_DEMO.GOVERNANCE;

SELECT 'Graph algorithms deployed: 5 views, 3 procedures' AS status;

-- ═══════════════════════════════════════════════════════════════════════════
-- EXAMPLE USAGE — copy/paste into a Worksheet
-- ═══════════════════════════════════════════════════════════════════════════
--
-- -- Top 20 most-connected nodes
-- SELECT * FROM DCA_DEMO.GOVERNANCE.V_GRAPH_DEGREE_CENTRALITY
-- ORDER BY centrality_rank LIMIT 20;
--
-- -- Live PHI propagation findings (no batch refresh needed)
-- SELECT * FROM DCA_DEMO.GOVERNANCE.V_GRAPH_PII_PROPAGATION;
--
-- -- Composite governance score per table
-- SELECT * FROM DCA_DEMO.GOVERNANCE.V_GRAPH_GOVERNANCE_SCORES
-- ORDER BY overall_score ASC LIMIT 10;
--
-- -- Shortest path between two nodes (pick real node_ids from your env)
-- CALL DCA_DEMO.GOVERNANCE.SP_GRAPH_SHORTEST_PATH(
--     'HCLS_PAT_<patient_md5>',
--     'WD_WKR_<worker_md5>',
--     10
-- );
--
-- -- Connected components
-- CALL DCA_DEMO.GOVERNANCE.SP_GRAPH_CONNECTED_COMPONENTS(15, 25);
--
-- -- 3-hop neighborhood from a starting node
-- CALL DCA_DEMO.GOVERNANCE.SP_GRAPH_NEIGHBORHOOD(
--     'HCLS_PAT_<patient_md5>',
--     3
-- );
-- ═══════════════════════════════════════════════════════════════════════════
