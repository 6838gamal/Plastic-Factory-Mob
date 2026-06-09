import os
import asyncpg
from urllib.parse import urlparse, parse_qs

DATABASE_URL = os.getenv("DATABASE_URL") or os.getenv("PG_DATABASE_URL")

if not DATABASE_URL:
    raise RuntimeError(
        "DATABASE_URL environment variable is not set. "
        "Set it to your PostgreSQL connection string, e.g.: "
        "postgresql://user:pass@host:5432/dbname"
    )

_pool: asyncpg.Pool | None = None


def _resolve_ssl(url: str):
    """Determine SSL mode from the URL itself, then fall back to host heuristics.

    Priority:
      1. sslmode=disable in query string → no SSL
      2. sslmode=require/verify-* in query string → SSL
      3. Known local/internal hosts → no SSL
      4. Default → require SSL (safe for any cloud provider)
    """
    try:
        parsed = urlparse(url)
        params = parse_qs(parsed.query)
        sslmode = (params.get("sslmode") or [None])[0]

        if sslmode == "disable":
            return None
        if sslmode in ("require", "verify-ca", "verify-full"):
            return "require"

        host = (parsed.hostname or "").lower()
        local_patterns = ("localhost", "127.0.0.1", "::1", "host.docker.internal", "helium")
        if any(p in host for p in local_patterns):
            return None

        return "require"
    except Exception:
        return None


async def get_pool() -> asyncpg.Pool:
    global _pool
    if _pool is None:
        ssl_mode = _resolve_ssl(DATABASE_URL)
        _pool = await asyncpg.create_pool(
            DATABASE_URL,
            ssl=ssl_mode,
            min_size=1,
            max_size=10,
        )
    return _pool


async def close_pool():
    global _pool
    if _pool:
        await _pool.close()
        _pool = None
