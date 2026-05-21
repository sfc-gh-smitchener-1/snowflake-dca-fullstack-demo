"""Abstract backend protocol shared by Neo4j and Snowflake-native graph engines.

Both implementations conform to this surface so the facade in `graph_engine.py`
can dispatch to either (or both, side-by-side) without the routes caring
which one served the response.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any


class GraphBackend(ABC):
    """Protocol both graph engines implement.

    Implementations:
      - Neo4jBackend     — Cypher against a sidecar property graph
      - SnowflakeBackend — Recursive CTEs over ONTOLOGY_GRAPH_NODES/EDGES

    All methods are async to match FastAPI's request lifecycle. The
    Snowflake-native methods are typically synchronous SQL underneath
    but are exposed via async functions for protocol uniformity.
    """

    name: str  # "neo4j" | "snowflake"

    # ─── Lifecycle ───────────────────────────────────────────────────────

    @abstractmethod
    async def initialize(self) -> None:
        """Connect, warm caches, prepare statements."""

    @abstractmethod
    async def reload_graph(self) -> None:
        """Re-sync from the source-of-truth tables in Snowflake.

        For Snowflake-native this is a no-op (always live).
        For Neo4j this clears and re-loads the in-memory graph.
        """

    @abstractmethod
    async def is_healthy(self) -> bool:
        """Return True if the backend can answer queries right now."""

    # ─── Graph Algorithms ────────────────────────────────────────────────

    @abstractmethod
    async def get_shortest_path(
        self, from_id: str, to_id: str, max_depth: int = 15
    ) -> list[dict[str, Any]]:
        """Return ordered nodes on the shortest path between two node_ids.

        Returns an empty list if no path exists within max_depth hops.
        """

    @abstractmethod
    async def get_centrality(self, top_n: int = 50) -> list[dict[str, Any]]:
        """Return the top-N nodes by degree centrality."""

    @abstractmethod
    async def get_connected_components(
        self, max_iterations: int = 20
    ) -> list[dict[str, Any]]:
        """Return weakly connected components, largest first."""

    # ─── Inference ───────────────────────────────────────────────────────

    @abstractmethod
    async def detect_pii_propagation(
        self, max_depth: int = 10
    ) -> list[dict[str, Any]]:
        """Detect untagged columns downstream of PII/PHI-tagged sources."""

    @abstractmethod
    async def detect_ownership_gaps(self) -> list[dict[str, Any]]:
        """Detect tables without ownership / contract / steward assignment."""

    @abstractmethod
    async def resolve_entities(
        self, threshold: float = 0.7
    ) -> list[dict[str, Any]]:
        """Cross-system entity resolution via string similarity."""

    @abstractmethod
    async def compute_governance_scores(self) -> list[dict[str, Any]]:
        """Compute composite governance scores from current graph state."""

    # ─── Stats ───────────────────────────────────────────────────────────

    @abstractmethod
    async def get_graph_stats(self) -> dict[str, Any]:
        """Return basic graph stats (node count, edge count, last refresh)."""
