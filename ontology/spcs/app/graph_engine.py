"""Graph engine facade — dispatches to one or both backends.

Two interchangeable engines are available:

  - SnowflakeBackend  (default) — recursive CTEs + window functions, always live,
                       inherits Snowflake governance / replication / sharing.
  - Neo4jBackend                — Cypher against a sidecar property graph, faster
                       at deep traversal and GDS-class algorithms.

Selection is controlled by the ``GRAPH_BACKEND`` environment variable:

    GRAPH_BACKEND=snowflake   # default — only Snowflake backend initialized
    GRAPH_BACKEND=neo4j       # only Neo4j backend initialized
    GRAPH_BACKEND=both        # both backends initialized; choose per-request

When both are running, every route accepts ``?backend=neo4j`` or
``?backend=snowflake`` to override the default per request. There is also a
``/inference/compare`` endpoint that runs the same query through both and
returns timings + diff.

See docs/GRAPH_BACKENDS.md for the full compare/contrast and decision matrix.
"""

from __future__ import annotations

import logging
import os
import time
from pathlib import Path
from typing import Any

from snowflake.snowpark import Session

from app.backends import (
    _NEO4J_AVAILABLE,
    GraphBackend,
    Neo4jBackend,
    SnowflakeBackend,
)

logger = logging.getLogger(__name__)

# Backend names — match what the ?backend= query param accepts.
BACKEND_SNOWFLAKE = "snowflake"
BACKEND_NEO4J = "neo4j"
BACKEND_BOTH = "both"


