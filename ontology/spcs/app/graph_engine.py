"""Neo4j-backed graph engine for the Ontology Knowledge Graph.

Connects to a Neo4j sidecar container running on the same SPCS service.
Loads nodes/edges from Snowflake into Neo4j, and provides graph inference
via Cypher queries (shortest path, centrality, entity resolution, etc.).
"""

import os
from pathlib import Path
from typing import Any

from neo4j import AsyncGraphDatabase
from snowflake.snowpark import Session


class GraphEngine:
    """Graph engine backed by Neo4j sidecar on SPCS.

    Reads nodes/edges from Snowflake, syncs them to Neo4j, and provides
    graph traversal and inference via Cypher queries.
    """

    _instance: "GraphEngine | None" = None

    def __new__(cls) -> "GraphEngine":
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance

    def __init__(self):
        self._session: Session | None = None
        self._neo4j_driver = None
        self._neo4j_uri = os.getenv("NEO4J_URI", "bolt://localhost:7687")
        self._neo4j_user = os.getenv("NEO4J_USER", "neo4j")
        self._neo4j_password = os.getenv("NEO4J_PASSWORD", "ontology-graph")

    async def initialize(self) -> None:
        """Initialize Snowpark session and Neo4j connection."""
        # Snowpark session for reading source data
        token_path = Path("/snowflake/session/token")
        if token_path.exists():
            token = token_path.read_text().strip()
            self._session = Session.builder.configs({
                "account": os.getenv("SNOWFLAKE_ACCOUNT", ""),
                "host": os.getenv("SNOWFLAKE_HOST", ""),
                "authenticator": "oauth",
                "token": token,
                "database": "DCA_DEMO",
                "schema": "GOVERNANCE",
                "warehouse": "COMPUTE_WH",
            }).create()
        else:
            self._session = Session.builder.configs({
                "connection_name": os.getenv("SNOWFLAKE_CONNECTION", "default"),
                "database": "DCA_DEMO",
                "schema": "GOVERNANCE",
            }).create()

        # Neo4j async driver
        self._neo4j_driver = AsyncGraphDatabase.driver(
            self._neo4j_uri,
            auth=(self._neo4j_user, self._neo4j_password),
        )

        # Initial sync: load graph from Snowflake into Neo4j
        await self._sync_graph_to_neo4j()

    async def _sync_graph_to_neo4j(self) -> None:
        """Load nodes and edges from Snowflake tables into Neo4j."""
        async with self._neo4j_driver.session() as neo_session:
            # Clear existing graph
            await neo_session.run("MATCH (n) DETACH DELETE n")

            # Create indexes for performance
            await neo_session.run(
                "CREATE INDEX IF NOT EXISTS FOR (n:Node) ON (n.node_id)"
            )
            await neo_session.run(
                "CREATE INDEX IF NOT EXISTS FOR (n:Node) ON (n.node_type)"
            )
            await neo_session.run(
                "CREATE INDEX IF NOT EXISTS FOR (n:Node) ON (n.source_system)"
            )

            # Load nodes from Snowflake
            rows = self.session.sql(
                "SELECT node_id, node_type, layer, source_system, fqn, display_name "
                "FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES"
            ).collect()

            # Batch insert nodes (500 at a time)
            batch_size = 500
            for i in range(0, len(rows), batch_size):
                batch = rows[i:i + batch_size]
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
                await neo_session.run(
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

            # Also add type-specific labels
            await neo_session.run(
                "MATCH (n:Node) WHERE n.node_type = 'TABLE' SET n:Table"
            )
            await neo_session.run(
                "MATCH (n:Node) WHERE n.node_type = 'COLUMN' SET n:Column"
            )
            await neo_session.run(
                "MATCH (n:Node) WHERE n.node_type = 'ROLE' SET n:Role"
            )
            await neo_session.run(
                "MATCH (n:Node) WHERE n.node_type = 'TAG' SET n:Tag"
            )

            # Load edges from Snowflake
            edge_rows = self.session.sql(
                "SELECT edge_id, source_node_id, target_node_id, edge_type, layer, weight "
                "FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES"
            ).collect()

            for i in range(0, len(edge_rows), batch_size):
                batch = edge_rows[i:i + batch_size]
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
                await neo_session.run(
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

            # Create typed relationships for common edge types
            await neo_session.run("""
                MATCH (src)-[e:EDGE]->(tgt) WHERE e.edge_type = 'LINEAGE_FROM'
                CREATE (src)-[:LINEAGE_FROM {weight: e.weight}]->(tgt)
            """)
            await neo_session.run("""
                MATCH (src)-[e:EDGE]->(tgt) WHERE e.edge_type = 'TAGGED_WITH'
                CREATE (src)-[:TAGGED_WITH {weight: e.weight}]->(tgt)
            """)
            await neo_session.run("""
                MATCH (src)-[e:EDGE]->(tgt) WHERE e.edge_type = 'OWNED_BY'
                CREATE (src)-[:OWNED_BY {weight: e.weight}]->(tgt)
            """)
            await neo_session.run("""
                MATCH (src)-[e:EDGE]->(tgt) WHERE e.edge_type = 'HAS_CONTRACT'
                CREATE (src)-[:HAS_CONTRACT {weight: e.weight}]->(tgt)
            """)

    async def reload_graph(self) -> None:
        """Reload the graph from Snowflake into Neo4j."""
        await self._sync_graph_to_neo4j()

    @property
    def session(self) -> Session:
        """Get the active Snowpark session."""
        if self._session is None:
            raise RuntimeError("Graph engine not initialized.")
        return self._session

    @property
    def neo4j(self):
        """Get the Neo4j async driver."""
        if self._neo4j_driver is None:
            raise RuntimeError("Neo4j not initialized.")
        return self._neo4j_driver

    # ─── Node/Edge Queries (Snowflake direct) ────────────────────────────

    def get_nodes(
        self,
        layer: str | None = None,
        node_type: str | None = None,
        source_system: str | None = None,
        limit: int = 100,
        offset: int = 0,
    ) -> list[dict[str, Any]]:
        """Query nodes with optional filters."""
        query = "SELECT * FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES WHERE 1=1"
        if layer:
            query += f" AND layer = '{layer}'"
        if node_type:
            query += f" AND node_type = '{node_type}'"
        if source_system:
            query += f" AND source_system = '{source_system}'"
        query += f" ORDER BY created_at DESC LIMIT {limit} OFFSET {offset}"
        rows = self.session.sql(query).collect()
        return [row.as_dict() for row in rows]

    def get_neighbors(self, node_id: str) -> list[dict[str, Any]]:
        """Get all nodes connected to the given node."""
        query = f"""
            SELECT n.*, e.edge_type, e.layer AS edge_layer, e.weight,
                   CASE WHEN e.source_node_id = '{node_id}' THEN 'outgoing' ELSE 'incoming' END AS direction
            FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES n
            JOIN DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES e
                ON (e.target_node_id = n.node_id AND e.source_node_id = '{node_id}')
                OR (e.source_node_id = n.node_id AND e.target_node_id = '{node_id}')
        """
        rows = self.session.sql(query).collect()
        return [row.as_dict() for row in rows]

    # ─── Graph Algorithms (Neo4j Cypher) ─────────────────────────────────

    async def get_shortest_path(self, from_id: str, to_id: str) -> list[dict[str, Any]]:
        """Find shortest path between two nodes using Neo4j."""
        async with self.neo4j.session() as neo_session:
            result = await neo_session.run(
                """
                MATCH p = shortestPath(
                    (src:Node {node_id: $from_id})-[*..15]-(tgt:Node {node_id: $to_id})
                )
                RETURN [n IN nodes(p) | {
                    node_id: n.node_id,
                    node_type: n.node_type,
                    layer: n.layer,
                    source_system: n.source_system,
                    display_name: n.display_name
                }] AS path
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
        """Compute degree centrality via Neo4j."""
        async with self.neo4j.session() as neo_session:
            result = await neo_session.run(
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

    async def get_connected_components(self) -> list[dict[str, Any]]:
        """Find weakly connected components via Neo4j."""
        async with self.neo4j.session() as neo_session:
            # Use GDS if available, otherwise manual BFS via Cypher
            result = await neo_session.run(
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

    # ─── Inference Methods (Neo4j Cypher) ────────────────────────────────

    async def detect_pii_propagation(self) -> list[dict[str, Any]]:
        """Detect untagged columns downstream of PII-tagged sources."""
        async with self.neo4j.session() as neo_session:
            result = await neo_session.run(
                """
                MATCH (source:Column)-[:TAGGED_WITH]->(tag:Tag)
                WHERE tag.display_name =~ '(?i).*(PII|PHI|SENSITIVE|HIPAA).*'
                MATCH (target:Column)-[:LINEAGE_FROM]->(source)
                WHERE NOT EXISTS {
                    MATCH (target)-[:TAGGED_WITH]->(t2:Tag)
                    WHERE t2.display_name =~ '(?i).*(PII|PHI|SENSITIVE).*'
                }
                RETURN target.node_id AS target_node_id,
                       source.node_id AS source_node_id,
                       target.fqn AS target_fqn,
                       source.fqn AS source_fqn,
                       'HIGH' AS severity
                """
            )
            return [dict(r) async for r in result]

    async def detect_ownership_gaps(self) -> list[dict[str, Any]]:
        """Detect tables without ownership assignments."""
        async with self.neo4j.session() as neo_session:
            result = await neo_session.run(
                """
                MATCH (t:Table)
                WHERE NOT EXISTS { MATCH (t)-[:OWNED_BY]->() }
                  AND NOT EXISTS { MATCH (t)-[:HAS_CONTRACT]->() }
                  AND NOT EXISTS {
                      MATCH (t)-[:TAGGED_WITH]->(tag:Tag)
                      WHERE tag.display_name =~ '(?i).*(OWNER|STEWARD|CONTRACT).*'
                  }
                RETURN t.node_id AS node_id,
                       t.display_name AS display_name,
                       t.fqn AS fqn,
                       t.source_system AS source_system,
                       'MEDIUM' AS severity
                ORDER BY t.display_name
                """
            )
            return [dict(r) async for r in result]

    async def resolve_entities(self, threshold: float = 0.7) -> list[dict[str, Any]]:
        """Cross-system entity resolution using string similarity in Cypher."""
        # Neo4j's apoc.text.jaroWinklerDistance or built-in functions
        # Fall back to Snowflake JAROWINKLER_SIMILARITY for reliable results
        query = f"""
            SELECT
                n1.node_id AS node_id_1,
                n2.node_id AS node_id_2,
                n1.display_name AS display_name_1,
                n2.display_name AS display_name_2,
                n1.source_system AS source_system_1,
                n2.source_system AS source_system_2,
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
        rows = self.session.sql(query).collect()
        return [row.as_dict() for row in rows]

    async def compute_governance_scores(self) -> list[dict[str, Any]]:
        """Compute governance scores using Neo4j graph structure."""
        async with self.neo4j.session() as neo_session:
            result = await neo_session.run(
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
                RETURN t.node_id AS node_id,
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

    def get_governance_scores(
        self, min_score: float | None = None
    ) -> list[dict[str, Any]]:
        """Return governance scores from pre-computed table."""
        query = "SELECT * FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_GOVERNANCE_SCORES"
        if min_score is not None:
            query += f" WHERE overall_score >= {min_score}"
        query += " ORDER BY overall_score ASC"
        rows = self.session.sql(query).collect()
        return [row.as_dict() for row in rows]

    async def get_graph_stats(self) -> dict[str, Any]:
        """Return graph statistics from Neo4j."""
        async with self.neo4j.session() as neo_session:
            result = await neo_session.run(
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
                }
            return {"node_count": 0, "edge_count": 0}
