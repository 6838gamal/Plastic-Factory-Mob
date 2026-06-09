import os
from fastapi import APIRouter, Request

router = APIRouter(prefix="/api", tags=["config"])


@router.get("/config")
async def get_config(request: Request):
    """Return the API base URL so the Flutter frontend can find the backend.

    Priority:
      1. API_BASE_URL env var (explicit override)
      2. Derived from the incoming request (works on Replit dev & production)

    When behind a reverse proxy (x-forwarded-host is set), the external URL
    has no port — never append the internal uvicorn port in that case.
    """
    explicit = os.getenv("API_BASE_URL")
    if explicit and "onrender.com" not in explicit:
        base_url = explicit.rstrip("/")
    else:
        forwarded_host  = request.headers.get("x-forwarded-host")
        forwarded_proto = request.headers.get("x-forwarded-proto")

        if forwarded_host:
            # Behind a proxy: use the external host/scheme with no port
            scheme = forwarded_proto or "https"
            base_url = f"{scheme}://{forwarded_host}"
        else:
            # Direct connection (local dev): include port if non-standard
            scheme = request.url.scheme
            host   = request.url.hostname
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
        """INSERT INTO settings (key, value)
           VALUES ($1, $2)
           ON CONFLICT (key) DO UPDATE SET value=$2
           RETURNING *""",
        key, str(body.get("value", "")),
    )
    return dict(row)
