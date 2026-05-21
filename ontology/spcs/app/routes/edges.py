"""Edge query endpoints."""

from typing import Any

from fastapi import APIRouter, HTTPException, Query, Request

router = APIRouter()


@router.get("")
async def list_edges(
    request: Request,
    layer: str | None = None,
    edge_type: str | None = None,
    source_node_id: str | None = None,
    target_node_id: str | None = None,
    limit: int = 100,
    offset: int = 0,
) -> list[dict[str, Any]]:
    """List edges with optional filters."""
    engine = request.app.state.graph_engine
    query = "SELECT * FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_EDGES WHERE 1=1"
    if layer:
        query += f" AND layer = '{layer}'"
    if edge_type:
        query += f" AND edge_type = '{edge_type}'"
    if source_node_id:
        query += f" AND source_node_id = '{source_node_id}'"
    if target_node_id:
        query += f" AND target_node_id = '{target_node_id}'"
    query += f" ORDER BY created_at DESC LIMIT {limit} OFFSET {offset}"

    rows = engine.session.sql(query).collect()
    return [row.as_dict() for row in rows]


@router.get("/path/{from_id}/{to_id}")
async def get_shortest_path(
    request: Request,
    from_id: str,
    to_id: str,
    backend: str | None = Query(
        None, description="snowflake (default) | neo4j | both"
    ),
) -> Any:
    """Find the shortest path between two nodes.

    Backend selection:
      - snowflake (default): recursive CTE — fine for paths up to ~10 hops
      - neo4j: Cypher shortestPath — sub-second for 15+ hops
      - both: returns both results, keyed by backend name
    """
    try:
        return await request.app.state.graph_engine.get_shortest_path(
            from_id=from_id, to_id=to_id, backend=backend
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
