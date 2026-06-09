"""
Batches router — full deduction engine.

Rules:
 - Transaction ID prevents duplicate deductions.
 - Negative stock is blocked when settings.prevent_negative_stock = 'true'.
 - Edit reverses old deductions then applies new ones atomically.
 - Delete reverses any applied deductions.
 - Every deduction / reversal is written to audit_log and inventory_transactions.
 - Alerts are raised for insufficient stock and post-deduction low/zero stock.
"""
import asyncio
import json
from datetime import date as DateType
from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import Optional, List, Any
from database import get_pool

router = APIRouter(prefix="/api/batches", tags=["batches"])


# ─────────────────────────── Models ────────────────────────────

class BatchCreate(BaseModel):
    batch_number: str
    date: Optional[DateType] = None
    shift: Optional[str] = None
    worker_id: Optional[str] = None
    worker_name: Optional[str] = None
    mixer_id: Optional[str] = None
    mixer_name: Optional[str] = None
    product_id: Optional[str] = None
    product_name: Optional[str] = None
    mixture_type_id: Optional[str] = None
    mixture_type_name: Optional[str] = None
    pvc_qty: Optional[float] = 0
    dop_qty: Optional[float] = 0
    scrap_qty: Optional[float] = 0
    calcium_qty: Optional[float] = 0
    wax_qty: Optional[float] = 0
    stabilizer_qty: Optional[float] = 0
    titanium_qty: Optional[float] = 0
    pigments: Optional[List[Any]] = []
    additives: Optional[List[Any]] = []
    materials: Optional[List[Any]] = []
    notes: Optional[str] = None
    scale_image_url: Optional[str] = None
    transaction_id: Optional[str] = None
    status: Optional[str] = "saved"
    created_by: Optional[str] = None


class BatchUpdate(BatchCreate):
    pass


# ─────────────────────────── Helpers ───────────────────────────

def _parse_json(val) -> list:
    if isinstance(val, str):
        try:
            return json.loads(val) or []
        except Exception:
            return []
    return val or []


def serialize_row(row) -> dict:
    d = dict(row)
    for k in ("pigments", "additives", "materials"):
        if k in d and isinstance(d[k], str):
            try:
                d[k] = json.loads(d[k])
            except Exception:
                pass
    return d


_GRAM_UNITS = {"جرام", "gram", "g", "غرام", "gm"}


def _to_kg(qty: float, unit: str) -> float:
    """Convert quantity to kg. Gram-based units are divided by 1000."""
    if unit and unit.strip().lower() in _GRAM_UNITS:
        return qty / 1000.0
    return qty


def _extract_materials(batch: BatchCreate) -> list:
    """Return a flat list of {material_id, name, quantity_kg, unit} for ALL
    materials in the batch that have a valid material_id and qty > 0.

    Quantities are automatically converted to KG (gram units ÷ 1000).
    """
    items = []
    seen = {}
    for field in ("materials", "pigments", "additives"):
        raw = _parse_json(getattr(batch, field, None))
        for item in raw:
            if not isinstance(item, dict):
                continue
            mid = item.get("material_id") or item.get("id")
            qty_raw = float(item.get("quantity", 0) or 0)
            unit = item.get("unit", "كجم")
            qty_kg = _to_kg(qty_raw, unit)
            if not mid or qty_kg <= 0:
                continue
            # Aggregate duplicates
            if mid in seen:
                seen[mid]["quantity"] += qty_kg
                seen[mid]["quantity_original"] += qty_raw
            else:
                entry = {
                    "material_id": str(mid),
                    "name": item.get("name", ""),
                    "quantity": qty_kg,          # always KG for deduction
                    "quantity_original": qty_raw,
                    "unit": unit,
                }
                seen[mid] = entry
                items.append(entry)
    return items


