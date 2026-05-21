"""Ontology Knowledge Graph API - FastAPI entry point.

Exposes the Ontology Knowledge Graph as a REST API running on SPCS.
Provides endpoints for querying nodes, edges, governance scores, and
graph inference via one or both of two interchangeable backends:

  - Snowflake-native (recursive CTEs, default)
  - Neo4j (Cypher, optional sidecar)

Backend selection is controlled by the GRAPH_BACKEND env var. See
docs/GRAPH_BACKENDS.md for the compare/contrast and decision matrix.
"""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.graph_engine import GraphEngine
from app.routes import edges, health, inference, nodes, scores


@asynccontextmanager
async def lifespan(application: FastAPI):
    """Initialize graph engine on startup."""
    application.state.graph_engine = GraphEngine()
    await application.state.graph_engine.initialize()
    yield
    application.state.graph_engine = None


app = FastAPI(
    title="Ontology Knowledge Graph API",
    description=(
        "REST API for the DCA Demo Ontology Knowledge Graph. "
        "Pluggable backends: Snowflake-native (recursive CTEs) and/or Neo4j (Cypher). "
        "Every inference route accepts ?backend=snowflake|neo4j|both."
    ),
    version="3.0.0",
    lifespan=lifespan,
)

# CORS middleware for Streamlit and other frontends
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include route modules
app.include_router(health.router, tags=["Health"])
app.include_router(nodes.router, prefix="/nodes", tags=["Nodes"])
app.include_router(edges.router, prefix="/edges", tags=["Edges"])
app.include_router(scores.router, prefix="/governance-scores", tags=["Governance Scores"])
app.include_router(inference.router, prefix="/inference", tags=["Inference"])
