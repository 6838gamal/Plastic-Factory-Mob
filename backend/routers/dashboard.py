"""
Dashboard stats — computed from live DB data for today.

Includes:
 - batches_today, production_today, scrap/waste/stop_time
 - pending_alerts
 - waste_percentage, efficiency_pct, deviation_pct
 - cost_today (sum of qty × cost_per_unit from inventory_transactions)
"""
from fastapi import APIRouter
from datetime import datetime, date
from database import get_pool

router = APIRouter(prefix="/api/dashboard", tags=["dashboard"])


@router.get("/stats")
async def get_stats():
    pool = await get_pool()
    today = date.today()
    day_start = datetime(today.year, today.month, today.day)
    day_end   = datetime(today.year, today.month, today.day, 23, 59, 59)

    # ── Batches today ──────────────────────────────────────────
    batches_count = await pool.fetchval(
        "SELECT COUNT(*) FROM batches WHERE created_at >= $1", day_start
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
        day_start, day_end,
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
        day_start, day_end,
    )
    total_inputs = float(inv_row["total_inputs"])

    # ── Day cost ───────────────────────────────────────────────
    cost_row = await pool.fetchrow(
        """SELECT COALESCE(SUM(it.quantity * COALESCE(rm.cost_per_unit, 0)), 0) AS day_cost
           FROM inventory_transactions it
           JOIN raw_materials rm ON rm.id::text = it.material_id::text
           WHERE it.transaction_type = 'out'
             AND it.created_at BETWEEN $1 AND $2""",
        day_start, day_end,
    )
    cost_today = float(cost_row["day_cost"])

    # ── KPIs ───────────────────────────────────────────────────
    # الانحراف = (المخرجات - المدخلات) / المدخلات × 100
    # المخرجات = الإنتاج النهائي + السكراب + الهالك
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
    }
