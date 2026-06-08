from fastapi import APIRouter, Query
from typing import Optional
from database import get_pool

router = APIRouter(prefix="/api/reports", tags=["reports"])


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
        conditions.append(f"date >= ${i}::date"); params.append(from_[:10]); i += 1
    if to:
        conditions.append(f"date <= ${i}::date"); params.append(to[:10]); i += 1
    params.append(limit); limit_idx = i
    query = f"""
        SELECT * FROM daily_reports
        WHERE {' AND '.join(conditions)}
        ORDER BY date DESC
        LIMIT ${limit_idx}
    """
    rows = await pool.fetch(query, *params)
    return [dict(r) for r in rows]


@router.get("/inventory-summary")
async def get_inventory_summary(
    warehouse_type: Optional[str] = Query(None),
    low_stock_only: bool = Query(False),
):
    pool = await get_pool()
    conditions = ["1=1"]
    if low_stock_only:
        conditions.append("stock_status = 'low'")
    rows = await pool.fetch(
        f"SELECT * FROM inventory_summary WHERE {' AND '.join(conditions)} ORDER BY material_name"
    )
    return [dict(r) for r in rows]


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
        conditions.append(f"it.created_at >= ${i}::timestamptz"); params.append(from_); i += 1
    if to:
        conditions.append(f"it.created_at <= ${i}::timestamptz"); params.append(to); i += 1
    query = f"""
        SELECT
            r.id AS material_id,
            r.name AS material_name,
            r.code,
            r.unit,
            COALESCE(SUM(it.quantity), 0) AS total_consumed,
            COUNT(it.id) AS transaction_count
        FROM inventory_transactions it
        JOIN raw_materials r ON r.id = it.material_id
        WHERE {' AND '.join(conditions)}
        GROUP BY r.id, r.name, r.code, r.unit
        ORDER BY total_consumed DESC
    """
    rows = await pool.fetch(query, *params)
    return [dict(r) for r in rows]


@router.get("/batch-items/{batch_id}")
async def get_batch_items(batch_id: str):
    """Return normalized batch material details, merging batch_items table
    with the legacy JSONB materials column for backwards-compatibility."""
    pool = await get_pool()

    # First try batch_items table
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
    import json
    row = await pool.fetchrow(
        "SELECT materials, pigments, additives FROM batches WHERE id=$1", batch_id
    )
    if not row:
        return []
    items = []
    for field in ("materials", "pigments", "additives"):
        raw = row[field]
        if isinstance(raw, str):
            raw = json.loads(raw)
        if raw:
            items.extend(raw)
    return items
