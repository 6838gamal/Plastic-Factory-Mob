from fastapi import APIRouter
from pydantic import BaseModel
from typing import Optional
from database import get_pool

router = APIRouter(prefix="/api/mixture-types", tags=["mixture_types"])


class MixtureTypeUpsert(BaseModel):
    id: Optional[str] = None
    name: str
    description: Optional[str] = None
    is_active: Optional[bool] = True


@router.get("")
async def get_mixture_types():
    pool = await get_pool()
    rows = await pool.fetch("SELECT * FROM mixture_types WHERE is_active=true ORDER BY name")
    return [dict(r) for r in rows]


@router.post("/upsert")
async def upsert_mixture_type(body: MixtureTypeUpsert):
    pool = await get_pool()
    if body.id:
        row = await pool.fetchrow(
            "UPDATE mixture_types SET name=$1, description=$2, is_active=$3 WHERE id=$4 RETURNING *",
            body.name, body.description, body.is_active, body.id,
        )
    else:
        row = await pool.fetchrow(
            "INSERT INTO mixture_types (id, name, description, is_active) VALUES (gen_random_uuid(), $1, $2, $3) RETURNING *",
            body.name, body.description, body.is_active,
        )
    return dict(row)
