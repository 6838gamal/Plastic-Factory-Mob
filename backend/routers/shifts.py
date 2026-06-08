from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional
from database import get_pool

router = APIRouter(prefix="/api/shifts", tags=["shifts"])


class ShiftCreate(BaseModel):
    name: str
    is_active: Optional[bool] = True


@router.get("")
async def get_shifts():
    pool = await get_pool()
    rows = await pool.fetch(
        "SELECT * FROM shifts WHERE is_active=true ORDER BY name"
    )
    return [dict(r) for r in rows]


@router.get("/all")
async def get_all_shifts():
    pool = await get_pool()
    rows = await pool.fetch("SELECT * FROM shifts ORDER BY name")
    return [dict(r) for r in rows]


@router.post("")
async def create_shift(body: ShiftCreate):
    pool = await get_pool()
    try:
        row = await pool.fetchrow(
            "INSERT INTO shifts (name, is_active) VALUES ($1, $2) RETURNING *",
            body.name, body.is_active,
        )
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
    return dict(row)


@router.put("/{shift_id}")
async def update_shift(shift_id: str, body: ShiftCreate):
    pool = await get_pool()
    row = await pool.fetchrow(
        "UPDATE shifts SET name=$1, is_active=$2 WHERE id=$3 RETURNING *",
        body.name, body.is_active, shift_id,
    )
    if not row:
        raise HTTPException(status_code=404, detail="Shift not found")
    return dict(row)


@router.delete("/{shift_id}")
async def delete_shift(shift_id: str):
    pool = await get_pool()
    await pool.execute(
        "UPDATE shifts SET is_active=false WHERE id=$1", shift_id
    )
    return {"success": True}
