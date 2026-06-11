"""
Reports router — daily reports, inventory summary, consumption, batch items.

Daily report generation:
  POST /api/reports/daily/generate?date=YYYY-MM-DD
  - Calculates all KPIs for the given day
  - Creates/updates a daily_reports row
  - Locks the report if requested
  - Writes an audit_log entry
"""
import json
from datetime import date as date_type, datetime, timezone
from fastapi import APIRouter, Query, HTTPException
from typing import Optional
from database import get_pool


def _parse_date(s: str) -> date_type:
    """Convert a YYYY-MM-DD string to datetime.date (asyncpg needs date objects)."""
    return date_type.fromisoformat(s[:10])


def _parse_dt(s: str) -> datetime:
    """Convert an ISO datetime string to datetime object for asyncpg."""
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return datetime.combine(_parse_date(s), datetime.min.time())

router = APIRouter(prefix="/api/reports", tags=["reports"])


# ────────────────────────── Daily reports ──────────────────────

@router.get("/daily")
async def get_daily_reports(
    from_: Optional[str] = Query(None, alias="from"),
    to: Optional[str] = Query(None),
    limit: int = Query(30),
):
    pool = await get_pool()
    conditions = ["1=1"]
    params: list = []
    i = 1
    if from_:
        conditions.append(f"report_date >= ${i}"); params.append(_parse_date(from_)); i += 1
    if to:
        conditions.append(f"report_date <= ${i}"); params.append(_parse_date(to)); i += 1
    params.append(limit)
    query = f"""
        SELECT * FROM daily_reports
        WHERE {' AND '.join(conditions)}
        ORDER BY report_date DESC
        LIMIT ${i}
    """
    rows = await pool.fetch(query, *params)
    result = []
    for r in rows:
        d = dict(r)
        if isinstance(d.get("snapshot"), str):
            try:
                d["snapshot"] = json.loads(d["snapshot"])
            except Exception:
                pass
        result.append(d)
    return result


@router.get("/daily/{report_date}")
async def get_daily_report(report_date: str):
    pool = await get_pool()
    row = await pool.fetchrow(
        "SELECT * FROM daily_reports WHERE report_date=$1", _parse_date(report_date)
    )
    if not row:
        raise HTTPException(status_code=404, detail="Report not found")
    d = dict(row)
    if isinstance(d.get("snapshot"), str):
        try:
            d["snapshot"] = json.loads(d["snapshot"])
        except Exception:
            pass
    return d


