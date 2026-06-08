import json
from fastapi import APIRouter, Query
from pydantic import BaseModel
from typing import Optional, Any
from database import get_pool

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
        conditions.append(f"created_at>=${i}"); params.append(from_); i += 1
    if to:
        conditions.append(f"created_at<=${i}"); params.append(to); i += 1
    query = f"SELECT * FROM audit_log WHERE {' AND '.join(conditions)} ORDER BY created_at DESC LIMIT 200"
    rows = await pool.fetch(query, *params)
    return [dict(r) for r in rows]


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
