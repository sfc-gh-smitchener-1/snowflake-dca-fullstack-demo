"""Health check endpoint."""

from fastapi import APIRouter

router = APIRouter()


@router.get("/health")
async def health_check() -> dict:
    """Return service health status."""
    return {
        "status": "healthy",
        "engine": "ONTOLOGY_ENGINE",
        "version": "1.0.0",
    }
