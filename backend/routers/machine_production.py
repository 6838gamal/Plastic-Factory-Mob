"""
Machine Production router.

Rules:
 - When production is saved:
     * scrap_quantity → added to scrap material inventory (warehouse_type='mixer')
     * industrial deviation alert raised when |outputs - inputs| / inputs > threshold
     * Auto 11: if projected deviation > notes_threshold AND notes is empty → HTTP 400
     * yield_deviation alert raised when actual_gram_per_pair > standard_gram_per_pair
 - Edit reverses scrap additions before applying new ones.
 - Delete reverses scrap additions.
 - Every change is written to audit_log.
 - After save/edit: daily report is regenerated in the background (Auto 5).
"""
import asyncio
import json
from fastapi import APIRouter, Query, HTTPException
from pydantic import BaseModel
from typing import Optional
from database import get_pool

router = APIRouter(prefix="/api/machine-production", tags=["machine_production"])

DEVIATION_ALERT_THRESHOLD = 2.0   # % — alert when industrial deviation exceeds ±2%
DEVIATION_NOTES_THRESHOLD = 5.0  # % — require notes when deviation exceeds ±5%

_GRAM_UNITS = {"جرام", "gram", "g", "غرام", "gm"}


def _to_kg(qty: float, unit: str) -> float:
    """Convert quantity to kg. Gram units ÷ 1000."""
    if unit and unit.strip().lower() in _GRAM_UNITS:
        return qty / 1000.0
    return qty


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
    # ── Yield standard fields ────────────────────────────────
    standard_id: Optional[str] = None
    pairs_produced: Optional[int] = None


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
        "SELECT balance FROM inventory WHERE material_id=$1::uuid AND warehouse_type='mixer'",
        scrap_mid,
    )
    balance_before = float(inv["balance"]) if inv else 0.0
    balance_after = balance_before + scrap_qty

    await pool.execute(
        """INSERT INTO inventory (id, material_id, warehouse_type, balance, updated_at)
           VALUES (gen_random_uuid(), $1::uuid, 'mixer', $2, NOW())
           ON CONFLICT (material_id, warehouse_type)
           DO UPDATE SET balance = inventory.balance + $2, updated_at = NOW()""",
        scrap_mid, scrap_qty,
    )

    await pool.execute(
        """INSERT INTO inventory_transactions
           (id, material_id, warehouse_type, transaction_type, quantity,
            production_id, transaction_ref, created_by, notes, balance_before, balance_after)
           VALUES (gen_random_uuid(), $1::uuid, 'mixer', 'in', $2, $3, $4, $5,
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
           WHERE material_id = $2::uuid AND warehouse_type = 'mixer'""",
        scrap_qty, scrap_mid,
    )
    await pool.execute(
        """DELETE FROM inventory_transactions
           WHERE production_id = $1 AND transaction_type = 'in'
             AND notes = 'راجع من الإنتاج'""",
        production_id,
    )


async def _get_notes_threshold(pool) -> float:
    """Fetch deviation_notes_threshold from settings."""
    row = await pool.fetchrow("SELECT value FROM settings WHERE key='deviation_notes_threshold'")
    try:
        return float(row["value"]) if row and row["value"] else DEVIATION_NOTES_THRESHOLD
    except (ValueError, TypeError):
        return DEVIATION_NOTES_THRESHOLD


async def _get_alert_threshold(pool) -> float:
    """Fetch deviation_alert_threshold from settings."""
    row = await pool.fetchrow("SELECT value FROM settings WHERE key='deviation_alert_threshold'")
    try:
        return float(row["value"]) if row and row["value"] else DEVIATION_ALERT_THRESHOLD
    except (ValueError, TypeError):
        return DEVIATION_ALERT_THRESHOLD


