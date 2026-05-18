"""Governance scores endpoints."""

from typing import Any

from fastapi import APIRouter, Request

router = APIRouter()


@router.get("")
async def list_governance_scores(
    request: Request, min_score: float | None = None
) -> list[dict[str, Any]]:
    """List all governance scores, optionally filtered by minimum threshold.

    Args:
        min_score: Minimum overall_score to include in results.
    """
    engine = request.app.state.graph_engine
    return engine.get_governance_scores(min_score=min_score)


@router.get("/{node_id}")
async def get_node_governance_score(
    request: Request, node_id: str
) -> dict[str, Any]:
    """Get the governance score for a single node."""
    engine = request.app.state.graph_engine
    results = engine.session.sql(
        f"SELECT * FROM DCA_DEMO.GOVERNANCE.ONTOLOGY_GRAPH_RAI_GOVERNANCE_SCORES WHERE node_id = '{node_id}'"
    ).collect()
    if not results:
        return {"error": "Score not found for node", "node_id": node_id}
    return results[0].as_dict()
