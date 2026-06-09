"""
Inventory router.

Flows:
 - GET /: list inventory by warehouse_type
 - GET /summary: inventory_summary VIEW
 - POST /balance: set absolute balance (admin override) + log transaction
 - POST /transfer: transfer qty from main → mixer (deduct main, add mixer, log both)
 - GET /transactions: movement history
 - POST /transactions: manual transaction entry
 - GET /material/{id}: single material inventory row
"""
from fastapi import APIRouter, Query, HTTPException
from pydantic import BaseModel
from typing import Optional
from database import get_pool

router = APIRouter(prefix="/api/inventory", tags=["inventory"])


class BalanceUpdate(BaseModel):
    material_id: str
    warehouse_type: str
    balance: float
    reason: Optional[str] = None
    created_by: Optional[str] = None


class TransferRequest(BaseModel):
    material_id: str
    quantity: float
    from_warehouse: Optional[str] = "main"
    to_warehouse: Optional[str] = "mixer"
    notes: Optional[str] = None
    created_by: Optional[str] = None


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
    balance_before: Optional[float] = None
    balance_after: Optional[float] = None


# ─────────────────────── GET endpoints ──────────────────────────

@router.get("")
async def get_inventory(warehouse_type: Optional[str] = Query(None)):
    pool = await get_pool()
    if warehouse_type:
        rows = await pool.fetch(
            """SELECT i.*, r.name AS material_name, r.unit, r.min_stock, r.code,
                      COALESCE(r.cost_per_unit, 0) AS cost_per_unit,
                      CASE WHEN i.balance <= 0 THEN 'out_of_stock'
                           WHEN r.min_stock > 0 AND i.balance <= r.min_stock THEN 'low'
                           ELSE 'normal' END AS stock_status
               FROM inventory i JOIN raw_materials r ON r.id=i.material_id
               WHERE i.warehouse_type=$1 ORDER BY r.name""",
            warehouse_type,
        )
    else:
        rows = await pool.fetch(
            """SELECT i.*, r.name AS material_name, r.unit, r.min_stock, r.code,
                      COALESCE(r.cost_per_unit, 0) AS cost_per_unit,
                      CASE WHEN i.balance <= 0 THEN 'out_of_stock'
                           WHEN r.min_stock > 0 AND i.balance <= r.min_stock THEN 'low'
                           ELSE 'normal' END AS stock_status
               FROM inventory i JOIN raw_materials r ON r.id=i.material_id
               ORDER BY r.name"""
        )
    return [dict(r) for r in rows]


@router.get("/summary")
async def get_inventory_summary(
    warehouse_type: Optional[str] = Query(None),
    low_stock_only: bool = Query(False),
):
    pool = await get_pool()
    conditions = ["1=1"]
    params = []
    i = 1
    if warehouse_type:
        conditions.append(f"warehouse_type=${i}"); params.append(warehouse_type); i += 1
    if low_stock_only:
        conditions.append("stock_status IN ('low','out_of_stock')")
    rows = await pool.fetch(
        f"SELECT * FROM inventory_summary WHERE {' AND '.join(conditions)} ORDER BY material_name",
        *params,
    )
    return [dict(r) for r in rows]


@router.get("/material/{material_id}")
async def get_material_inventory(material_id: str, warehouse_type: str = Query(...)):
    pool = await get_pool()
    row = await pool.fetchrow(
        """SELECT i.*, r.name AS material_name, r.unit, r.min_stock, r.code,
                  COALESCE(r.cost_per_unit, 0) AS cost_per_unit,
                  CASE WHEN i.balance <= 0 THEN 'out_of_stock'
                       WHEN r.min_stock > 0 AND i.balance <= r.min_stock THEN 'low'
                       ELSE 'normal' END AS stock_status
           FROM inventory i JOIN raw_materials r ON r.id=i.material_id
           WHERE i.material_id=$1 AND i.warehouse_type=$2""",
        material_id, warehouse_type,
    )
    return dict(row) if row else None