def _compute_batch_total_inputs(batch_row) -> float:
    """Compute total_inputs_kg from a batch DB row."""
    def to_f(v): return float(v or 0)
    pvc       = to_f(batch_row["pvc_qty"])
    dop       = to_f(batch_row["dop_qty"])
    scrap_b   = to_f(batch_row["scrap_qty"])
    calcium   = to_f(batch_row["calcium_qty"])
    wax       = to_f(batch_row["wax_qty"])
    stabilizer = to_f(batch_row["stabilizer_qty"])
    titanium  = to_f(batch_row["titanium_qty"])

    dynamic = 0.0
    for field in ("materials", "pigments", "additives"):
        raw = batch_row[field]
        if isinstance(raw, str):
            try:
                raw = json.loads(raw)
            except Exception:
                raw = []
        if raw:
            for item in raw:
                if isinstance(item, dict):
                    qty_raw = float(item.get("quantity", 0) or 0)
                    unit = item.get("unit", "كجم")
                    dynamic += _to_kg(qty_raw, unit)

    return pvc + dop + scrap_b + calcium + wax + stabilizer + titanium + dynamic


async def _check_notes_required(pool, batch_number: str, body: ProductionCreate,
                                 exclude_production_id: str = None):
    """
    Auto 11 — Pre-check: if projected deviation > notes_threshold and notes are empty → raise 400.
    """
    if not batch_number:
        return

    notes_threshold = await _get_notes_threshold(pool)
    notes = (body.notes or "").strip()

    batch = await pool.fetchrow("SELECT * FROM batches WHERE batch_number=$1", batch_number)
    if not batch:
        return

    total_inputs = _compute_batch_total_inputs(batch)
    if total_inputs <= 0:
        return

    conditions = ["batch_number=$1"]
    params = [batch_number]
    if exclude_production_id:
        conditions.append("id!=$2")
        params.append(exclude_production_id)

    prod = await pool.fetchrow(
        f"""SELECT
              COALESCE(SUM(produced_quantity),0) AS total_produced,
              COALESCE(SUM(scrap_quantity),0)    AS total_scrap,
              COALESCE(SUM(waste_quantity),0)    AS total_waste
            FROM machine_production
            WHERE {' AND '.join(conditions)}""",
        *params,
    )

    existing_outputs = (
        float(prod["total_produced"] or 0) +
        float(prod["total_scrap"] or 0) +
        float(prod["total_waste"] or 0)
    )

    new_outputs = (
        float(body.produced_quantity or 0) +
        float(body.scrap_quantity or 0) +
        float(body.waste_quantity or 0)
    )

    projected_outputs = existing_outputs + new_outputs
    deviation = projected_outputs - total_inputs
    deviation_pct = abs(deviation / total_inputs * 100)

    if deviation_pct > notes_threshold and not notes:
        direction = "زيادة" if deviation > 0 else "نقص"
        raise HTTPException(
            status_code=400,
            detail={
                "error": "notes_required",
                "message": (
                    f"الانحراف الصناعي كبير ({deviation_pct:.1f}% — {direction}). "
                    f"يجب إدخال ملاحظة تفسيرية قبل الحفظ."
                ),
                "deviation_pct": round(deviation_pct, 2),
                "threshold": notes_threshold,
            },
        )