class GraphEngine:
    """Facade over one or both graph backends.

    Singleton so FastAPI's app.state holds a single instance across requests.
    """

    _instance: "GraphEngine | None" = None

    def __new__(cls) -> "GraphEngine":
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance

    def __init__(self):
        if hasattr(self, "_initialized"):
            return  # singleton guard
        self._initialized = False
        self._session: Session | None = None
        self._backends: dict[str, GraphBackend] = {}
        self._default_backend = (
            os.getenv("GRAPH_BACKEND", BACKEND_SNOWFLAKE).strip().lower()
        )

    # ─── Lifecycle ───────────────────────────────────────────────────────

    async def initialize(self) -> None:
        """Initialize Snowpark session and the configured backend(s)."""
        self._session = self._build_session()

        wanted = self._wanted_backends()
        for name in wanted:
            try:
                if name == BACKEND_SNOWFLAKE:
                    backend: GraphBackend = SnowflakeBackend(self._session)
                elif name == BACKEND_NEO4J:
                    if not _NEO4J_AVAILABLE or Neo4jBackend is None:
                        logger.warning(
                            "Neo4j backend requested but driver not installed — skipping. "
                            "Install neo4j>=5.14.0 or set GRAPH_BACKEND=snowflake."
                        )
                        continue
                    backend = Neo4jBackend(self._session)
                else:
                    logger.warning("Unknown backend %r — skipping", name)
                    continue
                await backend.initialize()
                self._backends[name] = backend
                logger.info("Graph backend initialized: %s", name)
            except Exception as exc:
                logger.warning(
                    "Failed to initialize backend %r: %s — continuing without it",
                    name,
                    exc,
                )

        if not self._backends:
            raise RuntimeError(
                "No graph backend could be initialized. "
                f"GRAPH_BACKEND={self._default_backend!r}; check Neo4j sidecar / Snowflake creds."
            )

        self._initialized = True

    def _build_session(self) -> Session:
        token_path = Path("/snowflake/session/token")
        if token_path.exists():
            token = token_path.read_text().strip()
            return Session.builder.configs(
                {
                    "account": os.getenv("SNOWFLAKE_ACCOUNT", ""),
                    "host": os.getenv("SNOWFLAKE_HOST", ""),
                    "authenticator": "oauth",
                    "token": token,
                    "database": "DCA_DEMO",
                    "schema": "GOVERNANCE",
                    "warehouse": "COMPUTE_WH",
                }
            ).create()
        return Session.builder.configs(
            {
                "connection_name": os.getenv("SNOWFLAKE_CONNECTION", "default"),
                "database": "DCA_DEMO",
                "schema": "GOVERNANCE",
            }
        ).create()

    def _wanted_backends(self) -> list[str]:
        mode = self._default_backend
        if mode == BACKEND_BOTH:
            return [BACKEND_SNOWFLAKE, BACKEND_NEO4J]
        if mode in (BACKEND_SNOWFLAKE, BACKEND_NEO4J):
            return [mode]
        logger.warning(
            "Unknown GRAPH_BACKEND=%r; falling back to snowflake", mode
        )
        return [BACKEND_SNOWFLAKE]

    async def reload_graph(self, backend: str | None = None) -> None:
        for b in self._resolve(backend):
            await b.reload_graph()

    # ─── Backend resolution ─────────────────────────────────────────────

    def _resolve(self, backend: str | None) -> list[GraphBackend]:
        """Resolve which backend(s) to use for a request.

        - If a specific name is given, return that one (error if unavailable).
        - If "both" is given, return all available.
        - If None, return the default backend (preferring Snowflake when
          both are loaded, since it has no warm-up cost).
        """
        if backend is None:
            preferred = (
                BACKEND_SNOWFLAKE
                if BACKEND_SNOWFLAKE in self._backends
                else next(iter(self._backends))
            )
            return [self._backends[preferred]]
        backend = backend.lower()
        if backend == BACKEND_BOTH:
            return list(self._backends.values())
        if backend not in self._backends:
            raise ValueError(
                f"Backend {backend!r} is not available. "
                f"Loaded backends: {list(self._backends)}"
            )
        return [self._backends[backend]]

    def list_backends(self) -> list[str]:
        return list(self._backends.keys())

    @property
    def session(self) -> Session:
        if self._session is None:
            raise RuntimeError("Graph engine not initialized.")
        return self._session

    # ─── Dispatch helpers ────────────────────────────────────────────────
    #
    # Each public method below routes to one or more backends based on the
    # ``backend`` argument. When only one backend is targeted, the response
    # is unwrapped (list[dict] / dict). When multiple are targeted, the
    # response is keyed by backend name.

    async def _dispatch(
        self, method: str, backend: str | None, **kwargs: Any
    ) -> Any:
        targets = self._resolve(backend)
        if len(targets) == 1:
            return await getattr(targets[0], method)(**kwargs)
        out: dict[str, Any] = {}
        for b in targets:
            out[b.name] = await getattr(b, method)(**kwargs)
        return out

    async def compare(
        self, method: str, **kwargs: Any
    ) -> dict[str, Any]:
        """Run the same method on every loaded backend and report timings.

        Used by the ``/inference/compare`` endpoint to demonstrate the
        Neo4j vs Snowflake trade-off side-by-side.
        """
        out: dict[str, Any] = {"method": method, "kwargs": kwargs, "results": {}}
        for b in self._backends.values():
            t0 = time.perf_counter()
            try:
                rows = await getattr(b, method)(**kwargs)
                elapsed_ms = round((time.perf_counter() - t0) * 1000, 1)
                out["results"][b.name] = {
                    "ok": True,
                    "elapsed_ms": elapsed_ms,
                    "row_count": len(rows) if isinstance(rows, list) else 1,
                    "rows": rows,
                }
            except Exception as exc:
                elapsed_ms = round((time.perf_counter() - t0) * 1000, 1)
                out["results"][b.name] = {
                    "ok": False,
                    "elapsed_ms": elapsed_ms,
                    "error": str(exc),
                }
        return out

    # ─── Public API — same shape as before, plus optional backend param ──

    async def get_shortest_path(
        self, from_id: str, to_id: str, backend: str | None = None
    ) -> Any:
        return await self._dispatch(
            "get_shortest_path", backend, from_id=from_id, to_id=to_id
        )

    async def get_centrality(
        self, top_n: int = 50, backend: str | None = None
    ) -> Any:
        return await self._dispatch(
            "get_centrality", backend, top_n=top_n
        )

    async def get_connected_components(
        self, backend: str | None = None
    ) -> Any:
        return await self._dispatch(
            "get_connected_components", backend
        )

    async def detect_pii_propagation(
        self, backend: str | None = None
    ) -> Any:
        return await self._dispatch("detect_pii_propagation", backend)

    async def detect_ownership_gaps(
        self, backend: str | None = None
    ) -> Any:
        return await self._dispatch("detect_ownership_gaps", backend)

    async def resolve_entities(
        self, threshold: float = 0.7, backend: str | None = None
    ) -> Any:
        return await self._dispatch(
            "resolve_entities", backend, threshold=threshold
        )

    async def compute_governance_scores(
        self, backend: str | None = None
    ) -> Any:
        return await self._dispatch("compute_governance_scores", backend)

    async def get_graph_stats(
        self, backend: str | None = None
    ) -> Any:
        return await self._dispatch("get_graph_stats", backend)

    # ─── Direct Snowflake queries (used by node/edge/scores routes) ──────
    #
    # These are not dispatched through the backend protocol because they
    # read raw tables — equivalent behavior regardless of which backend
    # is active.

    def get_nodes(
        self,
        layer: str | None = None,
        node_type: str | None = None,
        source_system: str | None = None,
        limit: int = 100,
        offset: int = 0,
    ) -> list[dict[str, Any]]:
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

    def get_governance_scores(
        self, min_score: float | None = None
    ) -> list[dict[str, Any]]:
        query = "SELECT * FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_GOVERNANCE_SCORES"
        if min_score is not None:
            query += f" WHERE overall_score >= {min_score}"
        query += " ORDER BY overall_score ASC"
        rows = self.session.sql(query).collect()
        return [row.as_dict() for row in rows]
