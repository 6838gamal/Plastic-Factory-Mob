from fastapi import APIRouter
from pydantic import BaseModel
from typing import Optional
from database import get_pool

router = APIRouter(prefix="/api/workers", tags=["workers"])


class WorkerUpsert(BaseModel):
    id: Optional[str] = None
    name: str
    phone: Optional[str] = None
    employee_id: Optional[str] = None
    is_active: Optional[bool] = True


@router.get("")
async def get_workers():
    pool = await get_pool()
    rows = await pool.fetch("SELECT * FROM workers WHERE is_active=true ORDER BY name")
    return [dict(r) for r in rows]


@router.post("/upsert")
async def upsert_worker(body: WorkerUpsert):
    pool = await get_pool()
    if body.id:
        row = await pool.fetchrow(
            "UPDATE workers SET name=$1, phone=$2, employee_id=$3, is_active=$4, updated_at=NOW() WHERE id=$5 RETURNING *",
            body.name, body.phone, body.employee_id, body.is_active, body.id,
        )
    else:
        row = await pool.fetchrow(
            "INSERT INTO workers (id, name, phone, employee_id, is_active) VALUES (gen_random_uuid(), $1, $2, $3, $4) RETURNING *",
            body.name, body.phone, body.employee_id, body.is_active,
        )
    return dict(row)


@router.delete("/{worker_id}")
async def delete_worker(worker_id: str):
    pool = await get_pool()
    await pool.execute("UPDATE workers SET is_active=false, updated_at=NOW() WHERE id=$1", worker_id)
    return {"success": True}