async def _check_industrial_deviation(pool, batch_number: str, production_id: str):
    """Compare batch total_inputs vs total_outputs and raise alert if threshold exceeded."""
    if not batch_number:
        return

    batch = await pool.fetchrow("SELECT * FROM batches WHERE batch_number=$1", batch_number)
    if not batch:
        return

    total_inputs = _compute_batch_total_inputs(batch)

    prod = await pool.fetchrow(
        """SELECT
             COALESCE(SUM(produced_quantity),0) AS total_produced,
             COALESCE(SUM(scrap_quantity),0)    AS total_scrap,
             COALESCE(SUM(waste_quantity),0)    AS total_waste
           FROM machine_production WHERE batch_number=$1""",
        batch_number,
    )
    total_outputs = (
        float(prod["total_produced"]) +
        float(prod["total_scrap"]) +
        float(prod["total_waste"])
    )

    if total_inputs <= 0:
        return

    deviation = total_outputs - total_inputs
    deviation_pct = abs(deviation / total_inputs * 100)

    alert_threshold = await _get_alert_threshold(pool)
    notes_threshold = await _get_notes_threshold(pool)

    if deviation_pct > alert_threshold:
        direction = "زيادة" if deviation > 0 else "نقص"
        severity = "critical" if deviation_pct > notes_threshold else "high"
        description = (
            f"انحراف صناعي {direction} في طبخة {batch_number}: "
            f"المدخلات {total_inputs:.1f} كجم — المخرجات {total_outputs:.1f} كجم "
            f"(انحراف {deviation_pct:.1f}%)"
        )
        if deviation_pct > notes_threshold:
            description += " ⚠ يلزم إضافة ملاحظة تفسيرية"

        await pool.execute(
            """INSERT INTO alerts
               (id, alert_type, severity, batch_number, description, status, transaction_id)
               VALUES (gen_random_uuid(), 'industrial_deviation', $1, $2, $3, 'pending', $4)
               ON CONFLICT (transaction_id) WHERE transaction_id IS NOT NULL DO NOTHING""",
            severity, batch_number, description, f"deviat_{production_id}",
        )
        await pool.execute(
            """INSERT INTO audit_log
               (id, action, table_name, record_id, description)
               VALUES (gen_random_uuid(), 'alert', 'machine_production', $1, $2)""",
            production_id,
            f"انحراف صناعي {deviation_pct:.1f}% في طبخة {batch_number}" +
            (" — يلزم ملاحظة" if deviation_pct > notes_threshold else ""),
        )


async def _compute_yield_stats(pool, body: ProductionCreate):
    """
    Compute yield stats based on standard.
    Returns (actual_gram_per_pair, standard_gram_per_pair, deviation_pct, indicator)
    or (actual_gram, None, None, None) if no standard set.
    """
    pairs = body.pairs_produced
    if not pairs or pairs <= 0:
        return None, None, None, None

    total_kg = (
        float(body.produced_quantity or 0) +
        float(body.scrap_quantity or 0) +
        float(body.waste_quantity or 0)
    )
    actual_gram = (total_kg * 1000.0) / pairs

    if not body.standard_id:
        return actual_gram, None, None, None

    try:
        std_row = await pool.fetchrow(
            "SELECT standard_gram_per_pair FROM production_standards WHERE id=$1::uuid",
            body.standard_id,
        )
    except Exception as exc:
        print(f"[yield_stats] Failed to look up standard id={body.standard_id}: {exc}")
        return actual_gram, None, None, None

    if not std_row:
        return actual_gram, None, None, None

    standard_gram = float(std_row["standard_gram_per_pair"])
    deviation_pct = ((actual_gram - standard_gram) / standard_gram) * 100

    if deviation_pct <= 0:
        indicator = "normal"
    elif deviation_pct <= 5:
        indicator = "warning"
    else:
        indicator = "critical"

    return actual_gram, standard_gram, deviation_pct, indicator


async def _create_yield_deviation_alert(
    pool, production_id: str, body: ProductionCreate,
    actual_gram: float, standard_gram: float,
    deviation_pct: float, indicator: str,
):
    """Create a yield_deviation alert when actual consumption exceeds standard."""
    if deviation_pct is None or deviation_pct <= 0:
        return
    severity = "critical" if indicator == "critical" else "high"
    description = (
        f"انحراف معيار الإنتاج — صنف: {body.product_name or ''} | "
        f"ماكينة: {body.machine_name or ''} | "
        f"المعيار: {standard_gram:.0f} جرام/زوج | "
        f"الفعلي: {actual_gram:.0f} جرام/زوج | "
        f"الانحراف: +{deviation_pct:.1f}%"
    )
    try:
        await pool.execute(
            """INSERT INTO alerts
               (id, alert_type, severity, machine_id, machine_name, worker_name,
                description, status, transaction_id)
               VALUES (gen_random_uuid(), 'yield_deviation', $1, $2, $3, $4, $5, 'pending', $6)
               ON CONFLICT (transaction_id) WHERE transaction_id IS NOT NULL DO NOTHING""",
            severity, body.machine_id, body.machine_name, body.worker_name,
            description, f"yield_{production_id}",
        )
    except Exception as exc:
        print(f"[yield_alert] Failed to create yield deviation alert: {exc}")


