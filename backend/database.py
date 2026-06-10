import os
import asyncio
import asyncpg
from urllib.parse import urlparse, parse_qs

# Default connection string — overridden by DATABASE_URL / PG_DATABASE_URL env vars if set
_DEFAULT_DATABASE_URL = (
    "postgresql://gamalalmaqtary:tqL6D95VvkoCR9f1gE1fZykYakFU9sXb"
    "@dpg-d8j5350jo6nc73duopqg-a.virginia-postgres.render.com/plastic_factory_db"
)

DATABASE_URL = (
    os.getenv("DATABASE_URL")
    or os.getenv("PG_DATABASE_URL")
    or _DEFAULT_DATABASE_URL
)

_pool: asyncpg.Pool | None = None


def _resolve_ssl(url: str):
    """Determine SSL mode from the URL itself, then fall back to host heuristics."""
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
    """Return the shared connection pool, creating it with retry logic if needed."""
    global _pool
    if _pool is not None:
        return _pool

    ssl_mode = _resolve_ssl(DATABASE_URL)
    attempt = 0
    while True:
        attempt += 1
        try:
            if attempt == 1:
                print("⏳ [DB] جاري الاتصال بقاعدة البيانات...")
            else:
                print(f"⏳ [DB] إعادة المحاولة رقم {attempt}...")

            _pool = await asyncpg.create_pool(
                DATABASE_URL,
                ssl=ssl_mode,
                min_size=1,
                max_size=10,
            )
            print("✅ [DB] تم الاتصال بقاعدة البيانات بنجاح")
            return _pool

        except Exception as exc:
            delay = min(5 * attempt, 30)
            print(f"❌ [DB] فشل الاتصال: {exc}")
            print(f"⏳ [DB] إعادة المحاولة بعد {delay} ثانية...")
            await asyncio.sleep(delay)


async def close_pool():
    global _pool
    if _pool:
        await _pool.close()
        _pool = None
