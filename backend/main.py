import os
import sys
from contextlib import asynccontextmanager
from pathlib import Path

# Ensure backend directory is always on the Python path regardless of CWD
sys.path.insert(0, os.path.dirname(__file__))

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse

from database import get_pool, close_pool
from routers import (
    auth, materials, inventory, workers, products,
    machines, mixers, mixture_types, batches,
    machine_production, alerts, audit, dashboard, config,
    shifts, opening_balances, reports,
)

WEB_DIR = Path(__file__).parent.parent / "build" / "web"


@asynccontextmanager
async def lifespan(app: FastAPI):
    await get_pool()
    print("✅ Database pool ready")
    yield
    await close_pool()
    print("Database pool closed")


app = FastAPI(title="Plastic Factory ERP API", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(materials.router)
app.include_router(inventory.router)
app.include_router(workers.router)
app.include_router(products.router)
app.include_router(machines.router)
app.include_router(mixers.router)
app.include_router(mixture_types.router)
app.include_router(batches.router)
app.include_router(machine_production.router)
app.include_router(alerts.router)
app.include_router(audit.router)
app.include_router(dashboard.router)
app.include_router(config.router)
app.include_router(shifts.router)
app.include_router(opening_balances.router)
app.include_router(reports.router)


@app.get("/api/health")
async def health():
    try:
        pool = await get_pool()
        await pool.fetchval("SELECT 1")
        return {"status": "ok", "db": "connected"}
    except Exception as e:
        return {"status": "error", "db": str(e)}


_NO_CACHE = {"Cache-Control": "no-cache, no-store, must-revalidate", "Pragma": "no-cache"}

if WEB_DIR.exists():
    # Serve service worker and index.html with no-cache so browsers always pick up fresh builds
    @app.get("/flutter_service_worker.js")
    async def service_worker():
        return FileResponse(str(WEB_DIR / "flutter_service_worker.js"), headers=_NO_CACHE)

    @app.get("/index.html")
    async def index_html():
        return FileResponse(str(WEB_DIR / "index.html"), headers=_NO_CACHE)

    @app.get("/flutter_bootstrap.js")
    async def flutter_bootstrap():
        return FileResponse(str(WEB_DIR / "flutter_bootstrap.js"), headers=_NO_CACHE)

    app.mount("/", StaticFiles(directory=str(WEB_DIR), html=True), name="flutter")
