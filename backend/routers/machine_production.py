"""
Machine Production router.

Rules:
 - When production is saved:
     * scrap_quantity → added to scrap material inventory (warehouse_type='mixer')
     * industrial deviation alert raised when |outputs - inputs| / inputs > threshold
 - Edit reverses scrap additions before applying new ones.
 - Delete reverses scrap additions.
 - Every change is written to audit_log.
"""
from fastapi import APIRouter, Query, HTTPException
from pydantic import BaseModel
from typing import Optional
from database import get_pool

router = APIRouter(prefix="/api/machine-production", tags=["machine_production"])

DEVIATION_ALERT_THRESHOLD = 2.0  # % — alert when industrial deviation exceeds ±2%


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
    created_by: Optional[str] = None


# ─────────────────────── helpers ────────────────────────────────

async def _get_scrap_material_id(pool) -> Optional[str]:
    """Return the scrap raw_material id from settings."""
    row = await pool.fetchrow("SELECT value FROM settings WHERE key='scrap_material_id'")
    return row["value"] if row and row["value"] else None


async def _add_scrap_to_inventory(pool, production_id: str, batch_number: str,
                                   scrap_qty: float, transaction_id: str,
                                   created_by: str = None):
    """Add scrap_qty to the scrap material inventory (mixer warehouse)."""
    scrap_mid = await _get_scrap_material_id(pool)
    if not scrap_mid or scrap_qty <= 0:
        return

    inv = await pool.fetchrow(
        "SELECT balance FROM inventory WHERE material_id=$1 AND warehouse_type='mixer'",
        scrap_mid,
    )
    balance_before = float(inv["balance"]) if inv else 0.0
    balance_after = balance_before + scrap_qty

    await pool.execute(
        """INSERT INTO inventory (id, material_id, warehouse_type, balance, updated_at)
           VALUES (gen_random_uuid(), $1, 'mixer', $2, NOW())
           ON CONFLICT (material_id, warehouse_type)
           DO UPDATE SET balance = inventory.balance + $2, updated_at = NOW()""",
        scrap_mid, scrap_qty,
    )

    await pool.execute(
        """INSERT INTO inventory_transactions
           (id, material_id, warehouse_type, transaction_type, quantity,
            production_id, transaction_ref, created_by, notes, balance_before, balance_after)
           VALUES (gen_random_uuid(), $1, 'mixer', 'in', $2, $3, $4, $5,
                   'راجع من الإنتاج', $6, $7)""",
        scrap_mid, scrap_qty, production_id,
        f"scrap_{transaction_id}", created_by, balance_before, balance_after,
    )


async def _remove_scrap_from_inventory(pool, production_id: str, scrap_qty: float):
    """Reverse scrap addition when production is edited/deleted."""
    scrap_mid = await _get_scrap_material_id(pool)
    if not scrap_mid or scrap_qty <= 0:
        return
    await pool.execute(
        """UPDATE inventory
           SET balance = GREATEST(balance - $1, 0), updated_at = NOW()
           WHERE material_id = $2 AND warehouse_type = 'mixer'""",
        scrap_qty, scrap_mid,
    )
    await pool.execute(
        """DELETE FROM inventory_transactions
           WHERE production_id = $1 AND transaction_type = 'in'
             AND notes = 'راجع من الإنتاج'""",
        production_id,
    )


async def _check_industrial_deviation(pool, batch_number: str, production_id: str):
    """Compare batch total_inputs vs total_outputs and raise alert if threshold exceeded."""
    if not batch_number:
        return

    # Get batch total inputs
    batch = await pool.fetchrow("SELECT * FROM batches WHERE batch_number=$1", batch_number)
    if not batch:
        return

    def to_f(v): return float(v or 0)

    pvc = to_f(batch["pvc_qty"])
    dop = to_f(batch["dop_qty"])
    scrap_b = to_f(batch["scrap_qty"])
    calcium = to_f(batch["calcium_qty"])
    wax = to_f(batch["wax_qty"])
    stabilizer = to_f(batch["stabilizer_qty"])
    titanium = to_f(batch["titanium_qty"])

    import json
    dynamic = 0.0
    for field in ("materials", "pigments", "additives"):
        raw = batch[field]
        if isinstance(raw, str):
            try:
                raw = json.loads(raw)
            except Exception:
                raw = []
        if raw:
            for item in raw:
                if isinstance(item, dict):
                    dynamic += float(item.get("quantity", 0) or 0)

    total_inputs = pvc + dop + scrap_b + calcium + wax + stabilizer + titanium + dynamic

    # Get all machine production for this batch
    prod = await pool.fetchrow(
        """SELECT
             COALESCE(SUM(produced_quantity),0) AS total_produced,
             COALESCE(SUM(scrap_quantity),0)    AS total_scrap,
             COALESCE(SUM(waste_quantity),0)    AS total_waste
           FROM machine_production WHERE batch_number=$1""",
        batch_number,
    )
    total_outputs = (
        to_f(prod["total_produced"]) +
        to_f(prod["total_scrap"]) +
        to_f(prod["total_waste"])
    )

    if total_inputs <= 0:
        return

    deviation = total_outputs - total_inputs
    deviation_pct = abs(deviation / total_inputs * 100)

    if deviation_pct > DEVIATION_ALERT_THRESHOLD:
        direction = "زيادة" if deviation > 0 else "نقص"
        await pool.execute(
            """INSERT INTO alerts
               (id, alert_type, severity, batch_number, description, status, transaction_id)
               VALUES (gen_random_uuid(), 'industrial_deviation', 'high', $1, $2, 'pending', $3)
               ON CONFLICT DO NOTHING""",
            batch_number,
            f"انحراف صناعي {direction} في طبخة {batch_number}: "
            f"المدخلات {total_inputs:.1f} كجم — المخرجات {total_outputs:.1f} كجم "
            f"(انحراف {deviation_pct:.1f}%)",
            f"deviat_{production_id}",
        )
        await pool.execute(
            """INSERT INTO audit_log
               (id, action, table_name, record_id, description)
               VALUES (gen_random_uuid(), 'alert', 'machine_production', $1, $2)""",
            production_id,
            f"انحراف صناعي {deviation_pct:.1f}% في طبخة {batch_number}",
        )