async def _apply_deductions(pool, batch_id: str, batch_number: str,
                            transaction_id: str, materials: list,
                            created_by: str = None) -> dict:
    """Deduct materials from mixer inventory.

    Returns {"deducted": True/False, "items_count": N, "already_deducted": bool}
    Raises HTTPException 400 when stock is insufficient and prevent_negative=true.
    """
    if not transaction_id:
        return {"deducted": False, "items_count": 0, "already_deducted": False}

    # ── 1. Idempotency check ──────────────────────────────────
    existing = await pool.fetchrow(
        "SELECT id FROM deduction_log WHERE transaction_id=$1 AND reversed_at IS NULL",
        transaction_id,
    )
    if existing:
        return {"deducted": False, "items_count": 0, "already_deducted": True}

    if not materials:
        return {"deducted": False, "items_count": 0, "already_deducted": False}

    # ── 2. Prevent-negative setting ───────────────────────────
    setting = await pool.fetchrow(
        "SELECT value FROM settings WHERE key='prevent_negative_stock'"
    )
    prevent_neg = (setting["value"] if setting else "true").lower() == "true"

    # ── 3. Stock-sufficiency check ────────────────────────────
    if prevent_neg:
        insufficient = []
        for item in materials:
            inv = await pool.fetchrow(
                """SELECT i.balance, rm.min_stock
                   FROM inventory i
                   JOIN raw_materials rm ON rm.id = i.material_id
                   WHERE i.material_id=$1 AND i.warehouse_type='mixer'""",
                item["material_id"],
            )
            available = float(inv["balance"]) if inv else 0.0
            if available < item["quantity"]:
                insufficient.append({**item, "available": available})

        if insufficient:
            for it in insufficient:
                await pool.execute(
                    """INSERT INTO alerts
                       (id, alert_type, severity, material_id, material_name,
                        batch_number, description, status, transaction_id)
                       VALUES (gen_random_uuid(),'insufficient_stock','critical',
                               $1,$2,$3,$4,'pending',$5)""",
                    it["material_id"], it["name"], batch_number,
                    f"مخزون غير كافٍ: {it['name']} — مطلوب {it['quantity']:.3f}، متاح {it['available']:.3f} كجم",
                    transaction_id,
                )
            await pool.execute(
                """INSERT INTO audit_log
                   (id, action, table_name, record_id, transaction_id, user_id, description)
                   VALUES (gen_random_uuid(),'failed','batches',$1,$2,$3,$4)""",
                batch_id, transaction_id, created_by,
                f"رُفض حفظ طبخة {batch_number}: مخزون غير كافٍ",
            )
            raise HTTPException(
                status_code=400,
                detail={
                    "error": "insufficient_stock",
                    "message": "المخزون غير كافٍ لإتمام الطبخة",
                    "items": insufficient,
                },
            )

    # ── 4. Deduct each material ───────────────────────────────
    for item in materials:
        inv = await pool.fetchrow(
            """SELECT i.balance, rm.min_stock
               FROM inventory i
               JOIN raw_materials rm ON rm.id = i.material_id
               WHERE i.material_id=$1 AND i.warehouse_type='mixer'""",
            item["material_id"],
        )
        balance_before = float(inv["balance"]) if inv else 0.0
        min_stock = float(inv["min_stock"]) if inv else 0.0
        balance_after = balance_before - item["quantity"]

        # Upsert inventory row, subtracting qty
        await pool.execute(
            """INSERT INTO inventory (id, material_id, warehouse_type, balance, updated_at)
               VALUES (gen_random_uuid(), $1, 'mixer', -$2::decimal, NOW())
               ON CONFLICT (material_id, warehouse_type)
               DO UPDATE SET balance = inventory.balance - $2::decimal, updated_at = NOW()""",
            item["material_id"], item["quantity"],
        )

        # Transaction record
        await pool.execute(
            """INSERT INTO inventory_transactions
               (id, material_id, warehouse_type, transaction_type, quantity,
                batch_id, transaction_ref, created_by, balance_before, balance_after)
               VALUES (gen_random_uuid(),$1,'mixer','out',$2,$3,$4,$5,$6,$7)""",
            item["material_id"], item["quantity"],
            batch_id, transaction_id, created_by,
            balance_before, balance_after,
        )

        # Low / zero stock alerts
        if balance_after <= 0:
            sev = "critical"
            msg = f"نفاد المخزون: {item['name']} — الرصيد {balance_after:.3f} كجم"
        elif min_stock > 0 and balance_after <= min_stock:
            sev = "high"
            msg = f"مخزون منخفض: {item['name']} — الرصيد {balance_after:.3f} كجم (الحد الأدنى {min_stock:.0f})"
        else:
            sev = None

        if sev:
            alert_type = "out_of_stock" if balance_after <= 0 else "low_stock"
            await pool.execute(
                """INSERT INTO alerts
                   (id, alert_type, severity, material_id, material_name,
                    batch_number, description, status, transaction_id)
                   VALUES (gen_random_uuid(),$1,$2,$3,$4,$5,$6,'pending',$7)""",
                alert_type, sev, item["material_id"], item["name"],
                batch_number, msg, f"stock_{transaction_id}_{item['material_id']}",
            )

    # ── 5. Log deduction ──────────────────────────────────────
    await pool.execute(
        """INSERT INTO deduction_log (id, transaction_id, batch_id, applied_at)
           VALUES (gen_random_uuid(), $1, $2, NOW())""",
        transaction_id, batch_id,
    )

    await pool.execute(
        """INSERT INTO audit_log
           (id, action, table_name, record_id, transaction_id, user_id, description)
           VALUES (gen_random_uuid(),'deduct','batches',$1,$2,$3,$4)""",
        batch_id, transaction_id, created_by,
        f"خصم مواد طبخة {batch_number}: {len(materials)} مادة",
    )

    return {"deducted": True, "items_count": len(materials), "already_deducted": False}


