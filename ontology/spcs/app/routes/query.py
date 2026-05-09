"""Arbitrary Rel query endpoint (admin-only)."""

from typing import Any

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

router = APIRouter()


class RelQueryRequest(BaseModel):
    """Request body for Rel query execution."""

    rel_source: str


@router.post("/query")
async def execute_rel_query(
    request: Request, body: RelQueryRequest
) -> list[dict[str, Any]]:
    """Execute an arbitrary Rel query on the RAI engine.

    Requires ONTOLOGY_ADMIN role (validated via session token).

    Args:
        body: Request body containing the Rel source to execute.
    """
    client = request.app.state.rai_client

    # Validate caller has admin privileges by checking current role
    try:
        role_result = client.session.sql("SELECT CURRENT_ROLE() AS role").collect()
        current_role = role_result[0]["ROLE"] if role_result else None
        if current_role not in ("ONTOLOGY_ADMIN", "DATA_ADMIN", "ACCOUNTADMIN"):
            raise HTTPException(
                status_code=403,
                detail="Requires ONTOLOGY_ADMIN role to execute arbitrary Rel queries",
            )
    except Exception as e:
        if isinstance(e, HTTPException):
            raise
        raise HTTPException(status_code=500, detail=f"Role check failed: {e}")

    try:
        results = client.query_rel(body.rel_source)
        return results
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Rel query failed: {e}")