# ─────────────────────── routes ─────────────────────────────────

@router.get("")
async def get_productions(
    from_: Optional[str] = Query(None, alias="from"),
    to: Optional[str] = Query(None),
    machine_id: Optional[str] = Query(None),
    batch_number: Optional[str] = Query(None),
):
    pool = await get_pool()
    conditions = ["1=1"]
    params = []
    i = 1
    if from_:
        from datetime import datetime as dt
        conditions.append(f"created_at>=${i}")
        params.append(dt.fromisoformat(from_.replace("Z", ""))); i += 1
    if to:
        from datetime import datetime as dt
        conditions.append(f"created_at<=${i}")
        params.append(dt.fromisoformat(to.replace("Z", ""))); i += 1
    if machine_id:
        conditions.append(f"machine_id=${i}"); params.append(machine_id); i += 1
    if batch_number:
        conditions.append(f"batch_number=${i}"); params.append(batch_number); i += 1
    query = f"SELECT * FROM machine_production WHERE {' AND '.join(conditions)} ORDER BY created_at DESC"
    rows = await pool.fetch(query, *params)
    return [dict(r) for r in rows]


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
    production_id = str(row["id"])

    # ── Add scrap to inventory ────────────────────────────────
    scrap_qty = float(body.scrap_quantity or 0)
    if scrap_qty > 0:
        await _add_scrap_to_inventory(
            pool, production_id, body.batch_number or "",
            scrap_qty, body.transaction_id or production_id,
            body.created_by,
        )

    # ── Audit ─────────────────────────────────────────────────
    await pool.execute(
        """INSERT INTO audit_log
           (id, action, table_name, record_id, transaction_id, user_id, description)
           VALUES (gen_random_uuid(),'create','machine_production',$1,$2,$3,$4)""",
        production_id, body.transaction_id, body.created_by,
        f"إنتاج ماكينة {body.machine_name or ''} — طبخة {body.batch_number or ''}",
    )

    # ── Industrial deviation check ────────────────────────────
    await _check_industrial_deviation(pool, body.batch_number, production_id)

    return dict(row)


@router.put("/{production_id}")
async def update_production(production_id: str, body: ProductionCreate):
    pool = await get_pool()

    # Reverse old scrap addition
    old = await pool.fetchrow(
        "SELECT scrap_quantity FROM machine_production WHERE id=$1", production_id
    )
    if old:
        await _remove_scrap_from_inventory(pool, production_id, float(old["scrap_quantity"] or 0))

    row = await pool.fetchrow(
        """UPDATE machine_production SET
            produced_quantity=$1, scrap_quantity=$2, waste_quantity=$3,
            stop_time_minutes=$4, notes=$5, status=$6, updated_at=NOW()
           WHERE id=$7 RETURNING *""",
        body.produced_quantity, body.scrap_quantity, body.waste_quantity,
        body.stop_time_minutes, body.notes, body.status or "saved", production_id,
    )
    if not row:
        raise HTTPException(status_code=404, detail="Production record not found")

    # Add new scrap to inventory
    new_scrap = float(body.scrap_quantity or 0)
    if new_scrap > 0:
        await _add_scrap_to_inventory(
            pool, production_id, body.batch_number or "",
            new_scrap, f"update_{production_id}", body.created_by,
        )

    await _check_industrial_deviation(pool, str(row["batch_number"]), production_id)
    return dict(row)


@router.delete("/{production_id}")
async def delete_production(production_id: str):
    pool = await get_pool()
    old = await pool.fetchrow(
        "SELECT scrap_quantity FROM machine_production WHERE id=$1", production_id
    )
    if old:
        await _remove_scrap_from_inventory(pool, production_id, float(old["scrap_quantity"] or 0))

    await pool.execute(
        """INSERT INTO audit_log
           (id, action, table_name, record_id, description)
           VALUES (gen_random_uuid(),'delete','machine_production',$1,$2)""",
        production_id, "حذف سجل إنتاج",
    )
    await pool.execute("DELETE FROM machine_production WHERE id=$1", production_id)
    return {"success": True}
