import asyncio
import asyncpg
from urllib.parse import urlparse, parse_qs

from settings import DATABASE_URL as _DATABASE_URL

DATABASE_URL: str = _DATABASE_URL or ""

if not DATABASE_URL:
    raise RuntimeError(
        "DATABASE_URL environment variable is not set. "
        "Please configure a PostgreSQL database in your environment."
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
