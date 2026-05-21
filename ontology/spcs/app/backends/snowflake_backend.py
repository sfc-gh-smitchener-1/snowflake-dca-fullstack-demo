"""Snowflake-native graph engine.

Implements the same protocol as the Neo4j backend, but using recursive
CTEs and window functions over ONTOLOGY_GRAPH_NODES / ONTOLOGY_GRAPH_EDGES.

Strengths: zero sidecar, always live (no sync), inherits Snowflake's
governance / replication / sharing / time-travel. Same security perimeter
as the data of record.

Weaknesses: deep-traversal queries (10+ hops) degrade; large-graph
community detection is expensive vs Neo4j GDS.

See docs/GRAPH_BACKENDS.md for the full compare/contrast.
"""

from __future__ import annotations

from typing import Any

from snowflake.snowpark import Session

from app.backends.base import GraphBackend

# Fully-qualified table names — kept as module constants so they're easy
# to swap (e.g., for time-travel queries via AT() in tests).
NODES_TABLE = "DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES"
EDGES_TABLE = "DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES"
SCORES_TABLE = "DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_GOVERNANCE_SCORES"


class SnowflakeBackend(GraphBackend):
    """Recursive-CTE-powered graph engine.

    The graph is queried in-place against Snowflake tables. Every query
    is a live read; nothing is staged in memory. Suited to the majority
    of governance queries; defers to Neo4j only for deep traversal or
    GDS-class algorithms.
    """

    name = "snowflake"

    def __init__(self, snowpark_session: Session):
        self._session = snowpark_session

    # ─── Lifecycle ───────────────────────────────────────────────────────

    async def initialize(self) -> None:
        # Nothing to warm — Snowflake serves queries on demand.
        # We do verify connectivity so the service fails fast at boot.
        self._session.sql("SELECT 1").collect()

    async def reload_graph(self) -> None:
        # No-op. The Snowflake backend reads live tables; there's nothing
        # to sync. Callers can refresh source data via the graph
        # population stored procedures (SP_REFRESH_GRAPH, etc.).
        return None

    async def is_healthy(self) -> bool:
        try:
            self._session.sql("SELECT 1").collect()
            return True
        except Exception:
            return False

    # ─── Graph Algorithms ────────────────────────────────────────────────

    async def get_shortest_path(
        self, from_id: str, to_id: str, max_depth: int = 15
    ) -> list[dict[str, Any]]:
        """Undirected shortest path via recursive CTE.

        Treats every edge as bidirectional by querying the edge table
        twice (once each direction) inside a UNION ALL.
        """
        # Snowflake recursive CTE: BFS with array-based cycle guard.
        # Depth-first would be more memory-efficient but harder to bound;
        # BFS with LIMIT 1 ORDER BY depth ASC returns the shortest path.
        query = f"""
        WITH RECURSIVE bidir_edges AS (
            SELECT source_node_id AS from_id, target_node_id AS to_id FROM {EDGES_TABLE}
            UNION ALL
            SELECT target_node_id AS from_id, source_node_id AS to_id FROM {EDGES_TABLE}
        ),
        paths AS (
            SELECT
                from_id                                AS origin,
                to_id                                  AS current_node,
                ARRAY_CONSTRUCT(from_id, to_id)        AS path,
                1                                      AS depth
            FROM bidir_edges
            WHERE from_id = '{from_id}'

            UNION ALL

            SELECT
                p.origin,
                e.to_id,
                ARRAY_APPEND(p.path, e.to_id),
                p.depth + 1
            FROM paths p
            JOIN bidir_edges e ON e.from_id = p.current_node
            WHERE p.depth < {max_depth}
              AND NOT ARRAY_CONTAINS(e.to_id::VARIANT, p.path)
              AND p.current_node != '{to_id}'  -- stop expanding once we've hit target
        )
        SELECT path, depth
        FROM paths
        WHERE current_node = '{to_id}'
        ORDER BY depth ASC
        LIMIT 1
        """
        rows = self._session.sql(query).collect()
        if not rows:
            return []

        row = rows[0].as_dict()
        # path is returned as a VARIANT array of node_ids; hydrate them
        path_ids = list(row["PATH"]) if isinstance(row["PATH"], list) else []
        if not path_ids:
            return []

        # Hydrate node details in path order
        placeholders = ", ".join(f"'{nid}'" for nid in path_ids)
        node_rows = self._session.sql(
            f"""
            SELECT node_id, node_type, layer, source_system, display_name
            FROM {NODES_TABLE}
            WHERE node_id IN ({placeholders})
            """
        ).collect()
        node_map = {r.as_dict()["NODE_ID"]: r.as_dict() for r in node_rows}
        return [
            {**node_map.get(nid, {"node_id": nid}), "position": i}
            for i, nid in enumerate(path_ids)
        ]

    async def get_centrality(self, top_n: int = 50) -> list[dict[str, Any]]:
        """Degree centrality via aggregation + window function for normalization."""
        query = f"""
        WITH degrees AS (
            SELECT n.node_id,
                   n.node_type,
                   n.display_name,
                   n.source_system,
                   COUNT(DISTINCT e.edge_id) AS degree
            FROM {NODES_TABLE} n
            LEFT JOIN {EDGES_TABLE} e
                ON e.source_node_id = n.node_id
                OR e.target_node_id = n.node_id
            GROUP BY n.node_id, n.node_type, n.display_name, n.source_system
        )
        SELECT node_id,
               node_type,
               display_name,
               source_system,
               degree,
               ROUND(degree / NULLIF(MAX(degree) OVER (), 0), 3) AS centrality_score
        FROM degrees
        WHERE degree > 0
        ORDER BY degree DESC
        LIMIT {top_n}
        """
        rows = self._session.sql(query).collect()
        return [{k.lower(): v for k, v in r.as_dict().items()} for r in rows]

    async def get_connected_components(
        self, max_iterations: int = 20
    ) -> list[dict[str, Any]]:
        """Weakly connected components via iterative label propagation.

        Each iteration broadcasts min(component_id) along edges until
        convergence (or max_iterations). For demo-sized graphs (<50k
        nodes) this typically converges in 5-10 rounds.

        Implemented as a single recursive CTE that walks every node's
        connected set up to max_iterations hops, then derives the
        component_id as the minimum reachable node_id. Equivalent in
        result to label propagation but simpler to express in SQL.
        """
        query = f"""
        WITH RECURSIVE bidir_edges AS (
            SELECT source_node_id AS from_id, target_node_id AS to_id FROM {EDGES_TABLE}
            UNION ALL
            SELECT target_node_id AS from_id, source_node_id AS to_id FROM {EDGES_TABLE}
        ),
        reachable AS (
            SELECT node_id AS seed, node_id AS reached, 0 AS depth FROM {NODES_TABLE}

            UNION ALL

            SELECT r.seed, e.to_id, r.depth + 1
            FROM reachable r
            JOIN bidir_edges e ON e.from_id = r.reached
            WHERE r.depth < {max_iterations}
        ),
        components AS (
            SELECT seed AS node_id,
                   MIN(reached) AS component_id
            FROM reachable
            GROUP BY seed
        ),
        sized AS (
            SELECT component_id,
                   COUNT(DISTINCT node_id) AS comp_size,
                   ARRAY_AGG(DISTINCT node_id) WITHIN GROUP (ORDER BY node_id)
                       AS member_ids
            FROM components
            GROUP BY component_id
        )
        SELECT component_id,
               comp_size AS size,
               -- truncate to first 20 ids for response size
               ARRAY_SLICE(member_ids, 0, 20) AS nodes
        FROM sized
        ORDER BY comp_size DESC
        LIMIT 50
        """
        rows = self._session.sql(query).collect()
        return [
            {
                "component_id": r.as_dict()["COMPONENT_ID"],
                "size": r.as_dict()["SIZE"],
                "nodes": list(r.as_dict().get("NODES") or []),
            }
            for r in rows
        ]

    # ─── Inference ───────────────────────────────────────────────────────

    async def detect_pii_propagation(
        self, max_depth: int = 10
    ) -> list[dict[str, Any]]:
        """Walk LINEAGE_FROM edges out from PII-tagged columns; flag any
        downstream column without its own PII tag.
        """
        query = f"""
        WITH RECURSIVE phi_sources AS (
            SELECT DISTINCT n.node_id AS source_col, n.fqn AS source_fqn
            FROM {NODES_TABLE} n
            JOIN {EDGES_TABLE} e ON e.source_node_id = n.node_id AND e.edge_type = 'TAGGED_WITH'
            JOIN {NODES_TABLE} tag ON tag.node_id = e.target_node_id
            WHERE n.node_type = 'COLUMN'
              AND REGEXP_LIKE(tag.display_name, '.*(PII|PHI|SENSITIVE|HIPAA).*', 'i')
        ),
        downstream AS (
            SELECT source_col, source_fqn, source_col AS current_col, 0 AS depth
            FROM phi_sources

            UNION ALL

            SELECT d.source_col, d.source_fqn, e.source_node_id, d.depth + 1
            FROM downstream d
            JOIN {EDGES_TABLE} e
              ON e.target_node_id = d.current_col
             AND e.edge_type = 'LINEAGE_FROM'
            WHERE d.depth < {max_depth}
        ),
        targets AS (
            SELECT DISTINCT d.current_col AS target_node_id,
                            d.source_col  AS source_node_id,
                            d.source_fqn  AS source_fqn
            FROM downstream d
            WHERE d.depth > 0
        )
        SELECT
            t.target_node_id,
            t.source_node_id,
            tn.fqn        AS target_fqn,
            t.source_fqn,
            'HIGH'        AS severity
        FROM targets t
        JOIN {NODES_TABLE} tn ON tn.node_id = t.target_node_id
        WHERE NOT EXISTS (
            SELECT 1
            FROM {EDGES_TABLE} e2
            JOIN {NODES_TABLE} t2 ON t2.node_id = e2.target_node_id
            WHERE e2.source_node_id = t.target_node_id
              AND e2.edge_type = 'TAGGED_WITH'
              AND REGEXP_LIKE(t2.display_name, '.*(PII|PHI|SENSITIVE|HIPAA).*', 'i')
        )
        """
        rows = self._session.sql(query).collect()
        return [{k.lower(): v for k, v in r.as_dict().items()} for r in rows]

    async def detect_ownership_gaps(self) -> list[dict[str, Any]]:
        """Tables with no OWNED_BY edge, no HAS_CONTRACT edge, and no
        owner/steward/contract tag.
        """
        query = f"""
        SELECT
            t.node_id,
            t.display_name,
            t.fqn,
            t.source_system,
            'MEDIUM' AS severity
        FROM {NODES_TABLE} t
        WHERE t.node_type = 'TABLE'
          AND NOT EXISTS (
              SELECT 1 FROM {EDGES_TABLE} e
              WHERE e.source_node_id = t.node_id AND e.edge_type = 'OWNED_BY'
          )
          AND NOT EXISTS (
              SELECT 1 FROM {EDGES_TABLE} e
              WHERE e.source_node_id = t.node_id AND e.edge_type = 'HAS_CONTRACT'
          )
          AND NOT EXISTS (
              SELECT 1
              FROM {EDGES_TABLE} e
              JOIN {NODES_TABLE} tag ON tag.node_id = e.target_node_id
              WHERE e.source_node_id = t.node_id
                AND e.edge_type = 'TAGGED_WITH'
                AND REGEXP_LIKE(tag.display_name, '.*(OWNER|STEWARD|CONTRACT).*', 'i')
          )
        ORDER BY t.display_name
        """
        rows = self._session.sql(query).collect()
        return [{k.lower(): v for k, v in r.as_dict().items()} for r in rows]

    async def resolve_entities(
        self, threshold: float = 0.7
    ) -> list[dict[str, Any]]:
        """Cross-system entity resolution using Snowflake's built-in
        JAROWINKLER_SIMILARITY. Identical to the Neo4j backend's fallback.
        """
        sim_threshold = int(threshold * 100)
        query = f"""
        SELECT
            n1.node_id        AS node_id_1,
            n2.node_id        AS node_id_2,
            n1.display_name   AS display_name_1,
            n2.display_name   AS display_name_2,
            n1.source_system  AS source_system_1,
            n2.source_system  AS source_system_2,
            JAROWINKLER_SIMILARITY(UPPER(n1.display_name), UPPER(n2.display_name)) / 100.0 AS confidence
        FROM {NODES_TABLE} n1
        JOIN {NODES_TABLE} n2
            ON n1.layer = 'BUSINESS'
           AND n2.layer = 'BUSINESS'
           AND n1.source_system != n2.source_system
           AND n1.node_id < n2.node_id
        WHERE JAROWINKLER_SIMILARITY(UPPER(n1.display_name), UPPER(n2.display_name)) >= {sim_threshold}
        ORDER BY confidence DESC
        LIMIT 100
        """
        rows = self._session.sql(query).collect()
        return [{k.lower(): v for k, v in r.as_dict().items()} for r in rows]

    async def compute_governance_scores(self) -> list[dict[str, Any]]:
        """Composite governance score per table.

        Same formula as the Neo4j backend so the two engines return
        comparable values:
            overall = 0.30 * tag_score
                    + 0.30 * contract_score
                    + 0.25 * ownership_score
                    + 0.15 * quality_score

        tag_score = min(distinct_tags / 4, 1.0)
        contract_score = 1 if HAS_CONTRACT edge exists else 0
        ownership_score = 1 if OWNED_BY edge exists else 0
        quality_score = 1 if MONITORED_BY or QUALITY_CHECK edge exists else 0
        """
        query = f"""
        WITH base AS (
            SELECT t.node_id, t.display_name
            FROM {NODES_TABLE} t
            WHERE t.node_type = 'TABLE'
        ),
        tag_counts AS (
            SELECT b.node_id, COUNT(DISTINCT e.target_node_id) AS tag_count
            FROM base b
            LEFT JOIN {EDGES_TABLE} e
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
            LEFT JOIN {EDGES_TABLE} e ON e.source_node_id = b.node_id
            GROUP BY b.node_id
        )
        SELECT
            b.node_id,
            b.display_name,
            LEAST(tc.tag_count / 4.0, 1.0)                        AS tag_coverage,
            hf.has_contract::FLOAT                                AS contract_coverage,
            hf.has_owner::FLOAT                                   AS ownership_score,
            hf.has_quality::FLOAT                                 AS quality_score,
            ROUND(
                LEAST(tc.tag_count / 4.0, 1.0) * 0.30
                + hf.has_contract * 0.30
                + hf.has_owner    * 0.25
                + hf.has_quality  * 0.15
            , 3) AS overall_score
        FROM base b
        JOIN tag_counts tc ON tc.node_id = b.node_id
        JOIN has_flags  hf ON hf.node_id = b.node_id
        ORDER BY overall_score ASC
        """
        rows = self._session.sql(query).collect()
        return [{k.lower(): v for k, v in r.as_dict().items()} for r in rows]

    # ─── Stats ───────────────────────────────────────────────────────────

    async def get_graph_stats(self) -> dict[str, Any]:
        query = f"""
        SELECT
            (SELECT COUNT(*) FROM {NODES_TABLE}) AS node_count,
            (SELECT COUNT(*) FROM {EDGES_TABLE}) AS edge_count
        """
        rows = self._session.sql(query).collect()
        d = rows[0].as_dict() if rows else {"NODE_COUNT": 0, "EDGE_COUNT": 0}
        return {
            "node_count": int(d.get("NODE_COUNT", 0) or 0),
            "edge_count": int(d.get("EDGE_COUNT", 0) or 0),
            "backend": self.name,
            "live": True,  # always reading source tables
        }
