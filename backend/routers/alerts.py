from fastapi import APIRouter, Query, HTTPException
from pydantic import BaseModel
from typing import Optional
from database import get_pool

router = APIRouter(prefix="/api/alerts", tags=["alerts"])


class AlertCreate(BaseModel):
    alert_type: str
    severity: Optional[str] = "medium"
    material_id: Optional[str] = None
    material_name: Optional[str] = None
    batch_id: Optional[str] = None
    batch_number: Optional[str] = None
    machine_id: Optional[str] = None
    machine_name: Optional[str] = None
    description: str
    status: Optional[str] = "pending"
    transaction_id: Optional[str] = None


class AlertStatusUpdate(BaseModel):
    status: str


@router.get("")
async def get_alerts(
    status: Optional[str] = Query(None),
    severity: Optional[str] = Query(None),
):
    pool = await get_pool()
    conditions = ["1=1"]
    params = []
    i = 1
    if status:
        conditions.append(f"status=${i}"); params.append(status); i += 1
    if severity:
        conditions.append(f"severity=${i}"); params.append(severity); i += 1
    query = f"SELECT * FROM alerts WHERE {' AND '.join(conditions)} ORDER BY created_at DESC"
    rows = await pool.fetch(query, *params)
    return [dict(r) for r in rows]


@router.get("/pending-count")
async def pending_count():
    pool = await get_pool()
    row = await pool.fetchrow("SELECT COUNT(*) AS count FROM alerts WHERE status='pending'")
    return {"count": row["count"]}


@router.post("")
async def create_alert(body: AlertCreate):
    pool = await get_pool()
    row = await pool.fetchrow(
        """INSERT INTO alerts (
            id, alert_type, severity, material_id, material_name, batch_id, batch_number,
            machine_id, machine_name, description, status, transaction_id
        ) VALUES (gen_random_uuid(), $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
        RETURNING *""",
        body.alert_type, body.severity, body.material_id, body.material_name,
        body.batch_id, body.batch_number, body.machine_id, body.machine_name,
        body.description, body.status, body.transaction_id,
    )
    return dict(row)


@router.put("/{alert_id}/status")
async def update_status(alert_id: str, body: AlertStatusUpdate):
    pool = await get_pool()
    try:
        if body.status == "resolved":
            row = await pool.fetchrow(
                "UPDATE alerts SET status=$1, resolved_at=NOW(), updated_at=NOW() WHERE id=$2::uuid RETURNING *",
                body.status, alert_id,
            )
        else:
            row = await pool.fetchrow(
                "UPDATE alerts SET status=$1, updated_at=NOW() WHERE id=$2::uuid RETURNING *",
                body.status, alert_id,
            )
    except Exception:
        raise HTTPException(status_code=400, detail="معرّف تحذير غير صالح")
    if not row:
        raise HTTPException(status_code=404, detail="Alert not found")
    return dict(row)


@router.delete("/{alert_id}")
async def delete_alert(alert_id: str):
    pool = await get_pool()
    try:
        existing = await pool.fetchrow(
            "SELECT status FROM alerts WHERE id=$1::uuid", alert_id
        )
    except Exception:
        raise HTTPException(status_code=400, detail="معرّف تحذير غير صالح")
    if not existing:
        raise HTTPException(status_code=404, detail="التحذير غير موجود")
    if existing["status"] != "resolved":
        raise HTTPException(status_code=409, detail="لا يمكن حذف التحذير إلا بعد حله")
    try:
        await pool.execute("DELETE FROM alerts WHERE id=$1::uuid", alert_id)
    except Exception:
        raise HTTPException(status_code=500, detail="فشل حذف التحذير")
    return {"success": True}


@router.delete("")
async def delete_all_alerts(status: Optional[str] = Query(None)):
    """Bulk-clear alerts. Optionally restrict to a single status; otherwise clears all."""
    pool = await get_pool()
    if status:
        result = await pool.execute("DELETE FROM alerts WHERE status=$1", status)
    else:
        result = await pool.execute("DELETE FROM alerts")
    deleted = int(result.split()[-1]) if result else 0
    return {"success": True, "deleted": deleted}
