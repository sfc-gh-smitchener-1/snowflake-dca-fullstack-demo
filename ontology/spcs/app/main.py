"""Ontology Knowledge Graph API - FastAPI entry point.

Exposes the Ontology Knowledge Graph as a REST API running on SPCS.
Provides endpoints for querying nodes, edges, governance scores,
and executing RAI Rel queries.
"""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.rai_client import RAIClient
from app.routes import edges, health, nodes, query, scores


@asynccontextmanager
async def lifespan(application: FastAPI):
    """Initialize RAI client connection on startup."""
    application.state.rai_client = RAIClient()
    await application.state.rai_client.initialize()
    yield
    # Cleanup on shutdown
    application.state.rai_client = None


app = FastAPI(
    title="Ontology Knowledge Graph API",
    description="REST API for the DCA Demo Ontology Knowledge Graph powered by RelationalAI",
    version="1.0.0",
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
app.include_router(query.router, tags=["Query"])
