import os
import asyncpg

DEFAULT_DB_URL = (
    "postgresql://gamalalmaqtary:tqL6D95VvkoCR9f1gE1fZykYakFU9sXb"
    "@dpg-d8j5350jo6nc73duopqg-a.virginia-postgres.render.com/plastic_factory_db"
)

DATABASE_URL = os.getenv("PG_DATABASE_URL", DEFAULT_DB_URL)

_pool: asyncpg.Pool | None = None


async def get_pool() -> asyncpg.Pool:
    global _pool
    if _pool is None:
        _pool = await asyncpg.create_pool(
            DATABASE_URL,
            ssl="require",
            min_size=1,
            max_size=10,
        )
    return _pool


async def close_pool():
    global _pool
    if _pool:
        await _pool.close()
        _pool = None
