"""Edge query endpoints."""

from typing import Any

from fastapi import APIRouter, Request

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
    """List edges with optional filters.

    Args:
        layer: Filter by layer (METADATA, BUSINESS, CROSS).
        edge_type: Filter by edge type (OWNS, TAGGED_WITH, LINEAGE_FROM, etc.).
        source_node_id: Filter by source node.
        target_node_id: Filter by target node.
        limit: Maximum results (default 100).
        offset: Pagination offset.
    """
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
    request: Request, from_id: str, to_id: str
) -> list[dict[str, Any]]:
    """Find the shortest path between two nodes using Neo4j graph traversal."""
    engine = request.app.state.graph_engine
    return await engine.get_shortest_path(from_id, to_id)
