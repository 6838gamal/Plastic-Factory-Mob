from fastapi import APIRouter
from pydantic import BaseModel
from typing import Optional
from database import get_pool

router = APIRouter(prefix="/api/mixers", tags=["mixers"])


class MixerUpsert(BaseModel):
    id: Optional[str] = None
    name: str
    capacity: Optional[float] = None
    is_active: Optional[bool] = True


@router.get("")
async def get_mixers():
    pool = await get_pool()
    rows = await pool.fetch("SELECT * FROM mixers WHERE is_active=true ORDER BY name")
    return [dict(r) for r in rows]


@router.post("/upsert")
async def upsert_mixer(body: MixerUpsert):
    pool = await get_pool()
    if body.id:
        row = await pool.fetchrow(
            "UPDATE mixers SET name=$1, capacity=$2, is_active=$3 WHERE id=$4 RETURNING *",
            body.name, body.capacity, body.is_active, body.id,
        )
    else:
        row = await pool.fetchrow(
            "INSERT INTO mixers (id, name, capacity, is_active) VALUES (gen_random_uuid(), $1, $2, $3) RETURNING *",
            body.name, body.capacity, body.is_active,
        )
    return dict(row)
