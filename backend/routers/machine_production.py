from fastapi import APIRouter, Query
from pydantic import BaseModel
from typing import Optional
from database import get_pool

router = APIRouter(prefix="/api/machine-production", tags=["machine_production"])


class ProductionCreate(BaseModel):
    batch_number: Optional[str] = None
    machine_id: Optional[str] = None
    machine_name: Optional[str] = None
    product_id: Optional[str] = None
    product_name: Optional[str] = None
    worker_id: Optional[str] = None
    worker_name: Optional[str] = None
    produced_quantity: Optional[float] = 0
    scrap_quantity: Optional[float] = 0
    waste_quantity: Optional[float] = 0
    stop_time_minutes: Optional[float] = 0
    notes: Optional[str] = None
    production_image_url: Optional[str] = None
    transaction_id: Optional[str] = None
    status: Optional[str] = "saved"


@router.get("")
async def get_productions(
    from_: Optional[str] = Query(None, alias="from"),
    to: Optional[str] = Query(None),
    machine_id: Optional[str] = Query(None),
):
    pool = await get_pool()
    conditions = ["1=1"]
    params = []
    i = 1
    if from_:
        from datetime import datetime as dt
        conditions.append(f"created_at>=${i}"); params.append(dt.fromisoformat(from_.replace('Z',''))); i += 1
    if to:
        from datetime import datetime as dt
        conditions.append(f"created_at<=${i}"); params.append(dt.fromisoformat(to.replace('Z',''))); i += 1
    if machine_id:
        conditions.append(f"machine_id=${i}"); params.append(machine_id); i += 1
    query = f"SELECT * FROM machine_production WHERE {' AND '.join(conditions)} ORDER BY created_at DESC"
    rows = await pool.fetch(query, *params)
    return [dict(r) for r in rows]


@router.put("/{production_id}")
async def update_production(production_id: str, body: ProductionCreate):
    pool = await get_pool()
    row = await pool.fetchrow(
        """UPDATE machine_production SET
            produced_quantity=$1, scrap_quantity=$2, waste_quantity=$3,
            stop_time_minutes=$4, notes=$5, status=$6, updated_at=NOW()
           WHERE id=$7 RETURNING *""",
        body.produced_quantity, body.scrap_quantity, body.waste_quantity,
        body.stop_time_minutes, body.notes, body.status or 'saved', production_id,
    )
    return dict(row)


@router.delete("/{production_id}")
async def delete_production(production_id: str):
    pool = await get_pool()
    await pool.execute("DELETE FROM machine_production WHERE id=$1", production_id)
    return {"success": True}


@router.post("")
async def create_production(body: ProductionCreate):
    pool = await get_pool()
    row = await pool.fetchrow(
        """INSERT INTO machine_production (
            id, batch_number, machine_id, machine_name, product_id, product_name,
            worker_id, worker_name, produced_quantity, scrap_quantity, waste_quantity,
            stop_time_minutes, notes, production_image_url, transaction_id, status
        ) VALUES (gen_random_uuid(), $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
        RETURNING *""",
        body.batch_number, body.machine_id, body.machine_name,
        body.product_id, body.product_name, body.worker_id, body.worker_name,
        body.produced_quantity, body.scrap_quantity, body.waste_quantity,
        body.stop_time_minutes, body.notes, body.production_image_url,
        body.transaction_id, body.status,
    )
    return dict(row)
