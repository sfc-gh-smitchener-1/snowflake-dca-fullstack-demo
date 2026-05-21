"""Neo4j-backed graph engine.

Connects to a Neo4j sidecar container running on the same SPCS service.
Loads nodes/edges from Snowflake into Neo4j, then answers graph queries
via Cypher (shortest path, centrality, components, inference).

See docs/GRAPH_BACKENDS.md for when to pick this over the Snowflake
backend.
"""

from __future__ import annotations

import os
from typing import Any

from neo4j import AsyncGraphDatabase
from snowflake.snowpark import Session

from app.backends.base import GraphBackend


class Neo4jBackend(GraphBackend):
    """Cypher-powered graph engine, sidecar deployment.

    Strengths: deep traversal (5+ hops), GDS-class algorithms, sub-100ms
    shortest path. Reads node/edge data from Snowflake on initialize() and
    syncs into the in-memory graph.

    Weaknesses: stale until reload_graph() is called; requires a running
    container; needs a separate audit trail.
    """

    name = "neo4j"

    def __init__(self, snowpark_session: Session):
        self._session = snowpark_session
        self._driver = None
        self._uri = os.getenv("NEO4J_URI", "bolt://localhost:7687")
        self._user = os.getenv("NEO4J_USER", "neo4j")
        self._password = os.getenv("NEO4J_PASSWORD", "ontology-graph")

    # ─── Lifecycle ───────────────────────────────────────────────────────

    async def initialize(self) -> None:
        self._driver = AsyncGraphDatabase.driver(
            self._uri, auth=(self._user, self._password)
        )
        await self._sync_graph()

    async def reload_graph(self) -> None:
        await self._sync_graph()

    async def is_healthy(self) -> bool:
        if self._driver is None:
            return False
        try:
            async with self._driver.session() as s:
                await s.run("RETURN 1")
            return True
        except Exception:
            return False

    async def _sync_graph(self) -> None:
        """Clear and reload the in-memory graph from Snowflake."""
        async with self._driver.session() as neo:
            await neo.run("MATCH (n) DETACH DELETE n")
            await neo.run(
                "CREATE INDEX IF NOT EXISTS FOR (n:Node) ON (n.node_id)"
            )
            await neo.run(
                "CREATE INDEX IF NOT EXISTS FOR (n:Node) ON (n.node_type)"
            )
            await neo.run(
                "CREATE INDEX IF NOT EXISTS FOR (n:Node) ON (n.source_system)"
            )

            rows = self._session.sql(
                "SELECT node_id, node_type, layer, source_system, fqn, display_name "
                "FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES"
            ).collect()

            batch_size = 500
            for i in range(0, len(rows), batch_size):
                batch = rows[i : i + batch_size]
                nodes_data = [
                    {
                        "node_id": r.as_dict()["NODE_ID"],
                        "node_type": r.as_dict().get("NODE_TYPE", ""),
                        "layer": r.as_dict().get("LAYER", ""),
                        "source_system": r.as_dict().get("SOURCE_SYSTEM", ""),
                        "fqn": r.as_dict().get("FQN", ""),
                        "display_name": r.as_dict().get("DISPLAY_NAME", ""),
                    }
                    for r in batch
                ]
                await neo.run(
                    """
                    UNWIND $nodes AS node
                    CREATE (n:Node {
                        node_id: node.node_id,
                        node_type: node.node_type,
                        layer: node.layer,
                        source_system: node.source_system,
                        fqn: node.fqn,
                        display_name: node.display_name
                    })
                    """,
                    nodes=nodes_data,
                )

            # Apply secondary labels for common types — speeds up Cypher
            for type_, label in [
                ("TABLE", "Table"),
                ("COLUMN", "Column"),
                ("ROLE", "Role"),
                ("TAG", "Tag"),
            ]:
                await neo.run(
                    f"MATCH (n:Node) WHERE n.node_type = '{type_}' SET n:{label}"
                )

            edge_rows = self._session.sql(
                "SELECT edge_id, source_node_id, target_node_id, edge_type, layer, weight "
                "FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES"
            ).collect()

            for i in range(0, len(edge_rows), batch_size):
                batch = edge_rows[i : i + batch_size]
                edges_data = [
                    {
                        "edge_id": r.as_dict()["EDGE_ID"],
                        "source_node_id": r.as_dict()["SOURCE_NODE_ID"],
                        "target_node_id": r.as_dict()["TARGET_NODE_ID"],
                        "edge_type": r.as_dict().get("EDGE_TYPE", ""),
                        "layer": r.as_dict().get("LAYER", ""),
                        "weight": float(r.as_dict().get("WEIGHT", 1.0) or 1.0),
                    }
                    for r in batch
                ]
                await neo.run(
                    """
                    UNWIND $edges AS edge
                    MATCH (src:Node {node_id: edge.source_node_id})
                    MATCH (tgt:Node {node_id: edge.target_node_id})
                    CREATE (src)-[r:EDGE {
                        edge_id: edge.edge_id,
                        edge_type: edge.edge_type,
                        layer: edge.layer,
                        weight: edge.weight
                    }]->(tgt)
                    """,
                    edges=edges_data,
                )

            # Typed relationships for common edge types — supports rich pattern matching
            for edge_type in ["LINEAGE_FROM", "TAGGED_WITH", "OWNED_BY", "HAS_CONTRACT"]:
                await neo.run(
                    f"""
                    MATCH (src)-[e:EDGE]->(tgt) WHERE e.edge_type = '{edge_type}'
                    CREATE (src)-[:{edge_type} {{weight: e.weight}}]->(tgt)
                    """
                )

    # ─── Graph Algorithms ────────────────────────────────────────────────

    async def get_shortest_path(
        self, from_id: str, to_id: str, max_depth: int = 15
    ) -> list[dict[str, Any]]:
        async with self._driver.session() as neo:
            result = await neo.run(
                f"""
                MATCH p = shortestPath(
                    (src:Node {{node_id: $from_id}})-[*..{max_depth}]-(tgt:Node {{node_id: $to_id}})
                )
                RETURN [n IN nodes(p) | {{
                    node_id: n.node_id,
                    node_type: n.node_type,
                    layer: n.layer,
                    source_system: n.source_system,
                    display_name: n.display_name
                }}] AS path
                """,
                from_id=from_id,
                to_id=to_id,
            )
            record = await result.single()
            if record:
                return [
                    {**node, "position": i}
                    for i, node in enumerate(record["path"])
                ]
            return []

    async def get_centrality(self, top_n: int = 50) -> list[dict[str, Any]]:
        async with self._driver.session() as neo:
            result = await neo.run(
                """
                MATCH (n:Node)
                WITH n, size([(n)-[]-() | 1]) AS degree
                ORDER BY degree DESC
                LIMIT $top_n
                RETURN n.node_id AS node_id,
                       n.node_type AS node_type,
                       n.display_name AS display_name,
                       n.source_system AS source_system,
                       degree
                """,
                top_n=top_n,
            )
            records = [r async for r in result]
            if not records:
                return []
            max_degree = records[0]["degree"] if records else 1
            return [
                {
                    "node_id": r["node_id"],
                    "node_type": r["node_type"],
                    "display_name": r["display_name"],
                    "source_system": r["source_system"],
                    "degree": r["degree"],
                    "centrality_score": round(r["degree"] / max(max_degree, 1), 3),
                }
                for r in records
            ]

    async def get_connected_components(
        self, max_iterations: int = 20
    ) -> list[dict[str, Any]]:
        # max_iterations unused — Cypher walks until done
        async with self._driver.session() as neo:
            result = await neo.run(
                """
                MATCH (n:Node)
                WITH collect(n) AS nodes
                CALL {
                    WITH nodes
                    UNWIND nodes AS n
                    MATCH (n)-[*0..]-(connected:Node)
                    WITH n, collect(DISTINCT connected.node_id) AS component
                    WITH component, min(component[0]) AS comp_id
                    RETURN comp_id, size(component) AS comp_size, component[..20] AS sample_nodes
                }
                RETURN comp_id, comp_size, sample_nodes
                ORDER BY comp_size DESC
                LIMIT 50
                """
            )
            records = [r async for r in result]
            return [
                {
                    "component_id": r["comp_id"],
                    "size": r["comp_size"],
                    "nodes": r["sample_nodes"],
                }
                for r in records
            ]

    # ─── Inference ───────────────────────────────────────────────────────

    async def detect_pii_propagation(
        self, max_depth: int = 10
    ) -> list[dict[str, Any]]:
        async with self._driver.session() as neo:
            result = await neo.run(
                f"""
                MATCH (source:Column)-[:TAGGED_WITH]->(tag:Tag)
                WHERE tag.display_name =~ '(?i).*(PII|PHI|SENSITIVE|HIPAA).*'
                MATCH (target:Column)-[:LINEAGE_FROM*1..{max_depth}]->(source)
                WHERE NOT EXISTS {{
                    MATCH (target)-[:TAGGED_WITH]->(t2:Tag)
                    WHERE t2.display_name =~ '(?i).*(PII|PHI|SENSITIVE).*'
                }}
                RETURN DISTINCT
                    target.node_id  AS target_node_id,
                    source.node_id  AS source_node_id,
                    target.fqn      AS target_fqn,
                    source.fqn      AS source_fqn,
                    'HIGH'          AS severity
                """
            )
            return [dict(r) async for r in result]

    async def detect_ownership_gaps(self) -> list[dict[str, Any]]:
        async with self._driver.session() as neo:
            result = await neo.run(
                """
                MATCH (t:Table)
                WHERE NOT EXISTS { MATCH (t)-[:OWNED_BY]->() }
                  AND NOT EXISTS { MATCH (t)-[:HAS_CONTRACT]->() }
                  AND NOT EXISTS {
                      MATCH (t)-[:TAGGED_WITH]->(tag:Tag)
                      WHERE tag.display_name =~ '(?i).*(OWNER|STEWARD|CONTRACT).*'
                  }
                RETURN t.node_id        AS node_id,
                       t.display_name   AS display_name,
                       t.fqn            AS fqn,
                       t.source_system  AS source_system,
                       'MEDIUM'         AS severity
                ORDER BY t.display_name
                """
            )
            return [dict(r) async for r in result]

    async def resolve_entities(
        self, threshold: float = 0.7
    ) -> list[dict[str, Any]]:
        """Entity resolution.

        Even the Neo4j backend defers to Snowflake's JAROWINKLER_SIMILARITY
        because it's deterministic, well-tested, and the data is already
        there. APOC's text similarity is functionally equivalent but adds
        a plugin dependency to the Neo4j image.
        """
        query = f"""
            SELECT
                n1.node_id        AS node_id_1,
                n2.node_id        AS node_id_2,
                n1.display_name   AS display_name_1,
                n2.display_name   AS display_name_2,
                n1.source_system  AS source_system_1,
                n2.source_system  AS source_system_2,
                JAROWINKLER_SIMILARITY(UPPER(n1.display_name), UPPER(n2.display_name)) / 100.0 AS confidence
            FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n1
            JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n2
                ON n1.layer = 'BUSINESS'
               AND n2.layer = 'BUSINESS'
               AND n1.source_system != n2.source_system
               AND n1.node_id < n2.node_id
            WHERE JAROWINKLER_SIMILARITY(UPPER(n1.display_name), UPPER(n2.display_name)) >= {int(threshold * 100)}
            ORDER BY confidence DESC
            LIMIT 100
        """
        rows = self._session.sql(query).collect()
        return [row.as_dict() for row in rows]

    async def compute_governance_scores(self) -> list[dict[str, Any]]:
        async with self._driver.session() as neo:
            result = await neo.run(
                """
                MATCH (t:Table)
                OPTIONAL MATCH (t)-[:TAGGED_WITH]->(tag)
                WITH t, count(DISTINCT tag) AS tag_count
                OPTIONAL MATCH (t)-[:HAS_CONTRACT]->()
                WITH t, tag_count, count(*) > 0 AS has_contract
                OPTIONAL MATCH (t)-[:OWNED_BY]->()
                WITH t, tag_count, has_contract, count(*) > 0 AS has_owner
                OPTIONAL MATCH (t)-[e:EDGE]->() WHERE e.edge_type IN ['MONITORED_BY', 'QUALITY_CHECK']
                WITH t, tag_count, has_contract, has_owner, count(*) > 0 AS has_quality
                WITH t,
                     toFloat(CASE WHEN tag_count >= 4 THEN 1.0 ELSE tag_count / 4.0 END) AS tag_score,
                     CASE WHEN has_contract THEN 1.0 ELSE 0.0 END AS contract_score,
                     CASE WHEN has_owner THEN 1.0 ELSE 0.0 END AS ownership_score,
                     CASE WHEN has_quality THEN 1.0 ELSE 0.0 END AS quality_score
                RETURN t.node_id      AS node_id,
                       t.display_name AS display_name,
                       round((tag_score * 0.3 + contract_score * 0.3 + ownership_score * 0.25 + quality_score * 0.15) * 1000) / 1000.0 AS overall_score,
                       round(tag_score * 1000) / 1000.0 AS tag_coverage,
                       contract_score AS contract_coverage,
                       ownership_score,
                       quality_score
                ORDER BY overall_score ASC
                """
            )
            return [dict(r) async for r in result]

    # ─── Stats ───────────────────────────────────────────────────────────

    async def get_graph_stats(self) -> dict[str, Any]:
        async with self._driver.session() as neo:
            result = await neo.run(
                """
                MATCH (n:Node)
                WITH count(n) AS node_count
                MATCH ()-[r]->()
                WITH node_count, count(r) AS edge_count
                RETURN node_count, edge_count
                """
            )
            record = await result.single()
            if record:
                return {
                    "node_count": record["node_count"],
                    "edge_count": record["edge_count"],
                    "backend": self.name,
                    "live": False,  # Neo4j is staged copy, not live
                }
            return {
                "node_count": 0,
                "edge_count": 0,
                "backend": self.name,
                "live": False,
            }