async def _reverse_deductions(pool, transaction_id: str,
                              reason: str = "تعديل طبخة",
                              reversed_by: str = None) -> dict:
    """Reverse all 'out' inventory transactions linked to transaction_id.

    Returns {"reversed": bool, "items_count": int}
    """
    log = await pool.fetchrow(
        "SELECT id FROM deduction_log WHERE transaction_id=$1 AND reversed_at IS NULL",
        transaction_id,
    )
    if not log:
        return {"reversed": False, "items_count": 0}

    txns = await pool.fetch(
        """SELECT * FROM inventory_transactions
           WHERE transaction_ref=$1 AND transaction_type='out'""",
        transaction_id,
    )

    for txn in txns:
        # Add quantity back
        await pool.execute(
            """UPDATE inventory
               SET balance = balance + $1, updated_at = NOW()
               WHERE material_id = $2 AND warehouse_type = $3""",
            txn["quantity"], txn["material_id"], txn["warehouse_type"],
        )
        # Return transaction record
        await pool.execute(
            """INSERT INTO inventory_transactions
               (id, material_id, warehouse_type, transaction_type, quantity,
                transaction_ref, created_by, notes)
               VALUES (gen_random_uuid(),$1,$2,'return',$3,$4,$5,$6)""",
            txn["material_id"], txn["warehouse_type"], txn["quantity"],
            f"reverse_{transaction_id}", reversed_by, reason,
        )

    # Mark log entry reversed
    await pool.execute(
        "UPDATE deduction_log SET reversed_at = NOW(), reversed_reason = $1 WHERE transaction_id = $2",
        reason, transaction_id,
    )

    await pool.execute(
        """INSERT INTO audit_log
           (id, action, table_name, transaction_id, user_id, description)
           VALUES (gen_random_uuid(),'reverse','batches',$1,$2,$3)""",
        transaction_id, reversed_by, reason,
    )

    return {"reversed": True, "items_count": len(txns)}


def _calc_batch_stats(batch_row: dict) -> dict:
    """Compute total inputs from raw batch data (all quantities treated as KG already).

    The fixed-field quantities (pvc_qty, dop_qty …) are stored as KG in the DB.
    The dynamic materials in JSONB may carry a 'unit' field — apply gram→kg if needed.
    """
    pvc       = float(batch_row.get("pvc_qty") or 0)
    dop       = float(batch_row.get("dop_qty") or 0)
    scrap     = float(batch_row.get("scrap_qty") or 0)
    calcium   = float(batch_row.get("calcium_qty") or 0)
    wax       = float(batch_row.get("wax_qty") or 0)
    stabilizer = float(batch_row.get("stabilizer_qty") or 0)
    titanium  = float(batch_row.get("titanium_qty") or 0)

    dynamic_total = 0.0
    for field in ("materials", "pigments", "additives"):
        for item in _parse_json(batch_row.get(field)):
            if isinstance(item, dict):
                qty_raw = float(item.get("quantity", 0) or 0)
                unit = item.get("unit", "كجم")
                dynamic_total += _to_kg(qty_raw, unit)

    total_inputs = pvc + dop + scrap + calcium + wax + stabilizer + titanium + dynamic_total
    return {
        "total_inputs_kg": round(total_inputs, 3),
        "dynamic_materials_kg": round(dynamic_total, 3),
    }


