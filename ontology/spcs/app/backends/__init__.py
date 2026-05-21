"""Graph backend implementations.

Two interchangeable engines implement the same protocol:
  - SnowflakeBackend   — Recursive CTEs and window functions on Snowflake tables
  - Neo4jBackend       — Cypher queries against a sidecar property graph

The Neo4j backend is imported lazily — if the `neo4j` driver isn't installed
(minimal image, GRAPH_BACKEND=snowflake), the import will simply not happen
and the rest of the service keeps working.

See docs/GRAPH_BACKENDS.md for the full compare/contrast and decision matrix.
"""

from app.backends.base import GraphBackend
from app.backends.snowflake_backend import SnowflakeBackend

try:
    from app.backends.neo4j_backend import Neo4jBackend
    _NEO4J_AVAILABLE = True
except ImportError:  # pragma: no cover — minimal image without neo4j driver
    Neo4jBackend = None  # type: ignore[assignment,misc]
    _NEO4J_AVAILABLE = False

__all__ = ["GraphBackend", "Neo4jBackend", "SnowflakeBackend", "_NEO4J_AVAILABLE"]