@router.post("/daily/generate")
async def generate_daily_report(
    report_date: Optional[str] = Query(None, description="YYYY-MM-DD — defaults to today"),
    lock: bool = Query(False, description="Lock the report after generation"),
):
    """Generate (or regenerate) the daily report for the given date.

    Aggregates:
     - total batches, total inputs (from inventory_transactions 'out')
     - total production, waste, scrap (from machine_production)
     - total alerts, day cost
     - most/least consumed material
     - efficiency %, deviation %, waste %
    """
    pool = await get_pool()
    from datetime import date as dt_date
    target_str = (report_date or str(dt_date.today()))[:10]
    target = dt_date.fromisoformat(target_str)

    # Check existing locked report
    existing = await pool.fetchrow(
        "SELECT is_locked FROM daily_reports WHERE report_date=$1", target
    )
    if existing and existing["is_locked"] and not lock:
        raise HTTPException(
            status_code=400,
            detail=f"تقرير يوم {target_str} مقفل ولا يمكن تعديله"
        )

    day_start = datetime.combine(target, datetime.min.time())
    day_end   = datetime.combine(target, datetime.max.time().replace(microsecond=0))

    # ── Batches ────────────────────────────────────────────────
    total_batches = await pool.fetchval(
        "SELECT COUNT(*) FROM batches WHERE date=$1", target
    )

    # ── Machine production ─────────────────────────────────────
    prod = await pool.fetchrow(
        """SELECT
             COALESCE(SUM(produced_quantity),0) AS total_produced,
             COALESCE(SUM(scrap_quantity),0)    AS total_scrap,
             COALESCE(SUM(waste_quantity),0)    AS total_waste,
             COALESCE(SUM(stop_time_minutes),0) AS total_stop_time
           FROM machine_production
           WHERE created_at BETWEEN $1 AND $2""",
        day_start, day_end,
    )
    total_produced = float(prod["total_produced"])
    total_scrap    = float(prod["total_scrap"])
    total_waste    = float(prod["total_waste"])

    # ── Inventory consumption (out transactions) ───────────────
    inv_row = await pool.fetchrow(
        """SELECT COALESCE(SUM(quantity),0) AS total_inputs
           FROM inventory_transactions
           WHERE transaction_type='out'
             AND created_at BETWEEN $1 AND $2""",
        day_start, day_end,
    )
    total_inputs = float(inv_row["total_inputs"])

    # ── Alerts ────────────────────────────────────────────────
    total_alerts = await pool.fetchval(
        """SELECT COUNT(*) FROM alerts
           WHERE created_at BETWEEN $1 AND $2""",
        day_start, day_end,
    )

    # ── Day cost (sum of qty × cost_per_unit) ─────────────────
    cost_row = await pool.fetchrow(
        """SELECT COALESCE(SUM(it.quantity * rm.cost_per_unit),0) AS day_cost
           FROM inventory_transactions it
           JOIN raw_materials rm ON rm.id::text = it.material_id::text
           WHERE it.transaction_type='out'
             AND it.created_at BETWEEN $1 AND $2""",
        day_start, day_end,
    )
    day_cost = float(cost_row["day_cost"])

    # ── Most / least consumed material ────────────────────────
    consumption_rows = await pool.fetch(
        """SELECT rm.name, COALESCE(SUM(it.quantity),0) AS consumed
           FROM inventory_transactions it
           JOIN raw_materials rm ON rm.id::text = it.material_id::text
           WHERE it.transaction_type='out'
             AND it.created_at BETWEEN $1 AND $2
           GROUP BY rm.name
           ORDER BY consumed DESC""",
        day_start, day_end,
    )
    most_consumed  = consumption_rows[0]["name"]  if consumption_rows else None
    least_consumed = consumption_rows[-1]["name"] if consumption_rows else None
    consumption_snapshot = [{"name": r["name"], "consumed": float(r["consumed"])} for r in consumption_rows]

    # ── KPI formulas ───────────────────────────────────────────
    # الانحراف = (المخرجات - المدخلات) / المدخلات × 100
    # المخرجات = الإنتاج النهائي + السكراب + الهالك
    total_outputs = total_produced + total_scrap + total_waste
    if total_inputs > 0:
        efficiency_pct = round(total_produced / total_inputs * 100, 2)
        deviation_pct  = round((total_outputs - total_inputs) / total_inputs * 100, 2)
        waste_pct      = round(total_waste / total_inputs * 100, 2)
    else:
        efficiency_pct = deviation_pct = waste_pct = 0.0

    # ── Snapshot ───────────────────────────────────────────────
    snapshot = {
        "consumption": consumption_snapshot,
        "generated_at": datetime.utcnow().isoformat(),
    }

    # ── Upsert report ──────────────────────────────────────────
    # Note: total_production is a GENERATED ALWAYS column (= total_produced),
    # so we insert into total_produced only.
    row = await pool.fetchrow(
        """INSERT INTO daily_reports
           (id, report_date, total_batches, total_produced, total_inputs, total_waste,
            total_scrap, total_alerts, day_cost, most_consumed_material,
            least_consumed_material, efficiency_pct, deviation_pct, waste_pct,
            snapshot, is_locked, locked_at, updated_at)
           VALUES (gen_random_uuid(), $1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
                   $11, $12, $13, $14, $15,
                   CASE WHEN $15 THEN NOW() ELSE NULL END, NOW())
           ON CONFLICT (report_date)
           DO UPDATE SET
             total_batches=$2, total_produced=$3, total_inputs=$4, total_waste=$5,
             total_scrap=$6, total_alerts=$7, day_cost=$8,
             most_consumed_material=$9, least_consumed_material=$10,
             efficiency_pct=$11, deviation_pct=$12, waste_pct=$13,
             snapshot=$14, is_locked=$15,
             locked_at=CASE WHEN $15 THEN NOW() ELSE daily_reports.locked_at END,
             updated_at=NOW()
           RETURNING *""",
        target,
        int(total_batches), total_produced, total_inputs, total_waste,
        total_scrap, int(total_alerts), day_cost,
        most_consumed, least_consumed,
        efficiency_pct, deviation_pct, waste_pct,
        json.dumps(snapshot, ensure_ascii=False), lock,
    )

    # ── Audit log ──────────────────────────────────────────────
    await pool.execute(
        """INSERT INTO audit_log
           (id, action, table_name, record_id, description)
           VALUES (gen_random_uuid(),'create','daily_reports',$1,$2)""",
        str(row["id"]),
        f"تقرير يومي {target}" + (" (مقفل)" if lock else ""),
    )

    d = dict(row)
    if isinstance(d.get("snapshot"), str):
        try:
            d["snapshot"] = json.loads(d["snapshot"])
        except Exception:
            pass
    return d