# ─────────────────────────── Routes ────────────────────────────

@router.get("")
async def get_batches(
    from_: Optional[str] = Query(None, alias="from"),
    to: Optional[str] = Query(None),
    worker_id: Optional[str] = Query(None),
    limit: Optional[int] = Query(None),
):
    pool = await get_pool()
    conditions = ["1=1"]
    params = []
    i = 1
    if from_:
        conditions.append(f"date::text>=${i}"); params.append(from_[:10]); i += 1
    if to:
        conditions.append(f"date::text<=${i}"); params.append(to[:10]); i += 1
    if worker_id:
        conditions.append(f"worker_id=${i}"); params.append(worker_id); i += 1
    limit_clause = f" LIMIT {int(limit)}" if limit else ""
    query = f"SELECT * FROM batches WHERE {' AND '.join(conditions)} ORDER BY created_at DESC{limit_clause}"
    rows = await pool.fetch(query, *params)
    result = []
    for r in rows:
        d = serialize_row(r)
        d.update(_calc_batch_stats(d))
        result.append(d)
    return result


@router.get("/check-transaction/{transaction_id}")
async def check_transaction(transaction_id: str):
    pool = await get_pool()
    row = await pool.fetchrow(
        "SELECT id FROM batches WHERE transaction_id=$1", transaction_id
    )
    return {"exists": row is not None}


@router.get("/{batch_id}/stats")
async def get_batch_stats(batch_id: str):
    """Return KPI stats for a single batch including production figures if available."""
    pool = await get_pool()
    batch = await pool.fetchrow("SELECT * FROM batches WHERE id=$1", batch_id)
    if not batch:
        raise HTTPException(status_code=404, detail="Batch not found")

    d = serialize_row(batch)
    stats = _calc_batch_stats(d)

    # Join machine_production to get output quantities
    prod = await pool.fetchrow(
        """SELECT
             COALESCE(SUM(produced_quantity),0) AS total_produced,
             COALESCE(SUM(scrap_quantity),0)    AS total_scrap,
             COALESCE(SUM(waste_quantity),0)    AS total_waste,
             COALESCE(SUM(stop_time_minutes),0) AS total_stop_time
           FROM machine_production
           WHERE batch_number=$1""",
        d.get("batch_number", ""),
    )

    total_inputs   = stats["total_inputs_kg"]
    total_produced = float(prod["total_produced"]) if prod else 0
    total_waste    = float(prod["total_waste"])    if prod else 0
    total_scrap    = float(prod["total_scrap"])    if prod else 0
    total_outputs  = total_produced + total_waste + total_scrap

    production_diff = total_outputs - total_inputs
    efficiency  = (total_produced / total_inputs * 100) if total_inputs > 0 else 0
    deviation   = (production_diff / total_inputs * 100) if total_inputs > 0 else 0
    waste_pct   = (total_waste   / total_inputs * 100) if total_inputs > 0 else 0
    scrap_pct   = (total_scrap   / total_inputs * 100) if total_inputs > 0 else 0

    # ── Batch cost: sum(qty × cost_per_unit) from inventory_transactions ──
    cost_row = await pool.fetchrow(
        """SELECT COALESCE(SUM(it.quantity * COALESCE(rm.cost_per_unit, 0)), 0) AS batch_cost
           FROM inventory_transactions it
           JOIN raw_materials rm ON rm.id = it.material_id
           WHERE it.transaction_ref = $1
             AND it.transaction_type = 'out'""",
        d.get("transaction_id", ""),
    )
    batch_cost = float(cost_row["batch_cost"]) if cost_row else 0.0
    cost_per_kg = round(batch_cost / total_produced, 4) if total_produced > 0 else 0.0

    return {
        **stats,
        "total_produced_kg":  round(total_produced, 3),
        "total_outputs_kg":   round(total_outputs, 3),
        "total_waste_kg":     round(total_waste, 3),
        "total_scrap_kg":     round(total_scrap, 3),
        "total_stop_time_min": float(prod["total_stop_time"]) if prod else 0,
        "production_diff_kg": round(production_diff, 3),
        "efficiency_pct":     round(efficiency, 2),
        "deviation_pct":      round(deviation, 2),
        "waste_pct":          round(waste_pct, 2),
        "scrap_pct":          round(scrap_pct, 2),
        "batch_cost":         round(batch_cost, 2),
        "cost_per_kg":        cost_per_kg,
    }


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
            return
        from routers.reports import generate_daily_report
        await generate_daily_report(report_date=date_str, lock=False)
    except Exception as exc:
        print(f"[auto5] Daily report refresh failed for {date_str}: {exc}")


