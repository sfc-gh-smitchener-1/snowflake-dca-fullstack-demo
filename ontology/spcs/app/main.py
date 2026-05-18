"""Ontology Knowledge Graph API - FastAPI entry point.

Exposes the Ontology Knowledge Graph as a REST API running on SPCS.
Provides endpoints for querying nodes, edges, governance scores,
and graph inference via an in-memory NetworkX engine.
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
    # Cleanup on shutdown
    application.state.graph_engine = None


app = FastAPI(
    title="Ontology Knowledge Graph API",
    description="REST API for the DCA Demo Ontology Knowledge Graph (NetworkX engine on SPCS)",
    version="2.0.0",
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
