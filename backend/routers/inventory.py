from fastapi import APIRouter, Query
from pydantic import BaseModel
from typing import Optional
from database import get_pool
import json

router = APIRouter(prefix="/api/inventory", tags=["inventory"])


class BalanceUpdate(BaseModel):
    material_id: str
    warehouse_type: str
    balance: float


class TransactionCreate(BaseModel):
    material_id: str
    warehouse_type: str
    transaction_type: str
    quantity: float
    batch_id: Optional[str] = None
    production_id: Optional[str] = None
    transaction_ref: Optional[str] = None
    created_by: Optional[str] = None
    notes: Optional[str] = None


@router.get("")
async def get_inventory(warehouse_type: Optional[str] = Query(None)):
    pool = await get_pool()
    if warehouse_type:
        rows = await pool.fetch(
            """SELECT i.*, r.name AS material_name, r.unit, r.min_stock
               FROM inventory i JOIN raw_materials r ON r.id=i.material_id
               WHERE i.warehouse_type=$1 ORDER BY r.name""",
            warehouse_type,
        )
    else:
        rows = await pool.fetch(
            """SELECT i.*, r.name AS material_name, r.unit, r.min_stock
               FROM inventory i JOIN raw_materials r ON r.id=i.material_id
               ORDER BY r.name"""
        )
    return [dict(r) for r in rows]


@router.get("/material/{material_id}")
async def get_material_inventory(material_id: str, warehouse_type: str = Query(...)):
    pool = await get_pool()
    row = await pool.fetchrow(
        """SELECT i.*, r.name AS material_name, r.unit, r.min_stock
           FROM inventory i JOIN raw_materials r ON r.id=i.material_id
           WHERE i.material_id=$1 AND i.warehouse_type=$2""",
        material_id, warehouse_type,
    )
    return dict(row) if row else None


@router.post("/balance")
async def update_balance(body: BalanceUpdate):
    pool = await get_pool()
    row = await pool.fetchrow(
        """INSERT INTO inventory (id, material_id, warehouse_type, balance, updated_at)
           VALUES (gen_random_uuid(), $1, $2, $3, NOW())
           ON CONFLICT (material_id, warehouse_type)
           DO UPDATE SET balance=$3, updated_at=NOW()
           RETURNING *""",
        body.material_id, body.warehouse_type, body.balance,
    )
    return dict(row)


@router.get("/transactions")
async def get_transactions(
    material_id: Optional[str] = Query(None),
    warehouse_type: Optional[str] = Query(None),
    from_: Optional[str] = Query(None, alias="from"),
    to: Optional[str] = Query(None),
):
    pool = await get_pool()
    conditions = ["1=1"]
    params = []
    i = 1
    if material_id:
        conditions.append(f"material_id=${i}"); params.append(material_id); i += 1
    if warehouse_type:
        conditions.append(f"warehouse_type=${i}"); params.append(warehouse_type); i += 1
    if from_:
        conditions.append(f"created_at>=${i}"); params.append(from_); i += 1
    if to:
        conditions.append(f"created_at<=${i}"); params.append(to); i += 1
    query = f"SELECT * FROM inventory_transactions WHERE {' AND '.join(conditions)} ORDER BY created_at DESC LIMIT 100"
    rows = await pool.fetch(query, *params)
    return [dict(r) for r in rows]


@router.post("/transactions")
async def add_transaction(body: TransactionCreate):
    pool = await get_pool()
    row = await pool.fetchrow(
        """INSERT INTO inventory_transactions
           (id, material_id, warehouse_type, transaction_type, quantity,
            batch_id, production_id, transaction_ref, created_by, notes)
           VALUES (gen_random_uuid(), $1, $2, $3, $4, $5, $6, $7, $8, $9)
           RETURNING *""",
        body.material_id, body.warehouse_type, body.transaction_type, body.quantity,
        body.batch_id, body.production_id, body.transaction_ref, body.created_by, body.notes,
    )
    return dict(row)