@router.get("/next-number")
async def get_next_batch_number():
    """
    Return the next auto-incremented batch number in format B-YYYYMM-NNN.
    Looks at existing batch_numbers for the current month and increments.
    """
    from datetime import datetime
    pool = await get_pool()
    prefix = datetime.now().strftime("B-%Y%m-")
    last = await pool.fetchval(
        "SELECT batch_number FROM batches WHERE batch_number LIKE $1 ORDER BY batch_number DESC LIMIT 1",
        f"{prefix}%",
    )
    if last:
        try:
            seq = int(last.rsplit("-", 1)[-1]) + 1
        except (ValueError, IndexError):
            seq = 1
    else:
        seq = 1
    return {"next_number": f"{prefix}{seq:03d}"}


@router.post("")
async def create_batch(body: BatchCreate):
    pool = await get_pool()

    # ── Idempotency: if transaction_id already exists, return existing batch ──
    if body.transaction_id:
        existing = await pool.fetchrow(
            "SELECT * FROM batches WHERE transaction_id=$1", body.transaction_id
        )
        if existing:
            result = serialize_row(existing)
            result.update(_calc_batch_stats(result))
            result["deduction"] = {"deducted": False, "items_count": 0, "already_deducted": True}
            return result

    # ── Insert batch record ────────────────────────────────────
    row = await pool.fetchrow(
        """INSERT INTO batches (
            id, batch_number, date, shift, worker_id, worker_name, mixer_id, mixer_name,
            product_id, product_name, mixture_type_id, mixture_type_name,
            pvc_qty, dop_qty, scrap_qty, calcium_qty, wax_qty, stabilizer_qty, titanium_qty,
            pigments, additives, materials, notes, scale_image_url, transaction_id, status
        ) VALUES (
            gen_random_uuid(),$1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,
            $12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23,$24,$25
        ) RETURNING *""",
        body.batch_number, body.date or DateType.today(), body.shift,
        body.worker_id, body.worker_name, body.mixer_id, body.mixer_name,
        body.product_id, body.product_name, body.mixture_type_id, body.mixture_type_name,
        body.pvc_qty, body.dop_qty, body.scrap_qty, body.calcium_qty,
        body.wax_qty, body.stabilizer_qty, body.titanium_qty,
        json.dumps(body.pigments or []),
        json.dumps(body.additives or []),
        json.dumps(body.materials or []),
        body.notes, body.scale_image_url, body.transaction_id, body.status,
    )

    batch_id = str(row["id"])
    result = serialize_row(row)

    # ── Audit: create ─────────────────────────────────────────
    await pool.execute(
        """INSERT INTO audit_log
           (id, action, table_name, record_id, transaction_id, user_id, description)
           VALUES (gen_random_uuid(),'create','batches',$1,$2,$3,$4)""",
        batch_id, body.transaction_id, body.created_by,
        f"إنشاء طبخة {body.batch_number}",
    )

    # ── Deduct inventory ──────────────────────────────────────
    materials = _extract_materials(body)
    if materials and body.transaction_id:
        deduct_result = await _apply_deductions(
            pool, batch_id, body.batch_number,
            body.transaction_id, materials, body.created_by,
        )
        result["deduction"] = deduct_result

    result.update(_calc_batch_stats(result))

    # ── Auto 5: Refresh daily report in background ────────────
    asyncio.create_task(_refresh_daily_report(str(body.date or DateType.today())))

    return result


