"""
Dashboard stats — computed from live DB data for today.
Supports per-counter resets via the counter_resets table.
"""
from fastapi import APIRouter, HTTPException
from datetime import datetime, date
from database import get_pool

router = APIRouter(prefix="/api/dashboard", tags=["dashboard"])

_VALID_COUNTERS = {"batches", "production", "alerts", "scrap_balance", "inputs"}


async def _last_reset(pool, counter: str, day_start: datetime) -> datetime:
    """Return the last reset time for a counter today, or day_start if none."""
    row = await pool.fetchrow(
        "SELECT reset_at FROM counter_resets "
        "WHERE counter_name=$1 AND reset_at >= $2 "
        "ORDER BY reset_at DESC LIMIT 1",
        counter, day_start,
    )
    if row:
        return row["reset_at"].replace(tzinfo=None)
    return day_start


@router.get("/stats")
async def get_stats():
    pool = await get_pool()
    today = date.today()
    day_start = datetime(today.year, today.month, today.day)
    day_end   = datetime(today.year, today.month, today.day, 23, 59, 59)

    # ── Resolve effective start times per counter (after last reset) ──────
    batches_from    = await _last_reset(pool, "batches",       day_start)
    production_from = await _last_reset(pool, "production",    day_start)
    inputs_from     = await _last_reset(pool, "inputs",        day_start)

    # ── Batches today ──────────────────────────────────────────
    batches_count = await pool.fetchval(
        "SELECT COUNT(*) FROM batches WHERE created_at >= $1", batches_from
    )

    # ── Machine production today ───────────────────────────────
    prod = await pool.fetchrow(
        """SELECT
             COALESCE(SUM(produced_quantity), 0) AS total_produced,
             COALESCE(SUM(scrap_quantity),    0) AS total_scrap,
             COALESCE(SUM(waste_quantity),    0) AS total_waste,
             COALESCE(SUM(stop_time_minutes), 0) AS total_stop_time
           FROM machine_production
           WHERE created_at BETWEEN $1 AND $2""",
        production_from, day_end,
    )
    total_produced   = float(prod["total_produced"])
    total_waste      = float(prod["total_waste"])
    total_scrap      = float(prod["total_scrap"])
    total_stop_time  = float(prod["total_stop_time"])

    # ── Total material inputs today (from inventory out-transactions) ──
    inv_row = await pool.fetchrow(
        """SELECT COALESCE(SUM(quantity), 0) AS total_inputs
           FROM inventory_transactions
           WHERE transaction_type = 'out'
             AND created_at BETWEEN $1 AND $2""",
        inputs_from, day_end,
    )
    total_inputs = float(inv_row["total_inputs"])

    # ── Day cost ───────────────────────────────────────────────
    cost_row = await pool.fetchrow(
        """SELECT COALESCE(SUM(it.quantity * COALESCE(rm.cost_per_unit, 0)), 0) AS day_cost
           FROM inventory_transactions it
           JOIN raw_materials rm ON rm.id::text = it.material_id::text
           WHERE it.transaction_type = 'out'
             AND it.created_at BETWEEN $1 AND $2""",
        inputs_from, day_end,
    )
    cost_today = float(cost_row["day_cost"])

    # ── KPIs ───────────────────────────────────────────────────
    total_outputs = total_produced + total_waste + total_scrap
    efficiency_pct = round(total_produced / total_inputs * 100, 1) if total_inputs > 0 else 0.0
    deviation_pct  = round((total_outputs - total_inputs) / total_inputs * 100, 1) if total_inputs > 0 else 0.0
    waste_pct      = round(total_waste / total_inputs * 100, 1) if total_inputs > 0 else 0.0
    cost_per_kg    = round(cost_today / total_produced, 2) if total_produced > 0 else 0.0

    # ── Alerts ─────────────────────────────────────────────────
    alerts_count = await pool.fetchval("SELECT COUNT(*) FROM alerts WHERE status='pending'")

    # ── Low-stock materials count ──────────────────────────────
    low_stock_count = await pool.fetchval(
        """SELECT COUNT(*) FROM inventory i
           JOIN raw_materials r ON r.id::text = i.material_id::text
           WHERE r.min_stock > 0 AND i.balance <= r.min_stock"""
    )

    # ── Custody debts (pending) ────────────────────────────────
    custody_debts_count = await pool.fetchval(
        "SELECT COUNT(*) FROM custody_debts WHERE status='pending'"
    )
    custody_debts_total_kg = await pool.fetchval(
        "SELECT COALESCE(SUM(deficit_kg), 0) FROM custody_debts WHERE status='pending'"
    )

    # ── Scrap warehouse balance ────────────────────────────────
    scrap_balance_kg = await pool.fetchval(
        "SELECT COALESCE(SUM(balance), 0) FROM inventory WHERE warehouse_type='scrap'"
    )

    # ── Today's shift handovers ────────────────────────────────
    frozen_shifts_today = await pool.fetchval(
        "SELECT COUNT(*) FROM shift_handovers WHERE handover_date=$1 AND status='frozen'",
        today,
    )

    # ── Last reset times (to show in UI) ──────────────────────
    last_resets: dict = {}
    for c in _VALID_COUNTERS:
        row = await pool.fetchrow(
            "SELECT reset_at FROM counter_resets "
            "WHERE counter_name=$1 AND reset_at >= $2 "
            "ORDER BY reset_at DESC LIMIT 1",
            c, day_start,
        )
        if row:
            last_resets[c] = row["reset_at"].isoformat()

    return {
        "batches_today":    int(batches_count),
        "production_today": round(total_produced, 2),
        "scrap_today":      round(total_scrap, 2),
        "waste_today":      round(total_waste, 2),
        "stop_time_today":  round(total_stop_time, 1),
        "total_inputs_today": round(total_inputs, 2),
        "pending_alerts":   int(alerts_count),
        "low_stock_count":  int(low_stock_count),
        "waste_percentage": waste_pct,
        "efficiency_pct":   efficiency_pct,
        "deviation_pct":    deviation_pct,
        "cost_today":       round(cost_today, 2),
        "cost_per_kg":      cost_per_kg,
        "custody_debts_count": int(custody_debts_count),
        "custody_debts_total_kg": round(float(custody_debts_total_kg), 3),
        "scrap_balance_kg": round(float(scrap_balance_kg), 3),
        "frozen_shifts_today": int(frozen_shifts_today),
        "last_resets": last_resets,
    }