@router.get("/transactions")
async def get_transactions(
    material_id: Optional[str] = Query(None),
    warehouse_type: Optional[str] = Query(None),
    from_: Optional[str] = Query(None, alias="from"),
    to: Optional[str] = Query(None),
    limit: int = Query(100),
):
    pool = await get_pool()
    conditions = ["1=1"]
    params = []
    i = 1
    if material_id:
        conditions.append(f"it.material_id=${i}"); params.append(material_id); i += 1
    if warehouse_type:
        conditions.append(f"it.warehouse_type=${i}"); params.append(warehouse_type); i += 1
    if from_:
        conditions.append(f"it.created_at>=${i}"); params.append(from_); i += 1
    if to:
        conditions.append(f"it.created_at<=${i}"); params.append(to); i += 1
    params.append(limit)
    query = f"""
        SELECT it.*, r.name AS material_name, r.unit
        FROM inventory_transactions it
        LEFT JOIN raw_materials r ON r.id = it.material_id
        WHERE {' AND '.join(conditions)}
        ORDER BY it.created_at DESC
        LIMIT ${i}
    """
    rows = await pool.fetch(query, *params)
    return [dict(r) for r in rows]


# ─────────────────────── POST endpoints ─────────────────────────

@router.post("/balance")
async def update_balance(body: BalanceUpdate):
    """Admin override: set absolute balance + log the adjustment."""
    pool = await get_pool()

    inv = await pool.fetchrow(
        "SELECT balance FROM inventory WHERE material_id=$1 AND warehouse_type=$2",
        body.material_id, body.warehouse_type,
    )
    balance_before = float(inv["balance"]) if inv else 0.0

    row = await pool.fetchrow(
        """INSERT INTO inventory (id, material_id, warehouse_type, balance, updated_at)
           VALUES (gen_random_uuid(), $1, $2, $3, NOW())
           ON CONFLICT (material_id, warehouse_type)
           DO UPDATE SET balance=$3, updated_at=NOW()
           RETURNING *""",
        body.material_id, body.warehouse_type, body.balance,
    )

    # Log adjustment transaction
    diff = body.balance - balance_before
    if diff != 0:
        tx_type = "adjustment" if diff > 0 else "adjustment"
        await pool.execute(
            """INSERT INTO inventory_transactions
               (id, material_id, warehouse_type, transaction_type, quantity,
                created_by, notes, balance_before, balance_after)
               VALUES (gen_random_uuid(), $1, $2, $3, $4, $5, $6, $7, $8)""",
            body.material_id, body.warehouse_type, tx_type, abs(diff),
            body.created_by, body.reason or "تعديل رصيد يدوي",
            balance_before, body.balance,
        )

    return dict(row)


