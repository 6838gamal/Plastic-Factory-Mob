import asyncio
import json
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


def _jsonb_encode(value) -> str:
    """Many routers already call json.dumps(...) before passing a value in
    for a json/jsonb column (e.g. batches.py, audit.py, reports.py). Passing
    those pre-serialized strings straight through avoids double-encoding
    them into a quoted JSON string; anything that isn't already a string
    (a raw dict/list) gets serialized here instead."""
    if isinstance(value, str):
        return value
    return json.dumps(value, default=str)


async def _init_connection(conn: asyncpg.Connection) -> None:
    """Decode json/jsonb columns straight into Python objects (dict/list)
    instead of leaving them as raw JSON strings — otherwise every
    jsonb_agg(...) result (e.g. voucher items) comes back to the client
    as a string, breaking Flutter's `as List<dynamic>?` casts."""
    await conn.set_type_codec(
        "json",
        encoder=_jsonb_encode,
        decoder=json.loads,
        schema="pg_catalog",
    )
    await conn.set_type_codec(
        "jsonb",
        encoder=_jsonb_encode,
        decoder=json.loads,
        schema="pg_catalog",
    )


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
                init=_init_connection,
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
