import os
from fastapi import APIRouter, Request

router = APIRouter(prefix="/api", tags=["config"])


@router.get("/config")
async def get_config(request: Request):
    """Return the API base URL so the Flutter frontend can find the backend.

    Priority:
      1. API_BASE_URL env var (explicit override)
      2. Derived from the incoming request (works on Replit dev & production)
    """
    explicit = os.getenv("API_BASE_URL")
    if explicit:
        base_url = explicit.rstrip("/")
    else:
        # Use the request host so it works in any environment automatically
        scheme = request.headers.get("x-forwarded-proto", request.url.scheme)
        host   = request.headers.get("x-forwarded-host",  request.url.hostname)
        port   = request.url.port
        if port and port not in (80, 443):
            base_url = f"{scheme}://{host}:{port}"
        else:
            base_url = f"{scheme}://{host}"

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
        """INSERT INTO settings (key, value, updated_at)
           VALUES ($1, $2, NOW())
           ON CONFLICT (key) DO UPDATE SET value=$2, updated_at=NOW()
           RETURNING *""",
        key, str(body.get("value", "")),
    )
    return dict(row)
