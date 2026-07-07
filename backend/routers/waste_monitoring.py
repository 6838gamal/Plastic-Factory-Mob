"""
Waste Monitoring router — مراقبة الهدر والانحراف عن معايير الإنتاج

Provides analytics for production yield vs. standards.
All queries rely on the computed columns stored in machine_production:
  actual_gram_per_pair, standard_gram_per_pair, deviation_from_standard_pct, waste_indicator
"""
from fastapi import APIRouter, Query
from typing import Optional
from datetime import date, timedelta, datetime
from database import get_pool

router = APIRouter(prefix="/api/waste-monitoring", tags=["waste_monitoring"])


def _parse_date(s: Optional[str]) -> Optional[date]:
    if not s:
        return None
    try:
        return date.fromisoformat(s)
    except Exception:
        return None


def _to_dt(d: date, end: bool = False) -> datetime:
    if end:
        return datetime(d.year, d.month, d.day, 23, 59, 59)
    return datetime(d.year, d.month, d.day, 0, 0, 0)


@router.get("/dashboard")
async def get_waste_dashboard(
    from_date: Optional[str] = Query(None, alias="from"),
    to_date: Optional[str] = Query(None, alias="to"),
):
    """Main waste monitoring dashboard stats."""
    pool = await get_pool()
    today = date.today()
    d_from = _parse_date(from_date) or today
    d_to = _parse_date(to_date) or today
    dt_from = _to_dt(d_from)
    dt_to = _to_dt(d_to, end=True)

    # ── Summary ─────────────────────────────────────────────────────
    try:
        summary = await pool.fetchrow(
            """SELECT
                 COUNT(*) AS total_operations,
                 COALESCE(SUM(pairs_produced), 0) AS total_pairs,
                 COALESCE(SUM(produced_quantity + scrap_quantity + waste_quantity), 0) AS total_material_kg,
                 COALESCE(SUM(produced_quantity), 0) AS total_produced_kg,
                 COUNT(*) FILTER (WHERE waste_indicator = 'normal')   AS normal_count,
                 COUNT(*) FILTER (WHERE waste_indicator = 'warning')  AS warning_count,
                 COUNT(*) FILTER (WHERE waste_indicator = 'critical') AS critical_count,
                 COALESCE(AVG(deviation_from_standard_pct)
                   FILTER (WHERE deviation_from_standard_pct IS NOT NULL), 0) AS avg_deviation,
                 COALESCE(SUM(
                   GREATEST(0,
                     (actual_gram_per_pair - standard_gram_per_pair) * pairs_produced / 1000.0
                   )
                 ) FILTER (WHERE actual_gram_per_pair IS NOT NULL AND standard_gram_per_pair IS NOT NULL), 0)
                   AS total_excess_kg
               FROM machine_production
               WHERE created_at BETWEEN $1 AND $2
                 AND pairs_produced > 0
                 AND standard_id IS NOT NULL""",
            dt_from, dt_to,
        )
        summary_dict = dict(summary) if summary else {}
    except Exception as exc:
        summary_dict = {"error": str(exc)}

    # ── By product type ─────────────────────────────────────────────
    try:
        by_product = await pool.fetch(
            """SELECT
                 product_name,
                 COALESCE(MAX(standard_gram_per_pair), 0) AS standard_gram_per_pair,
                 COUNT(*) AS operation_count,
                 COALESCE(SUM(pairs_produced), 0) AS total_pairs,
                 COALESCE(AVG(actual_gram_per_pair), 0) AS avg_actual_gram,
                 COALESCE(AVG(deviation_from_standard_pct), 0) AS avg_deviation,
                 COUNT(*) FILTER (WHERE waste_indicator = 'critical') AS critical_count,
                 COUNT(*) FILTER (WHERE waste_indicator = 'warning')  AS warning_count
               FROM machine_production
               WHERE created_at BETWEEN $1 AND $2
                 AND pairs_produced > 0
                 AND standard_id IS NOT NULL
               GROUP BY product_name
               ORDER BY avg_deviation DESC NULLS LAST""",
            dt_from, dt_to,
        )
        by_product_list = [dict(r) for r in by_product]
    except Exception:
        by_product_list = []

    # ── Top wasting operations ───────────────────────────────────────
    try:
        top_waste = await pool.fetch(
            """SELECT id, machine_name, product_name, worker_name,
                      pairs_produced, actual_gram_per_pair, standard_gram_per_pair,
                      deviation_from_standard_pct, waste_indicator, created_at
               FROM machine_production
               WHERE created_at BETWEEN $1 AND $2
                 AND pairs_produced > 0
                 AND standard_id IS NOT NULL
                 AND deviation_from_standard_pct > 0
               ORDER BY deviation_from_standard_pct DESC NULLS LAST
               LIMIT 10""",
            dt_from, dt_to,
        )
        top_waste_list = [dict(r) for r in top_waste]
    except Exception:
        top_waste_list = []

    # ── By machine ──────────────────────────────────────────────────
    try:
        by_machine = await pool.fetch(
            """SELECT machine_name,
                      COUNT(*) AS operation_count,
                      COALESCE(SUM(pairs_produced), 0) AS total_pairs,
                      COALESCE(AVG(deviation_from_standard_pct), 0) AS avg_deviation,
                      COALESCE(SUM(
                        GREATEST(0, (actual_gram_per_pair - standard_gram_per_pair)
                                 * pairs_produced / 1000.0)
                      ) FILTER (WHERE actual_gram_per_pair IS NOT NULL), 0) AS total_excess_kg,
                      COUNT(*) FILTER (WHERE waste_indicator = 'critical') AS critical_count,
                      COUNT(*) FILTER (WHERE waste_indicator = 'warning')  AS warning_count
               FROM machine_production
               WHERE created_at BETWEEN $1 AND $2
                 AND pairs_produced > 0
                 AND standard_id IS NOT NULL
               GROUP BY machine_name
               ORDER BY avg_deviation DESC NULLS LAST""",
            dt_from, dt_to,
        )
        by_machine_list = [dict(r) for r in by_machine]
    except Exception:
        by_machine_list = []

    # ── By supervisor (worker) ───────────────────────────────────────
    try:
        by_supervisor = await pool.fetch(
            """SELECT worker_name,
                      COUNT(*) AS operation_count,
                      COALESCE(AVG(deviation_from_standard_pct), 0) AS avg_deviation,
                      COUNT(*) FILTER (WHERE waste_indicator = 'critical') AS critical_count,
                      COUNT(*) FILTER (WHERE waste_indicator = 'warning')  AS warning_count
               FROM machine_production
               WHERE created_at BETWEEN $1 AND $2
                 AND pairs_produced > 0
                 AND standard_id IS NOT NULL
                 AND worker_name IS NOT NULL AND worker_name != ''
               GROUP BY worker_name
               ORDER BY avg_deviation DESC NULLS LAST""",
            dt_from, dt_to,
        )
        by_supervisor_list = [dict(r) for r in by_supervisor]
    except Exception:
        by_supervisor_list = []

    return {
        "summary": summary_dict,
        "by_product": by_product_list,
        "top_waste_operations": top_waste_list,
        "by_machine": by_machine_list,
        "by_supervisor": by_supervisor_list,
    }


@router.get("/trend")
async def get_waste_trend(days: int = Query(7, ge=1, le=90)):
    """Daily waste deviation trend for the past N days."""
    pool = await get_pool()
    today = date.today()
    start = today - timedelta(days=days - 1)
    try:
        rows = await pool.fetch(
            """SELECT
                 DATE(created_at AT TIME ZONE 'UTC') AS day,
                 COUNT(*) AS operations,
                 COALESCE(AVG(deviation_from_standard_pct), 0) AS avg_deviation,
                 COUNT(*) FILTER (WHERE waste_indicator = 'critical') AS critical_count,
                 COUNT(*) FILTER (WHERE waste_indicator = 'warning')  AS warning_count,
                 COUNT(*) FILTER (WHERE waste_indicator = 'normal')   AS normal_count,
                 COALESCE(SUM(pairs_produced), 0) AS total_pairs
               FROM machine_production
               WHERE DATE(created_at AT TIME ZONE 'UTC') >= $1
                 AND pairs_produced > 0
                 AND standard_id IS NOT NULL
               GROUP BY DATE(created_at AT TIME ZONE 'UTC')
               ORDER BY day ASC""",
            start,
        )
        return [dict(r) for r in rows]
    except Exception:
        return []
