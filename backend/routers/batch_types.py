from fastapi import APIRouter
from pydantic import BaseModel
from typing import Optional
from database import get_pool

router = APIRouter(prefix="/api/batch-types", tags=["batch_types"])


class BatchTypeUpsert(BaseModel):
    id: Optional[str] = None
    name: str
    description: Optional[str] = None
    is_active: Optional[bool] = True


@router.get("")
async def get_batch_types():
    pool = await get_pool()
    rows = await pool.fetch("SELECT * FROM batch_types WHERE is_active=true ORDER BY name")
    return [dict(r) for r in rows]


@router.post("/upsert")
async def upsert_batch_type(body: BatchTypeUpsert):
    pool = await get_pool()
    if body.id:
        row = await pool.fetchrow(
            "UPDATE batch_types SET name=$1, description=$2, is_active=$3 WHERE id=$4 RETURNING *",
            body.name, body.description, body.is_active, body.id,
        )
    else:
        row = await pool.fetchrow(
            "INSERT INTO batch_types (id, name, description, is_active) VALUES (gen_random_uuid(), $1, $2, $3) RETURNING *",
            body.name, body.description, body.is_active,
        )
    return dict(row)


@router.delete("/{batch_type_id}")
async def delete_batch_type(batch_type_id: str):
    pool = await get_pool()
    await pool.execute(
        "UPDATE batch_types SET is_active=false WHERE id=$1", batch_type_id
    )
    return {"ok": True}
