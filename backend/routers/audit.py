import json
from datetime import datetime
from fastapi import APIRouter, Query, HTTPException
from pydantic import BaseModel
from typing import Optional, Any
from database import get_pool


def _parse_dt(s: str, end_of_day: bool = False) -> datetime:
    """Convert an ISO datetime/date string to a timezone-aware datetime for asyncpg.

    - Full ISO strings (with T) are parsed as-is, converted to UTC-aware.
    - Date-only strings (YYYY-MM-DD) become start-of-day (00:00:00 UTC) unless
      end_of_day=True, in which case they become start of the NEXT day so that
      ``created_at < next_day`` correctly includes all records on that date.
    """
    from datetime import timezone as _tz, timedelta as _td, date as _date
    s = s.strip()
    if "T" in s or " " in s:
        try:
            dt = datetime.fromisoformat(s.replace("Z", "+00:00"))
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=_tz.utc)
            return dt
        except Exception:
            pass
    # Date-only path
    d = _date.fromisoformat(s[:10])
    if end_of_day:
        # next-day midnight so caller can use strict-less-than (<)
        next_day = d + _td(days=1)
        return datetime.combine(next_day, datetime.min.time(), tzinfo=_tz.utc)
    return datetime.combine(d, datetime.min.time(), tzinfo=_tz.utc)

router = APIRouter(prefix="/api/audit", tags=["audit"])


class AuditCreate(BaseModel):
    action: str
    table_name: str
    record_id: Optional[str] = None
    old_values: Optional[Any] = None
    new_values: Optional[Any] = None
    user_id: Optional[str] = None
    user_email: Optional[str] = None
    transaction_id: Optional[str] = None
    description: Optional[str] = None


@router.get("")
async def get_audit_logs(
    table_name: Optional[str] = Query(None),
    action: Optional[str] = Query(None),
    from_: Optional[str] = Query(None, alias="from"),
    to: Optional[str] = Query(None),
):
    pool = await get_pool()
    conditions = ["1=1"]
    params = []
    i = 1
    if table_name:
        conditions.append(f"table_name=${i}"); params.append(table_name); i += 1
    if action:
        conditions.append(f"action=${i}"); params.append(action); i += 1
    if from_:
        conditions.append(f"created_at>=${i}"); params.append(_parse_dt(from_)); i += 1
    if to:
        conditions.append(f"created_at<${i}"); params.append(_parse_dt(to, end_of_day=True)); i += 1
    query = f"SELECT * FROM audit_log WHERE {' AND '.join(conditions)} ORDER BY created_at DESC LIMIT 200"
    rows = await pool.fetch(query, *params)
    return [dict(r) for r in rows]


@router.delete("/{log_id}")
async def delete_audit_log(log_id: str):
    pool = await get_pool()
    try:
        row = await pool.fetchrow("SELECT id FROM audit_log WHERE id=$1::uuid", log_id)
    except Exception:
        raise HTTPException(status_code=400, detail="معرّف سجل غير صالح")
    if not row:
        raise HTTPException(status_code=404, detail="السجل غير موجود")
    await pool.execute("DELETE FROM audit_log WHERE id=$1::uuid", log_id)
    return {"success": True}


@router.delete("")
async def delete_audit_logs(
    table_name: Optional[str] = Query(None),
    from_: Optional[str] = Query(None, alias="from"),
    to: Optional[str] = Query(None),
):
    """Bulk-clear audit log entries. Optionally restrict by table/date range; otherwise clears all."""
    pool = await get_pool()
    conditions = ["1=1"]
    params = []
    i = 1
    if table_name:
        conditions.append(f"table_name=${i}"); params.append(table_name); i += 1
    if from_:
        conditions.append(f"created_at>=${i}"); params.append(_parse_dt(from_)); i += 1
    if to:
        conditions.append(f"created_at<${i}"); params.append(_parse_dt(to, end_of_day=True)); i += 1
    result = await pool.execute(f"DELETE FROM audit_log WHERE {' AND '.join(conditions)}", *params)
    deleted = int(result.split()[-1]) if result else 0
    return {"success": True, "deleted": deleted}


@router.post("")
async def add_audit_log(body: AuditCreate):
    pool = await get_pool()
    old_v = json.dumps(body.old_values) if body.old_values else None
    new_v = json.dumps(body.new_values) if body.new_values else None
    row = await pool.fetchrow(
        """INSERT INTO audit_log
           (id, action, table_name, record_id, old_values, new_values,
            user_id, user_email, transaction_id, description)
           VALUES (gen_random_uuid(), $1, $2, $3, $4, $5, $6, $7, $8, $9)
           RETURNING *""",
        body.action, body.table_name, body.record_id, old_v, new_v,
        body.user_id, body.user_email, body.transaction_id, body.description,
    )
    return dict(row)
