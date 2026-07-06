"""
Suppliers router — CRUD for supplier management (الموردين).
"""
import logging
from datetime import datetime
from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import Optional
from database import get_pool

logger = logging.getLogger("plastic_factory.suppliers")
router = APIRouter(prefix="/api/suppliers", tags=["suppliers"])


class SupplierCreate(BaseModel):
    name: str
    phone: Optional[str] = None
    email: Optional[str] = None
    address: Optional[str] = None
    category: Optional[str] = None
    notes: Optional[str] = None
    is_active: bool = True


class SupplierUpdate(BaseModel):
    name: Optional[str] = None
    phone: Optional[str] = None
    email: Optional[str] = None
    address: Optional[str] = None
    category: Optional[str] = None
    notes: Optional[str] = None
    is_active: Optional[bool] = None


def _row(r) -> dict:
    if r is None:
        return {}
    d = dict(r)
    for k, v in d.items():
        if isinstance(v, datetime):
            d[k] = v.isoformat()
    return d


@router.get("")
async def list_suppliers(active_only: bool = Query(False)):
    pool = await get_pool()
    if active_only:
        rows = await pool.fetch("SELECT * FROM suppliers WHERE is_active=TRUE ORDER BY name")
    else:
        rows = await pool.fetch("SELECT * FROM suppliers ORDER BY is_active DESC, name")
    return [_row(r) for r in rows]


@router.get("/{supplier_id}")
async def get_supplier(supplier_id: str):
    pool = await get_pool()
    row = await pool.fetchrow("SELECT * FROM suppliers WHERE id=$1::uuid", supplier_id)
    if not row:
        raise HTTPException(404, "المورد غير موجود")
    return _row(row)


@router.post("")
async def create_supplier(body: SupplierCreate):
    pool = await get_pool()
    if not body.name or not body.name.strip():
        raise HTTPException(400, "اسم المورد مطلوب")
    # Prevent duplicate active name
    dup = await pool.fetchrow(
        "SELECT id FROM suppliers WHERE LOWER(name)=LOWER($1)", body.name.strip()
    )
    if dup:
        raise HTTPException(400, "يوجد مورد بنفس الاسم مسبقاً")
    row = await pool.fetchrow(
        """INSERT INTO suppliers (name, phone, email, address, category, notes, is_active)
           VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id""",
        body.name.strip(), body.phone or None, body.email or None,
        body.address or None, body.category or None,
        body.notes or None, body.is_active,
    )
    logger.info(f"[suppliers] Created supplier '{body.name}' id={row['id']}")
    return {"id": str(row["id"]), "message": "تم إضافة المورد بنجاح"}


@router.put("/{supplier_id}")
async def update_supplier(supplier_id: str, body: SupplierUpdate):
    pool = await get_pool()
    existing = await pool.fetchrow(
        "SELECT * FROM suppliers WHERE id=$1::uuid", supplier_id
    )
    if not existing:
        raise HTTPException(404, "المورد غير موجود")
    # Check name duplication (skip if same record)
    if body.name:
        dup = await pool.fetchrow(
            "SELECT id FROM suppliers WHERE LOWER(name)=LOWER($1) AND id!=$2::uuid",
            body.name.strip(), supplier_id,
        )
        if dup:
            raise HTTPException(400, "يوجد مورد آخر بنفس الاسم")
    await pool.execute(
        """UPDATE suppliers SET
               name      = COALESCE($1, name),
               phone     = COALESCE($2, phone),
               email     = COALESCE($3, email),
               address   = COALESCE($4, address),
               category  = COALESCE($5, category),
               notes     = COALESCE($6, notes),
               is_active = COALESCE($7, is_active),
               updated_at = NOW()
           WHERE id=$8::uuid""",
        body.name.strip() if body.name else None,
        body.phone, body.email, body.address,
        body.category, body.notes, body.is_active,
        supplier_id,
    )
    return {"message": "تم تحديث بيانات المورد بنجاح"}


@router.delete("/{supplier_id}")
async def delete_supplier(supplier_id: str):
    pool = await get_pool()
    existing = await pool.fetchrow(
        "SELECT name FROM suppliers WHERE id=$1::uuid", supplier_id
    )
    if not existing:
        raise HTTPException(404, "المورد غير موجود")
    await pool.execute("DELETE FROM suppliers WHERE id=$1::uuid", supplier_id)
    logger.info(f"[suppliers] Deleted supplier '{existing['name']}'")
    return {"message": "تم حذف المورد بنجاح"}