async def _refresh_daily_report(date_str: str):
    """Auto 5 — Regenerate today's daily report snapshot in the background (non-locking)."""
    try:
        from datetime import date as _date
        pool = await get_pool()
        target = _date.fromisoformat(date_str)
        existing = await pool.fetchrow(
            "SELECT is_locked FROM daily_reports WHERE report_date=$1", target
        )
        if existing and existing["is_locked"]:
            return  # Never touch a locked report
        from routers.reports import generate_daily_report
        await generate_daily_report(report_date=date_str, lock=False)
    except Exception as exc:
        print(f"[auto5] Daily report refresh failed for {date_str}: {exc}")


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

    # ── Auto 11: Enforce notes when deviation is large ────────
    await _check_notes_required(pool, body.batch_number, body)

    # ── Compute yield stats ───────────────────────────────────
    actual_gram, standard_gram, deviation_pct, indicator = await _compute_yield_stats(pool, body)

    row = await pool.fetchrow(
        """INSERT INTO machine_production (
            id, batch_number, machine_id, machine_name, product_id, product_name,
            worker_id, worker_name, produced_quantity, scrap_quantity, waste_quantity,
            stop_time_minutes, notes, production_image_url, transaction_id, status,
            standard_id, pairs_produced, actual_gram_per_pair, standard_gram_per_pair,
            deviation_from_standard_pct, waste_indicator
        ) VALUES (gen_random_uuid(), $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15,
                  $16, $17, $18, $19, $20, $21)
        RETURNING *""",
        body.batch_number, body.machine_id, body.machine_name,
        body.product_id, body.product_name, body.worker_id, body.worker_name,
        body.produced_quantity, body.scrap_quantity, body.waste_quantity,
        body.stop_time_minutes, body.notes, body.production_image_url,
        body.transaction_id, body.status,
        body.standard_id, body.pairs_produced,
        actual_gram, standard_gram, deviation_pct, indicator,
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

    # ── Industrial deviation check + alert ────────────────────
    await _check_industrial_deviation(pool, body.batch_number, production_id)

    # ── Yield deviation alert ─────────────────────────────────
    if actual_gram is not None and standard_gram is not None and deviation_pct is not None:
        await _create_yield_deviation_alert(
            pool, production_id, body,
            actual_gram, standard_gram, deviation_pct, indicator,
        )

    # ── Auto 5: Refresh daily report in background ────────────
    from datetime import date
    asyncio.create_task(_refresh_daily_report(str(date.today())))

    return dict(row)


@router.put("/{production_id}")
async def update_production(production_id: str, body: ProductionCreate):
    pool = await get_pool()

    # ── Auto 11: Enforce notes when deviation is large ────────
    await _check_notes_required(pool, body.batch_number, body,
                                 exclude_production_id=production_id)

    # ── Fetch existing record (patch semantics for yield fields) ──
    existing = await pool.fetchrow(
        """SELECT scrap_quantity, standard_id, pairs_produced,
                  actual_gram_per_pair, deviation_from_standard_pct
           FROM machine_production WHERE id=$1""",
        production_id,
    )
    if not existing:
        raise HTTPException(status_code=404, detail="Production record not found")

    # Fall back to stored yield inputs when caller doesn't provide them
    effective_standard_id = body.standard_id if body.standard_id is not None \
        else existing["standard_id"]
    effective_pairs = body.pairs_produced if body.pairs_produced is not None \
        else (existing["pairs_produced"] or 0)

    # Reverse old scrap addition
    await _remove_scrap_from_inventory(
        pool, production_id, float(existing["scrap_quantity"] or 0)
    )

    # ── Recompute yield stats using effective (possibly carried-over) inputs ──
    class _EffectiveBody:
        """Thin wrapper so _compute_yield_stats sees the right standard/pairs."""
        def __init__(self, b, sid, pairs):
            self.__dict__.update(vars(b) if hasattr(b, '__dict__') else b.model_dump())
            self.standard_id = sid
            self.pairs_produced = pairs

    effective_body = _EffectiveBody(body, effective_standard_id, effective_pairs)
    actual_gram, standard_gram, deviation_pct, indicator = \
        await _compute_yield_stats(pool, effective_body)

    row = await pool.fetchrow(
        """UPDATE machine_production SET
            produced_quantity=$1, scrap_quantity=$2, waste_quantity=$3,
            stop_time_minutes=$4, notes=$5, status=$6,
            standard_id=$7, pairs_produced=$8,
            actual_gram_per_pair=$9, standard_gram_per_pair=$10,
            deviation_from_standard_pct=$11, waste_indicator=$12,
            updated_at=NOW()
           WHERE id=$13 RETURNING *""",
        body.produced_quantity, body.scrap_quantity, body.waste_quantity,
        body.stop_time_minutes, body.notes, body.status or "saved",
        effective_standard_id, effective_pairs,
        actual_gram, standard_gram, deviation_pct, indicator,
        production_id,
    )

    # Add new scrap to inventory
    new_scrap = float(body.scrap_quantity or 0)
    if new_scrap > 0:
        await _add_scrap_to_inventory(
            pool, production_id, body.batch_number or "",
            new_scrap, f"update_{production_id}", body.created_by,
        )

    await pool.execute(
        """INSERT INTO audit_log
           (id, action, table_name, record_id, transaction_id, user_id, description)
           VALUES (gen_random_uuid(),'update','machine_production',$1,$2,$3,$4)""",
        production_id, body.transaction_id, body.created_by,
        f"تعديل إنتاج ماكينة {body.machine_name or ''} — طبخة {body.batch_number or ''}",
    )

    await _check_industrial_deviation(pool, str(row["batch_number"]), production_id)

    # ── Yield alert: only touch when yield inputs actually changed ────
    old_deviation = existing["deviation_from_standard_pct"]
    old_gram = existing["actual_gram_per_pair"]
    yield_inputs_changed = (
        effective_standard_id != existing["standard_id"]
        or effective_pairs != (existing["pairs_produced"] or 0)
        or actual_gram != (float(old_gram) if old_gram is not None else None)
    )
    if yield_inputs_changed:
        try:
            await pool.execute(
                "DELETE FROM alerts WHERE transaction_id=$1",
                f"yield_{production_id}",
            )
        except Exception:
            pass
        if actual_gram is not None and standard_gram is not None and deviation_pct is not None:
            await _create_yield_deviation_alert(
                pool, production_id, effective_body,
                actual_gram, standard_gram, deviation_pct, indicator,
            )

    # ── Auto 5: Refresh daily report in background ────────────
    from datetime import date
    asyncio.create_task(_refresh_daily_report(str(date.today())))

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

    # Remove yield alert
    try:
        await pool.execute(
            "DELETE FROM alerts WHERE transaction_id=$1",
            f"yield_{production_id}",
        )
    except Exception:
        pass

    await pool.execute("DELETE FROM machine_production WHERE id=$1", production_id)

    # ── Auto 5: Refresh daily report in background ────────────
    from datetime import date
    asyncio.create_task(_refresh_daily_report(str(date.today())))

    return {"success": True}
