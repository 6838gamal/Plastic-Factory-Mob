import os
import asyncpg

DATABASE_URL = os.getenv("DATABASE_URL") or os.getenv("PG_DATABASE_URL")

if not DATABASE_URL:
    raise RuntimeError("DATABASE_URL environment variable is not set")

_pool: asyncpg.Pool | None = None


async def get_pool() -> asyncpg.Pool:
    global _pool
    if _pool is None:
        use_ssl = "helium" not in DATABASE_URL and "localhost" not in DATABASE_URL and "127.0.0.1" not in DATABASE_URL
        _pool = await asyncpg.create_pool(
            DATABASE_URL,
            ssl="require" if use_ssl else None,
            min_size=1,
            max_size=10,
        )
    return _pool


async def close_pool():
    global _pool
    if _pool:
        await _pool.close()
        _pool = None
