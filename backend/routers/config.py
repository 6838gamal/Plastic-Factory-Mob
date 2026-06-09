import os
from fastapi import APIRouter, Request

router = APIRouter(prefix="/api", tags=["config"])

DEFAULT_API_URL = "https://plastic-factory-api.onrender.com"


@router.get("/config")
async def get_config(request: Request):
    """Return the API base URL so the Flutter frontend can find the backend.

    Priority:
      1. API_BASE_URL env var (explicit override)
      2. Default: https://plastic-factory-api.onrender.com
    """
    base_url = os.getenv("API_BASE_URL", DEFAULT_API_URL).rstrip("/")
    return {"base_url": base_url}


@router.get("/settings")
async def get_settings():
    from database import get_pool
    pool = await get_pool()
    rows = await pool.fetch("SELECT key, value, description FROM settings ORDER BY key")
    return {r["key"]: {"value": r["value"], "description": r["description"]} for r in rows}


@router.put("/settings/{key}")
async def update_setting(key: str, body: dict):
    from database import get_pool
    pool = await get_pool()
    row = await pool.fetchrow(
        """INSERT INTO settings (key, value)
           VALUES ($1, $2)
           ON CONFLICT (key) DO UPDATE SET value=$2
           RETURNING *""",
        key, str(body.get("value", "")),
    )
    return dict(row)
