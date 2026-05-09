"""RAI Python SDK wrapper for the Ontology Knowledge Graph.

Provides a singleton client that manages the RAI engine connection
and exposes methods for querying the graph via Rel.
"""

import json
import os
from pathlib import Path
from typing import Any

from snowflake.snowpark import Session


class RAIClient:
    """Singleton wrapper around the RelationalAI Python SDK.

    Uses token-based authentication from the SPCS environment
    (/snowflake/session/token).
    """

    _instance: "RAIClient | None" = None

    def __new__(cls) -> "RAIClient":
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance

    def __init__(self):
        self._session: Session | None = None
        self._engine_name = os.getenv("RAI_ENGINE", "ONTOLOGY_ENGINE")

    async def initialize(self) -> None:
        """Initialize the Snowpark session using SPCS token auth."""
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
            # Local development fallback
            self._session = Session.builder.configs({
                "connection_name": "default",
                "database": "DCA_DEMO",
                "schema": "GOVERNANCE",
            }).create()

    @property
    def session(self) -> Session:
        """Get the active Snowpark session."""
        if self._session is None:
            raise RuntimeError("RAI client not initialized. Call initialize() first.")
        return self._session

    def get_engine(self) -> str:
        """Return the RAI engine name."""
        return self._engine_name

    def query_rel(self, rel_source: str) -> list[dict[str, Any]]:
        """Execute a Rel query on the RAI engine and return results.

        Args:
            rel_source: Rel source code to execute.

        Returns:
            List of result dictionaries.
        """
        result = self.session.sql(
            f"CALL RAI.API.EXEC_REL('{self._engine_name}', $${rel_source}$$)"
        ).collect()
        if result:
            return [json.loads(row[0]) for row in result]
        return []

    def get_nodes(
        self,
        layer: str | None = None,
        node_type: str | None = None,
        source_system: str | None = None,
        limit: int = 100,
        offset: int = 0,
    ) -> list[dict[str, Any]]:
        """Query nodes from the graph tables with optional filters.

        Args:
            layer: Filter by layer (METADATA, BUSINESS).
            node_type: Filter by node type.
            source_system: Filter by source system.
            limit: Max results to return.
            offset: Pagination offset.

        Returns:
            List of node dictionaries.
        """
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
        """Get all nodes connected to the given node via edges in either direction.

        Args:
            node_id: The node to find neighbors for.

        Returns:
            List of neighboring node dictionaries with edge info.
        """
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

    def get_path(self, from_id: str, to_id: str) -> list[dict[str, Any]]:
        """Find the shortest path between two nodes using RAI.

        Args:
            from_id: Source node ID.
            to_id: Target node ID.

        Returns:
            Ordered list of nodes along the shortest path.
        """
        rel_query = f"""
            def output = shortest_path_length("{from_id}", "{to_id}", d)
        """
        return self.query_rel(rel_query)

    def get_governance_scores(
        self, min_score: float | None = None
    ) -> list[dict[str, Any]]:
        """Return governance scores, optionally filtered by minimum threshold.

        Args:
            min_score: Minimum overall_score to include.

        Returns:
            List of score dictionaries.
        """
        query = "SELECT * FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_GOVERNANCE_SCORES"
        if min_score is not None:
            query += f" WHERE overall_score >= {min_score}"
        query += " ORDER BY overall_score ASC"

        rows = self.session.sql(query).collect()
        return [row.as_dict() for row in rows]