@router.put("/{batch_id}")
async def update_batch(batch_id: str, body: BatchUpdate):
    pool = await get_pool()

    # ── Load old batch to get its transaction_id ───────────────
    old_row = await pool.fetchrow(
        "SELECT transaction_id, batch_number FROM batches WHERE id=$1", batch_id
    )
    old_tx_id = str(old_row["transaction_id"]) if old_row and old_row["transaction_id"] else None
    old_batch_number = old_row["batch_number"] if old_row else ""

    # ── Reverse old deductions ────────────────────────────────
    if old_tx_id:
        await _reverse_deductions(
            pool, old_tx_id,
            reason=f"تعديل طبخة {old_batch_number}",
            reversed_by=body.created_by,
        )

    # ── Update batch record ───────────────────────────────────
    row = await pool.fetchrow(
        """UPDATE batches SET
            batch_number=$1, date=$2, shift=$3, worker_id=$4, worker_name=$5,
            mixer_id=$6, mixer_name=$7, product_id=$8, product_name=$9,
            mixture_type_id=$10, mixture_type_name=$11,
            pvc_qty=$12, dop_qty=$13, scrap_qty=$14, calcium_qty=$15,
            wax_qty=$16, stabilizer_qty=$17, titanium_qty=$18,
            pigments=$19, additives=$20, materials=$21, notes=$22,
            scale_image_url=$23, status=$24, updated_at=NOW()
           WHERE id=$25 RETURNING *""",
        body.batch_number, body.date or DateType.today(), body.shift,
        body.worker_id, body.worker_name, body.mixer_id, body.mixer_name,
        body.product_id, body.product_name, body.mixture_type_id, body.mixture_type_name,
        body.pvc_qty, body.dop_qty, body.scrap_qty, body.calcium_qty,
        body.wax_qty, body.stabilizer_qty, body.titanium_qty,
        json.dumps(body.pigments or []),
        json.dumps(body.additives or []),
        json.dumps(body.materials or []),
        body.notes, body.scale_image_url, body.status, batch_id,
    )
    if not row:
        raise HTTPException(status_code=404, detail="Batch not found")

    result = serialize_row(row)

    # ── Audit: update ─────────────────────────────────────────
    await pool.execute(
        """INSERT INTO audit_log
           (id, action, table_name, record_id, transaction_id, user_id, description)
           VALUES (gen_random_uuid(),'update','batches',$1,$2,$3,$4)""",
        batch_id, body.transaction_id, body.created_by,
        f"تعديل طبخة {body.batch_number}",
    )

    # ── Apply new deductions ──────────────────────────────────
    materials = _extract_materials(body)
    if materials and body.transaction_id:
        deduct_result = await _apply_deductions(
            pool, batch_id, body.batch_number,
            body.transaction_id, materials, body.created_by,
        )
        result["deduction"] = deduct_result

    result.update(_calc_batch_stats(result))

    # ── Auto 5: Refresh daily report in background ────────────
    asyncio.create_task(_refresh_daily_report(str(body.date or DateType.today())))

    return result


@router.delete("/{batch_id}")
async def delete_batch(batch_id: str):
    pool = await get_pool()

    row = await pool.fetchrow(
        "SELECT transaction_id, batch_number FROM batches WHERE id=$1", batch_id
    )
    if row and row["transaction_id"]:
        await _reverse_deductions(
            pool, str(row["transaction_id"]),
            reason=f"حذف طبخة {row['batch_number']}",
        )

    await pool.execute(
        """INSERT INTO audit_log
           (id, action, table_name, record_id, description)
           VALUES (gen_random_uuid(),'delete','batches',$1,$2)""",
        batch_id,
        f"حذف طبخة {row['batch_number'] if row else batch_id}",
    )

    await pool.execute("DELETE FROM batches WHERE id=$1", batch_id)

    # ── Auto 5: Refresh daily report in background ────────────
    asyncio.create_task(_refresh_daily_report(str(DateType.today())))

    return {"success": True}


# ───────────────────── Recipe Deviation ──────────────────────────