# ────────────────────────── Inventory ─────────────────────────

@router.get("/inventory-summary")
async def get_inventory_summary(
    warehouse_type: Optional[str] = Query(None),
    low_stock_only: bool = Query(False),
):
    pool = await get_pool()
    conditions = ["1=1"]
    if low_stock_only:
        conditions.append("stock_status IN ('low','out_of_stock')")
    rows = await pool.fetch(
        f"SELECT * FROM inventory_summary WHERE {' AND '.join(conditions)} ORDER BY material_name"
    )
    return [dict(r) for r in rows]


# ────────────────────────── Consumption ───────────────────────

@router.get("/consumption")
async def get_consumption_report(
    from_: Optional[str] = Query(None, alias="from"),
    to: Optional[str] = Query(None),
):
    """Total consumption per material for a date range."""
    pool = await get_pool()
    conditions = ["it.transaction_type = 'out'"]
    params: list = []
    i = 1
    if from_:
        conditions.append(f"it.created_at >= ${i}"); params.append(_parse_dt(from_)); i += 1
    if to:
        conditions.append(f"it.created_at <= ${i}"); params.append(_parse_dt(to)); i += 1
    query = f"""
        SELECT
            r.id AS material_id,
            r.name AS material_name,
            r.code,
            r.unit,
            r.cost_per_unit,
            COALESCE(SUM(it.quantity), 0) AS total_consumed,
            COALESCE(SUM(it.quantity * r.cost_per_unit), 0) AS total_cost,
            COUNT(it.id) AS transaction_count
        FROM inventory_transactions it
        JOIN raw_materials r ON r.id::text = it.material_id::text
        WHERE {' AND '.join(conditions)}
        GROUP BY r.id, r.name, r.code, r.unit, r.cost_per_unit
        ORDER BY total_consumed DESC
    """
    rows = await pool.fetch(query, *params)
    return [dict(r) for r in rows]


# ────────────────────────── Batch items ───────────────────────

@router.get("/batch-items/{batch_id}")
async def get_batch_items(batch_id: str):
    """Return normalized batch material details."""
    pool = await get_pool()

    rows = await pool.fetch(
        """SELECT bi.*, r.name AS material_name, r.unit
           FROM batch_items bi
           LEFT JOIN raw_materials r ON r.id = bi.material_id
           WHERE bi.batch_id = $1
           ORDER BY bi.created_at""",
        batch_id,
    )
    if rows:
        return [dict(r) for r in rows]

    # Fallback: parse JSONB materials column from batches
    row = await pool.fetchrow(
        "SELECT materials, pigments, additives FROM batches WHERE id=$1", batch_id
    )
    if not row:
        return []
    items = []
    for field in ("materials", "pigments", "additives"):
        raw = row[field]
        if isinstance(raw, str):
            try:
                raw = json.loads(raw)
            except Exception:
                raw = []
        if raw:
            items.extend(raw)
    return items


# ────────────────────────── Balance history ───────────────────

@router.get("/material-balance/{material_id}")
async def get_material_balance_history(
    material_id: str,
    from_: Optional[str] = Query(None, alias="from"),
    to: Optional[str] = Query(None),
    limit: int = Query(100),
):
    """Full transaction history and computed balance for one material."""
    pool = await get_pool()
    conditions = ["it.material_id=$1"]
    params: list = [material_id]
    i = 2
    if from_:
        conditions.append(f"it.created_at>=${i}"); params.append(_parse_dt(from_)); i += 1
    if to:
        conditions.append(f"it.created_at<=${i}"); params.append(_parse_dt(to)); i += 1
    params.append(limit)
    query = f"""
        SELECT it.*, rm.name AS material_name, rm.unit
        FROM inventory_transactions it
        JOIN raw_materials rm ON rm.id::text = it.material_id::text
        WHERE {' AND '.join(conditions)}
        ORDER BY it.created_at DESC
        LIMIT ${i}
    """
    rows = await pool.fetch(query, *params)
    return [dict(r) for r in rows]
