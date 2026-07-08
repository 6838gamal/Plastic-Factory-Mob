from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional
from database import get_pool
from materials_seed import export_raw_materials_seed

router = APIRouter(prefix="/api/materials", tags=["materials"])


class MaterialUpsert(BaseModel):
    id: Optional[str] = None
    name: str
    code: Optional[str] = None
    category: Optional[str] = "عام"
    unit: Optional[str] = "كجم"
    min_stock: Optional[float] = 0
    cost_per_unit: Optional[float] = 0
    is_active: Optional[bool] = True
    notes: Optional[str] = None


@router.get("")
async def get_materials():
    pool = await get_pool()
    rows = await pool.fetch(
        "SELECT * FROM raw_materials WHERE is_active=true ORDER BY category, name"
    )
    return [dict(r) for r in rows]


@router.get("/all")
async def get_all_materials():
    pool = await get_pool()
    rows = await pool.fetch("SELECT * FROM raw_materials ORDER BY category, name")
    return [dict(r) for r in rows]


@router.post("/upsert")
async def upsert_material(body: MaterialUpsert):
    pool = await get_pool()
    if body.id:
        row = await pool.fetchrow(
            """UPDATE raw_materials SET name=$1, code=$2, category=$3, unit=$4,
               min_stock=$5, cost_per_unit=$6, is_active=$7, notes=$8, updated_at=NOW()
               WHERE id=$9 RETURNING *""",
            body.name, body.code, body.category, body.unit, body.min_stock,
            body.cost_per_unit, body.is_active, body.notes, body.id,
        )
    else:
        row = await pool.fetchrow(
            """INSERT INTO raw_materials (id, name, code, category, unit, min_stock, cost_per_unit, is_active, notes)
               VALUES (gen_random_uuid(), $1, $2, $3, $4, $5, $6, $7, $8) RETURNING *""",
            body.name, body.code, body.category, body.unit, body.min_stock,
            body.cost_per_unit, body.is_active, body.notes,
        )
    await export_raw_materials_seed()
    return dict(row)


@router.delete("/{material_id}")
async def delete_material(material_id: str):
    pool = await get_pool()
    await pool.execute(
        "UPDATE raw_materials SET is_active=false, updated_at=NOW() WHERE id=$1", material_id
    )
    await export_raw_materials_seed()
    return {"success": True}
