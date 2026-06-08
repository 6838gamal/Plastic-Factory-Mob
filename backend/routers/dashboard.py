from fastapi import APIRouter
from datetime import datetime, date
from database import get_pool

router = APIRouter(prefix="/api/dashboard", tags=["dashboard"])


@router.get("/stats")
async def get_stats():
    pool = await get_pool()
    today = date.today()
    start_of_day = datetime(today.year, today.month, today.day).isoformat()

    batches_count = await pool.fetchval(
        "SELECT COUNT(*) FROM batches WHERE created_at >= $1", start_of_day
    )
    prod_row = await pool.fetchrow(
        """SELECT
             COALESCE(SUM(produced_quantity), 0) AS total_produced,
             COALESCE(SUM(scrap_quantity), 0) AS total_scrap,
             COALESCE(SUM(waste_quantity), 0) AS total_waste,
             COALESCE(SUM(stop_time_minutes), 0) AS total_stop_time
           FROM machine_production WHERE created_at >= $1""",
        start_of_day,
    )
    alerts_count = await pool.fetchval("SELECT COUNT(*) FROM alerts WHERE status='pending'")

    total_produced = float(prod_row["total_produced"])
    total_waste = float(prod_row["total_waste"])

    return {
        "batches_today": batches_count,
        "production_today": total_produced,
        "scrap_today": float(prod_row["total_scrap"]),
        "waste_today": total_waste,
        "stop_time_today": float(prod_row["total_stop_time"]),
        "pending_alerts": alerts_count,
        "waste_percentage": (total_waste / total_produced * 100) if total_produced > 0 else 0,
    }
