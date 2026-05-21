"""Graph inference endpoints.

Every route accepts an optional ``?backend=`` query param to choose which
graph backend serves the request:

    ?backend=snowflake   recursive-CTE backend (default)
    ?backend=neo4j       Cypher / property-graph backend (if loaded)
    ?backend=both        both backends; response is keyed by backend name

The /inference/compare endpoint runs the same query through every loaded
backend and returns timings + result counts for side-by-side comparison.

See docs/GRAPH_BACKENDS.md for the compare/contrast and decision matrix.
"""

from typing import Any

from fastapi import APIRouter, HTTPException, Query, Request

router = APIRouter()


def _engine(request: Request):
    return request.app.state.graph_engine


@router.get("/backends")
async def list_backends(request: Request) -> dict[str, Any]:
    """List currently loaded backends and the default."""
    engine = _engine(request)
    return {
        "default": engine._default_backend,
        "loaded": engine.list_backends(),
    }


@router.get("/pii-propagation")
async def detect_pii_propagation(
    request: Request,
    backend: str | None = Query(None, description="snowflake | neo4j | both"),
) -> Any:
    """Detect columns receiving PII data from tagged sources but not themselves tagged."""
    try:
        return await _engine(request).detect_pii_propagation(backend=backend)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@router.get("/ownership-gaps")
async def detect_ownership_gaps(
    request: Request,
    backend: str | None = Query(None, description="snowflake | neo4j | both"),
) -> Any:
    """Detect tables without ownership or contract assignments."""
    try:
        return await _engine(request).detect_ownership_gaps(backend=backend)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@router.get("/entity-resolution")
async def resolve_entities(
    request: Request,
    threshold: float = 0.7,
    backend: str | None = Query(None, description="snowflake | neo4j | both"),
) -> Any:
    """Cross-system entity resolution via name similarity.

    Args:
        threshold: Minimum similarity score (0-1) to include. Default 0.7.
        backend: snowflake (default) | neo4j | both
    """
    try:
        return await _engine(request).resolve_entities(
            threshold=threshold, backend=backend
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@router.get("/centrality")
async def get_centrality(
    request: Request,
    top_n: int = 50,
    backend: str | None = Query(None, description="snowflake | neo4j | both"),
) -> Any:
    """Get top-N nodes by degree centrality (hub detection)."""
    try:
        return await _engine(request).get_centrality(
            top_n=top_n, backend=backend
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@router.get("/components")
async def get_connected_components(
    request: Request,
    backend: str | None = Query(None, description="snowflake | neo4j | both"),
) -> Any:
    """Find connected components in the graph (cluster detection)."""
    try:
        return await _engine(request).get_connected_components(backend=backend)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@router.get("/governance-scores/compute")
async def compute_governance_scores(
    request: Request,
    backend: str | None = Query(None, description="snowflake | neo4j | both"),
) -> Any:
    """Compute live governance scores from current graph structure."""
    try:
        return await _engine(request).compute_governance_scores(backend=backend)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@router.post("/reload")
async def reload_graph(
    request: Request,
    backend: str | None = Query(None, description="snowflake | neo4j | both"),
) -> dict[str, str]:
    """Reload graph backend(s) from Snowflake tables.

    For the Snowflake-native backend this is a no-op (always live).
    For the Neo4j backend this clears and re-syncs the in-memory graph.
    """
    engine = _engine(request)
    await engine.reload_graph(backend=backend)
    stats = await engine.get_graph_stats(backend=backend)
    return {
        "status": "reloaded",
        "stats": stats,
    }


@router.get("/compare")
async def compare_backends(
    request: Request,
    endpoint: str = Query(
        ...,
        description=(
            "Which inference method to compare across backends. "
            "One of: pii-propagation, ownership-gaps, entity-resolution, "
            "centrality, components, governance-scores"
        ),
    ),
    threshold: float = 0.7,
    top_n: int = 50,
) -> dict[str, Any]:
    """Run the same query through every loaded backend; return timings + results.

    Demonstrates the Neo4j vs Snowflake-native trade-off live. Useful in the
    middle of a demo when the audience asks "okay, which one is actually faster?"
    """
    method_map = {
        "pii-propagation": ("detect_pii_propagation", {}),
        "ownership-gaps": ("detect_ownership_gaps", {}),
        "entity-resolution": ("resolve_entities", {"threshold": threshold}),
        "centrality": ("get_centrality", {"top_n": top_n}),
        "components": ("get_connected_components", {}),
        "governance-scores": ("compute_governance_scores", {}),
    }
    if endpoint not in method_map:
        raise HTTPException(
            status_code=400,
            detail=f"Unknown endpoint {endpoint!r}. Choose one of: {list(method_map)}",
        )

    method, kwargs = method_map[endpoint]
    return await _engine(request).compare(method, **kwargs)
