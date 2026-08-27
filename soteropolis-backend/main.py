"""FastAPI application entrypoint - wires up middleware and routers."""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from routers import auth, descartes, ecopontos, resgates

app = FastAPI(title="Soteropolis Chain API", version="0.1.0")

# Permissive for now: this backend serves the Flutter mobile app, which has
# no browser-origin concept to restrict against. Restrict allow_origins to
# specific domains before any browser-based client consumes this API.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router, prefix="/users", tags=["auth"])
app.include_router(ecopontos.router, prefix="/ecopontos", tags=["ecopontos"])
app.include_router(descartes.router, prefix="/descartes", tags=["descartes"])
app.include_router(resgates.router, prefix="/resgates", tags=["resgates"])
