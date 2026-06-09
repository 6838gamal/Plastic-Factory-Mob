"""
Day management router — Automation 18: open new work day.

POST /api/day/open
 - Checks if today already has a report snapshot (day is open)
 - If not: snapshots current inventory as opening state for the day
 - Seeds default settings if missing
 - Returns day status and opening inventory snapshot

GET /api/day/status
 - Returns whether today is already open, locked, and today's KPIs
"""
from fastapi import APIRouter
from datetime import date, datetime
from database import get_pool

router = APIRouter(prefix="/api/day", tags=["day"])


@router.get("/status")
async def get_day_status():
    """Return today's work-day status: is_open, is_locked, opening snapshot."""
    pool = await get_pool()
    today = date.today()

    report = await pool.fetchrow(
        "SELECT * FROM daily_reports WHERE report_date=$1", today
    )

    # Count today's batches and production
    batches_today = await pool.fetchval(
        "SELECT COUNT(*) FROM batches WHERE date=$1", today
    )
    prod = await pool.fetchrow(
        """SELECT COALESCE(SUM(produced_quantity),0) AS produced,
                  COALESCE(SUM(waste_quantity),0) AS waste,
                  COALESCE(SUM(scrap_quantity),0) AS scrap
           FROM machine_production WHERE created_at::date=$1""",
        today,
    )

    return {
        "date": str(today),
        "is_open": report is not None or int(batches_today) > 0,
        "is_locked": bool(report["is_locked"]) if report else False,
        "batches_today": int(batches_today),
        "produced_today": float(prod["produced"]) if prod else 0.0,
        "waste_today": float(prod["waste"]) if prod else 0.0,
        "scrap_today": float(prod["scrap"]) if prod else 0.0,
        "report_exists": report is not None,
    }


@router.post("/open")
async def open_new_day():
    """
    Automation 18 — Open a new work day.

    1. Snapshots current inventory balances as the day's opening state.
    2. Seeds any missing default settings.
    3. Creates an audit log entry.
    4. Returns the opening inventory snapshot.
    """
    pool = await get_pool()
    today = date.today()

    # ── 1. Seed missing settings ──────────────────────────────
    defaults = {
        "prevent_negative_stock": "true",
        "deviation_alert_threshold": "2.0",
        "deviation_notes_threshold": "5.0",
        "scrap_material_id": "",
    }
    for k, v in defaults.items():
        await pool.execute(
            "INSERT INTO settings (key, value) VALUES ($1,$2) ON CONFLICT (key) DO NOTHING",
            k, v,
        )

    # ── 2. Snapshot current inventory ────────────────────────
    inv_rows = await pool.fetch(
        """SELECT i.material_id, rm.name, rm.unit, i.warehouse_type, i.balance
           FROM inventory i
           JOIN raw_materials rm ON rm.id = i.material_id
           ORDER BY rm.name, i.warehouse_type"""
    )
    opening_snapshot = [
        {
            "material_id": str(r["material_id"]),
            "name": r["name"],
            "unit": r["unit"],
            "warehouse_type": r["warehouse_type"],
            "opening_balance": float(r["balance"]),
        }
        for r in inv_rows
    ]

    # ── 3. Check if report already exists for today ───────────
    existing = await pool.fetchrow(
        "SELECT id, is_locked FROM daily_reports WHERE report_date=$1", today
    )
    already_open = existing is not None

    # ── 4. Audit log ──────────────────────────────────────────
    if not already_open:
        await pool.execute(
            """INSERT INTO audit_log (id, action, table_name, description)
               VALUES (gen_random_uuid(), 'create', 'daily_reports', $1)""",
            f"فتح يوم عمل جديد: {today}",
        )

    return {
        "success": True,
        "date": str(today),
        "already_open": already_open,
        "is_locked": bool(existing["is_locked"]) if existing else False,
        "opening_inventory_count": len(opening_snapshot),
        "opening_snapshot": opening_snapshot,
        "message": f"يوم {today} {'مفتوح مسبقاً' if already_open else 'تم فتحه بنجاح'}",
    }
