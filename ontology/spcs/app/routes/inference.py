"""Graph inference endpoints — powered by Neo4j Cypher queries."""

from typing import Any

from fastapi import APIRouter, Request

router = APIRouter()


@router.get("/pii-propagation")
async def detect_pii_propagation(request: Request) -> list[dict[str, Any]]:
    """Detect columns receiving PII data from tagged sources but not themselves tagged."""
    engine = request.app.state.graph_engine
    return await engine.detect_pii_propagation()


@router.get("/ownership-gaps")
async def detect_ownership_gaps(request: Request) -> list[dict[str, Any]]:
    """Detect tables without ownership or contract assignments."""
    engine = request.app.state.graph_engine
    return await engine.detect_ownership_gaps()


@router.get("/entity-resolution")
async def resolve_entities(
    request: Request, threshold: float = 0.7
) -> list[dict[str, Any]]:
    """Cross-system entity resolution via name similarity.

    Args:
        threshold: Minimum similarity score (0-1) to include. Default 0.7.
    """
    engine = request.app.state.graph_engine
    return await engine.resolve_entities(threshold=threshold)


@router.get("/centrality")
async def get_centrality(request: Request, top_n: int = 50) -> list[dict[str, Any]]:
    """Get top-N nodes by degree centrality (hub detection).

    Args:
        top_n: Number of top nodes to return. Default 50.
    """
    engine = request.app.state.graph_engine
    return await engine.get_centrality(top_n=top_n)


@router.get("/components")
async def get_connected_components(request: Request) -> list[dict[str, Any]]:
    """Find connected components in the graph (cluster detection)."""
    engine = request.app.state.graph_engine
    return await engine.get_connected_components()


@router.get("/governance-scores/compute")
async def compute_governance_scores(request: Request) -> list[dict[str, Any]]:
    """Compute live governance scores from Neo4j graph structure."""
    engine = request.app.state.graph_engine
    return await engine.compute_governance_scores()


@router.post("/reload")
async def reload_graph(request: Request) -> dict[str, str]:
    """Reload the Neo4j graph from Snowflake tables.

    Call this after running graph population procedures to refresh
    the graph engine without restarting the service.
    """
    engine = request.app.state.graph_engine
    await engine.reload_graph()
    stats = await engine.get_graph_stats()
    return {
        "status": "reloaded",
        "nodes": str(stats.get("node_count", 0)),
        "edges": str(stats.get("edge_count", 0)),
    }