@router.post("/reset/{counter}")
async def reset_counter(counter: str):
    """Reset a specific dashboard counter."""
    if counter not in _VALID_COUNTERS:
        raise HTTPException(
            status_code=400,
            detail=f"عداد غير معروف. القيم المسموح بها: {', '.join(_VALID_COUNTERS)}",
        )

    pool = await get_pool()
    now = datetime.utcnow()

    if counter == "alerts":
        affected = await pool.execute(
            "UPDATE alerts SET status='resolved' WHERE status='pending'"
        )
        return {"ok": True, "counter": counter, "reset_at": now.isoformat(), "detail": "تم حل جميع التحذيرات المعلقة"}

    elif counter == "scrap_balance":
        await pool.execute(
            "UPDATE inventory SET balance=0 WHERE warehouse_type='scrap'"
        )
        await pool.execute(
            "INSERT INTO counter_resets (counter_name, reset_at) VALUES ($1, $2)",
            counter, now,
        )
        return {"ok": True, "counter": counter, "reset_at": now.isoformat(), "detail": "تم تصفير رصيد السكراب"}

    else:
        await pool.execute(
            "INSERT INTO counter_resets (counter_name, reset_at) VALUES ($1, $2)",
            counter, now,
        )
        return {"ok": True, "counter": counter, "reset_at": now.isoformat(), "detail": "تم التصفير بنجاح"}
