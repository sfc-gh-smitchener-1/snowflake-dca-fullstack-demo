"""Health check endpoint — reports status of every loaded graph backend."""

from typing import Any

from fastapi import APIRouter, Request

router = APIRouter()


@router.get("/health")
async def health_check(request: Request) -> dict[str, Any]:
    """Return service health plus status of every loaded backend."""
    engine = request.app.state.graph_engine

    backends_status: dict[str, dict[str, Any]] = {}
    overall_ok = bool(engine.list_backends())

    for name in engine.list_backends():
        try:
            stats = await engine.get_graph_stats(backend=name)
            backends_status[name] = {
                "status": "connected",
                "node_count": stats.get("node_count", 0),
                "edge_count": stats.get("edge_count", 0),
                "live": stats.get("live", False),
            }
        except Exception as exc:
            backends_status[name] = {
                "status": "disconnected",
                "error": str(exc),
            }
            overall_ok = False

    return {
        "status": "healthy" if overall_ok else "degraded",
        "version": "3.0.0",
        "default_backend": engine._default_backend,
        "backends": backends_status,
    }