@router.get("/{batch_id}/recipe-deviation")
async def get_recipe_deviation(batch_id: str):
    """
    معادلة الاستهلاك المعياري وانحراف الوصفة.

    لكل مادة في الوصفة المرتبطة بنوع المزيج للطبخة:
      الكمية المعيارية (كجم) = (كمية PVC الفعلية ÷ 100) × كمية المادة في الوصفة
      الانحراف              = الفعلي − المعياري
      نسبة الانحراف (%)   = (الانحراف ÷ المعياري) × 100

    ملاحظة: إذا لم تكن الوصفة موجودة، يُرجع قائمة فارغة.
    """
    pool = await get_pool()

    # ── Load batch ────────────────────────────────────────────
    batch = await pool.fetchrow("SELECT * FROM batches WHERE id=$1", batch_id)
    if not batch:
        raise HTTPException(status_code=404, detail="Batch not found")

    def to_f(v): return float(v or 0)

    actual_pvc = to_f(batch["pvc_qty"])

    # ── Load recipe for this mixture_type ─────────────────────
    recipe = await pool.fetchrow(
        "SELECT id FROM recipes WHERE mixture_type_id=$1",
        batch["mixture_type_id"],
    )
    if not recipe:
        return {
            "batch_id": batch_id,
            "batch_number": batch["batch_number"],
            "mixture_type_id": str(batch["mixture_type_id"] or ""),
            "mixture_type_name": batch["mixture_type_name"],
            "actual_pvc_kg": actual_pvc,
            "recipe_found": False,
            "items": [],
            "summary": {
                "total_standard_kg": 0,
                "total_actual_kg": 0,
                "total_deviation_kg": 0,
                "total_deviation_pct": 0,
            },
        }

    recipe_items = await pool.fetch(
        """SELECT ri.material_id, ri.quantity, ri.unit, rm.name, rm.unit AS mat_unit
           FROM recipe_items ri
           JOIN raw_materials rm ON rm.id = ri.material_id
           WHERE ri.recipe_id = $1
           ORDER BY rm.name""",
        recipe["id"],
    )

    # ── Build actual-quantities map from batch ────────────────
    actual_map: dict = {}

    # Fixed fields
    field_to_name = {
        "pvc_qty": "PVC",
        "dop_qty": "DOP",
        "scrap_qty": "scrap",
        "calcium_qty": "calcium",
        "wax_qty": "wax",
        "stabilizer_qty": "stabilizer",
        "titanium_qty": "titanium",
    }
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
                    mid = str(item.get("material_id") or item.get("id") or "")
                    if mid:
                        qty_raw = to_f(item.get("quantity", 0))
                        unit = item.get("unit", "كجم")
                        actual_map[mid] = actual_map.get(mid, 0.0) + _to_kg(qty_raw, unit)

    # ── Compute deviations ────────────────────────────────────
    items = []
    total_standard = 0.0
    total_actual   = 0.0

    for ri in recipe_items:
        material_id = str(ri["material_id"])
        recipe_qty  = to_f(ri["quantity"])
        recipe_unit = ri["unit"] or "كجم"
        recipe_qty_kg = _to_kg(recipe_qty, recipe_unit)

        # Standard = scale recipe qty proportionally to actual PVC
        standard_kg = (actual_pvc / 100.0) * recipe_qty_kg if actual_pvc > 0 else recipe_qty_kg

        actual_kg = actual_map.get(material_id, 0.0)

        deviation_kg = actual_kg - standard_kg
        if standard_kg > 0:
            deviation_pct = round(deviation_kg / standard_kg * 100, 2)
        else:
            deviation_pct = 0.0

        items.append({
            "material_id": material_id,
            "material_name": ri["name"],
            "recipe_qty_per_100kg_pvc": round(recipe_qty_kg, 4),
            "standard_qty_kg": round(standard_kg, 4),
            "actual_qty_kg":   round(actual_kg, 4),
            "deviation_kg":    round(deviation_kg, 4),
            "deviation_pct":   deviation_pct,
            "status": (
                "ok" if abs(deviation_pct) <= 2
                else ("warning" if abs(deviation_pct) <= 5 else "critical")
            ),
        })

        total_standard += standard_kg
        total_actual   += actual_kg

    total_deviation    = total_actual - total_standard
    total_deviation_pct = round(total_deviation / total_standard * 100, 2) if total_standard > 0 else 0.0

    return {
        "batch_id": batch_id,
        "batch_number": batch["batch_number"],
        "mixture_type_id": str(batch["mixture_type_id"] or ""),
        "mixture_type_name": batch["mixture_type_name"],
        "actual_pvc_kg": actual_pvc,
        "recipe_found": True,
        "items": items,
        "summary": {
            "total_standard_kg":  round(total_standard, 3),
            "total_actual_kg":    round(total_actual, 3),
            "total_deviation_kg": round(total_deviation, 3),
            "total_deviation_pct": total_deviation_pct,
        },
    }