@router.post("/transfer")
async def transfer_inventory(body: TransferRequest):
    """Transfer material from one warehouse to another.

    Default: main → mixer (تحويل للخلاط).
    Deducts from source, adds to destination, logs both transactions.
    Raises 400 if source balance is insufficient.
    """
    pool = await get_pool()

    if body.quantity <= 0:
        raise HTTPException(status_code=400, detail="الكمية يجب أن تكون أكبر من صفر")

    from_wh = body.from_warehouse or "main"
    to_wh = body.to_warehouse or "mixer"

    # Check source balance
    src = await pool.fetchrow(
        "SELECT balance FROM inventory WHERE material_id=$1 AND warehouse_type=$2",
        body.material_id, from_wh,
    )
    src_balance = float(src["balance"]) if src else 0.0

    setting = await pool.fetchrow("SELECT value FROM settings WHERE key='prevent_negative_stock'")
    prevent_neg = (setting["value"] if setting else "true").lower() == "true"

    if prevent_neg and src_balance < body.quantity:
        raise HTTPException(
            status_code=400,
            detail={
                "error": "insufficient_stock",
                "message": f"رصيد المخزن ({from_wh}) غير كافٍ: متاح {src_balance:.3f} كجم، مطلوب {body.quantity:.3f} كجم",
                "available": src_balance,
            },
        )

    # Deduct from source
    new_src = src_balance - body.quantity
    await pool.execute(
        """INSERT INTO inventory (id, material_id, warehouse_type, balance, updated_at)
           VALUES (gen_random_uuid(), $1, $2, $3, NOW())
           ON CONFLICT (material_id, warehouse_type)
           DO UPDATE SET balance = inventory.balance - $4, updated_at = NOW()""",
        body.material_id, from_wh, new_src, body.quantity,
    )

    # Add to destination
    dst = await pool.fetchrow(
        "SELECT balance FROM inventory WHERE material_id=$1 AND warehouse_type=$2",
        body.material_id, to_wh,
    )
    dst_balance = float(dst["balance"]) if dst else 0.0
    new_dst = dst_balance + body.quantity

    await pool.execute(
        """INSERT INTO inventory (id, material_id, warehouse_type, balance, updated_at)
           VALUES (gen_random_uuid(), $1, $2, $3, NOW())
           ON CONFLICT (material_id, warehouse_type)
           DO UPDATE SET balance = inventory.balance + $4, updated_at = NOW()""",
        body.material_id, to_wh, new_dst, body.quantity,
    )

    import uuid
    tx_ref = str(uuid.uuid4())

    # Log source transaction (out)
    await pool.execute(
        """INSERT INTO inventory_transactions
           (id, material_id, warehouse_type, transaction_type, quantity,
            transaction_ref, created_by, notes, balance_before, balance_after)
           VALUES (gen_random_uuid(), $1, $2, 'transfer_out', $3, $4, $5, $6, $7, $8)""",
        body.material_id, from_wh, body.quantity, tx_ref,
        body.created_by, body.notes or f"تحويل من {from_wh} إلى {to_wh}",
        src_balance, new_src,
    )

    # Log destination transaction (in)
    await pool.execute(
        """INSERT INTO inventory_transactions
           (id, material_id, warehouse_type, transaction_type, quantity,
            transaction_ref, created_by, notes, balance_before, balance_after)
           VALUES (gen_random_uuid(), $1, $2, 'transfer_in', $3, $4, $5, $6, $7, $8)""",
        body.material_id, to_wh, body.quantity, tx_ref,
        body.created_by, body.notes or f"تحويل من {from_wh} إلى {to_wh}",
        dst_balance, new_dst,
    )

    await pool.execute(
        """INSERT INTO audit_log
           (id, action, table_name, description)
           VALUES (gen_random_uuid(), 'transfer', 'inventory', $1)""",
        f"تحويل {body.quantity} كجم من {from_wh} إلى {to_wh}",
    )

    rm = await pool.fetchrow("SELECT name, unit FROM raw_materials WHERE id=$1", body.material_id)
    return {
        "success": True,
        "material_name": rm["name"] if rm else "",
        "quantity": body.quantity,
        "from_warehouse": from_wh,
        "to_warehouse": to_wh,
        "src_balance_after": new_src,
        "dst_balance_after": new_dst,
        "transaction_ref": tx_ref,
    }


@router.post("/transactions")
async def add_transaction(body: TransactionCreate):
    """Manual transaction entry — updates inventory balance accordingly."""
    pool = await get_pool()

    inv = await pool.fetchrow(
        "SELECT balance FROM inventory WHERE material_id=$1 AND warehouse_type=$2",
        body.material_id, body.warehouse_type,
    )
    balance_before = float(inv["balance"]) if inv else 0.0

    qty_signed = body.quantity if body.transaction_type == "in" else -body.quantity
    balance_after = balance_before + qty_signed

    await pool.execute(
        """INSERT INTO inventory (id, material_id, warehouse_type, balance, updated_at)
           VALUES (gen_random_uuid(), $1, $2, $3, NOW())
           ON CONFLICT (material_id, warehouse_type)
           DO UPDATE SET balance = inventory.balance + $4, updated_at = NOW()""",
        body.material_id, body.warehouse_type, balance_after, qty_signed,
    )

    row = await pool.fetchrow(
        """INSERT INTO inventory_transactions
           (id, material_id, warehouse_type, transaction_type, quantity,
            batch_id, production_id, transaction_ref, created_by, notes,
            balance_before, balance_after)
           VALUES (gen_random_uuid(), $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
           RETURNING *""",
        body.material_id, body.warehouse_type, body.transaction_type, body.quantity,
        body.batch_id, body.production_id, body.transaction_ref, body.created_by,
        body.notes, balance_before, balance_after,
    )
    return dict(row)
