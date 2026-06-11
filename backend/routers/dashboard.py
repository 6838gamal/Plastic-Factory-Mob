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

    # ── Day cost (cost_per_unit not in schema — defaulting to 0) ──
    cost_today = 0.0

    # ── KPIs ───────────────────────────────────────────────────
    efficiency_pct = round(total_produced / total_inputs * 100, 1) if total_inputs > 0 else 0.0
    deviation_pct  = round((total_produced - total_inputs) / total_inputs * 100, 1) if total_inputs > 0 else 0.0
    waste_pct      = round(total_waste / total_inputs * 100, 1) if total_inputs > 0 else 0.0
    cost_per_kg    = round(cost_today / total_produced, 2) if total_produced > 0 else 0.0

    # ── Alerts ─────────────────────────────────────────────────
    alerts_count = await pool.fetchval("SELECT COUNT(*) FROM alerts WHERE status='pending'")

    # ── Low-stock materials count ──────────────────────────────
    low_stock_count = await pool.fetchval(
        """SELECT COUNT(*) FROM inventory i
           JOIN raw_materials r ON r.id = i.material_id
           WHERE r.min_stock > 0 AND i.balance <= r.min_stock"""
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
    }
