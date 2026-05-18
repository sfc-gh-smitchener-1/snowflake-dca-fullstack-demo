"""Health check endpoint."""

from fastapi import APIRouter, Request

router = APIRouter()


@router.get("/health")
async def health_check(request: Request) -> dict:
    """Return service health status."""
    engine = request.app.state.graph_engine
    try:
        stats = await engine.get_graph_stats()
        neo4j_status = "connected"
    except Exception:
        stats = {"node_count": 0, "edge_count": 0}
        neo4j_status = "disconnected"
    return {
        "status": "healthy",
        "graph_db": "neo4j",
        "neo4j_status": neo4j_status,
        "version": "2.0.0",
        "graph_nodes": stats.get("node_count", 0),
        "graph_edges": stats.get("edge_count", 0),
    }
