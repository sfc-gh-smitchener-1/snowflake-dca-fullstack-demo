"""Node query endpoints."""

from typing import Any

from fastapi import APIRouter, Request

router = APIRouter()


@router.get("")
async def list_nodes(
    request: Request,
    layer: str | None = None,
    node_type: str | None = None,
    source_system: str | None = None,
    limit: int = 100,
    offset: int = 0,
) -> list[dict[str, Any]]:
    """List nodes with optional filters.

    Args:
        layer: Filter by layer (METADATA, BUSINESS).
        node_type: Filter by node type (TABLE, COLUMN, ROLE, CUSTOMER, etc.).
        source_system: Filter by source system (SNOWFLAKE, SAP, ORACLE, etc.).
        limit: Maximum results (default 100).
        offset: Pagination offset.
    """
    client = request.app.state.rai_client
    return client.get_nodes(
        layer=layer,
        node_type=node_type,
        source_system=source_system,
        limit=limit,
        offset=offset,
    )


@router.get("/{node_id}")
async def get_node(request: Request, node_id: str) -> dict[str, Any]:
    """Get a single node by ID."""
    client = request.app.state.rai_client
    results = client.session.sql(
        f"SELECT * FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_NODES WHERE node_id = '{node_id}'"
    ).collect()
    if not results:
        return {"error": "Node not found"}
    return results[0].as_dict()


@router.get("/{node_id}/neighbors")
async def get_node_neighbors(request: Request, node_id: str) -> list[dict[str, Any]]:
    """Get all nodes connected to the given node via edges in either direction."""
    client = request.app.state.rai_client
    return client.get_neighbors(node_id)
