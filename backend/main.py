import os
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from database import get_pool, close_pool
from routers import (
    auth, materials, inventory, workers, products,
    machines, mixers, mixture_types, batches,
    machine_production, alerts, audit, dashboard,
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


@app.get("/api/health")
async def health():
    try:
        pool = await get_pool()
        await pool.fetchval("SELECT 1")
        return {"status": "ok", "db": "connected"}
    except Exception as e:
        return {"status": "error", "db": str(e)}


if WEB_DIR.exists():
    app.mount("/", StaticFiles(directory=str(WEB_DIR), html=True), name="flutter")
