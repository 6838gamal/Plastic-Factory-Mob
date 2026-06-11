"""
Periodic Inventory Audit (الجرد الدوري) — admin-only router.

Workflow:
  1. POST /api/stock-take/sessions           — create session, snapshot system balances
  2. GET  /api/stock-take/sessions           — list all sessions
  3. GET  /api/stock-take/sessions/{id}      — get session + items
  4. PATCH /api/stock-take/sessions/{id}/items/{item_id} — record actual quantity (exact timestamp)
  5. POST /api/stock-take/sessions/{id}/close — finalise; log adjustments to audit_log
"""
from datetime import datetime, timezone
from typing import Optional
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from database import get_pool

router = APIRouter(prefix="/api/stock-take", tags=["stock_take"])

_NOW = lambda: datetime.now(timezone.utc)


# ── helpers ───────────────────────────────────────────────────────────────────
def _fmt(dt) -> Optional[str]:
    if dt is None:
        return None
    if hasattr(dt, "isoformat"):
        return dt.isoformat()
    return str(dt)


def _row(r) -> dict:
    d = dict(r)
    for k, v in d.items():
        if hasattr(v, "isoformat"):
            d[k] = v.isoformat()
    return d


# ── schemas ───────────────────────────────────────────────────────────────────
class SessionCreate(BaseModel):
    session_name: str
    warehouse_type: Optional[str] = "main"
    notes: Optional[str] = None
    created_by: Optional[str] = "admin"


class ActualQtyUpdate(BaseModel):
    actual_qty: float
    notes: Optional[str] = None


# ── endpoints ─────────────────────────────────────────────────────────────────

@router.post("/sessions", status_code=201)
async def create_session(body: SessionCreate):
    """
    Create a new stock-take session and snapshot current system balances
    for all materials in the specified warehouse.
    """
    pool = await get_pool()
    now = _NOW()

    session_id = await pool.fetchval("""
        INSERT INTO stock_take_sessions
          (session_name, warehouse_type, notes, created_by, status, created_at, updated_at)
        VALUES ($1, $2, $3, $4, 'open', $5, $5)
        RETURNING id
    """, body.session_name, body.warehouse_type, body.notes, body.created_by, now)

    # Snapshot current system inventory
    items = await pool.fetch("""
        SELECT i.material_id, rm.name AS material_name, rm.unit,
               i.warehouse_type, i.balance
        FROM inventory i
        JOIN raw_materials rm ON rm.id::text = i.material_id::text
        WHERE i.warehouse_type = $1
        ORDER BY rm.name
    """, body.warehouse_type)

    for it in items:
        await pool.execute("""
            INSERT INTO stock_take_items
              (session_id, material_id, material_name, warehouse_type,
               unit, system_qty, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7)
        """, session_id, it["material_id"], it["material_name"],
            it["warehouse_type"], it["unit"], float(it["balance"]), now)

    # Audit log
    await pool.execute("""
        INSERT INTO audit_log (table_name, record_id, action, description, created_at)
        VALUES ('stock_take_sessions', $1::text, 'create',
                $2, $3)
    """, str(session_id), f"بدء جرد دوري: {body.session_name}", now)

    session = await pool.fetchrow(
        "SELECT * FROM stock_take_sessions WHERE id=$1", session_id
    )
    return _row(session)


@router.get("/sessions")
async def list_sessions():
    pool = await get_pool()
    rows = await pool.fetch("""
        SELECT s.*,
               COUNT(si.id)                        AS total_items,
               COUNT(si.id) FILTER (WHERE si.actual_qty IS NOT NULL) AS counted_items,
               COUNT(si.id) FILTER (WHERE si.actual_qty IS NOT NULL
                                      AND ABS(si.actual_qty - si.system_qty) > 0.01) AS diff_items
        FROM stock_take_sessions s
        LEFT JOIN stock_take_items si ON si.session_id = s.id
        GROUP BY s.id
        ORDER BY s.created_at DESC
    """)
    return [_row(r) for r in rows]


@router.get("/sessions/{session_id}")
async def get_session(session_id: str):
    pool = await get_pool()
    session = await pool.fetchrow(
        "SELECT * FROM stock_take_sessions WHERE id=$1", session_id
    )
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    items = await pool.fetch("""
        SELECT si.*,
               CASE WHEN si.actual_qty IS NOT NULL
                    THEN ROUND((si.actual_qty - si.system_qty)::numeric, 3)
                    ELSE NULL END AS difference,
               CASE WHEN si.system_qty > 0 AND si.actual_qty IS NOT NULL
                    THEN ROUND(((si.actual_qty - si.system_qty) / si.system_qty * 100)::numeric, 2)
                    ELSE NULL END AS diff_pct
        FROM stock_take_items si
        ORDER BY si.material_name
    """)

    result = _row(session)
    result["items"] = [_row(it) for it in items]
    return result


@router.patch("/sessions/{session_id}/items/{item_id}")
async def update_item(session_id: str, item_id: str, body: ActualQtyUpdate):
    """Record the actual counted quantity for a specific material (with exact timestamp)."""
    pool = await get_pool()

    session = await pool.fetchrow(
        "SELECT status FROM stock_take_sessions WHERE id=$1", session_id
    )
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    if session["status"] == "closed":
        raise HTTPException(status_code=400, detail="لا يمكن تعديل جرد مغلق")

    now = _NOW()
    row = await pool.fetchrow("""
        UPDATE stock_take_items
        SET actual_qty = $1,
            notes      = COALESCE($2, notes),
            counted_at = $3
        WHERE id = $4 AND session_id = $5
        RETURNING *,
          ROUND((actual_qty - system_qty)::numeric, 3) AS difference,
          CASE WHEN system_qty > 0
               THEN ROUND(((actual_qty - system_qty) / system_qty * 100)::numeric, 2)
               ELSE NULL END AS diff_pct
    """, body.actual_qty, body.notes, now, item_id, session_id)

    if not row:
        raise HTTPException(status_code=404, detail="Item not found")

    await pool.execute("""
        UPDATE stock_take_sessions SET updated_at=$1 WHERE id=$2
    """, now, session_id)

    return _row(row)


@router.post("/sessions/{session_id}/close")
async def close_session(session_id: str):
    """Close the session and log any material differences to audit_log."""
    pool = await get_pool()
    session = await pool.fetchrow(
        "SELECT * FROM stock_take_sessions WHERE id=$1", session_id
    )
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    if session["status"] == "closed":
        raise HTTPException(status_code=400, detail="الجرد مغلق بالفعل")

    now = _NOW()
    items = await pool.fetch("""
        SELECT * FROM stock_take_items WHERE session_id=$1 AND actual_qty IS NOT NULL
    """, session_id)

    diffs = []
    for it in items:
        diff = float(it["actual_qty"]) - float(it["system_qty"])
        if abs(diff) > 0.001:
            diffs.append({
                "material": it["material_name"],
                "system": float(it["system_qty"]),
                "actual": float(it["actual_qty"]),
                "diff": round(diff, 3),
                "unit": it["unit"],
            })

    await pool.execute("""
        UPDATE stock_take_sessions
        SET status='closed', closed_at=$1, updated_at=$1
        WHERE id=$2
    """, now, session_id)

    # Audit log for the session closure
    summary = (f"إغلاق جرد: {session['session_name']} | "
               f"{len(items)} صنف تم جرده | "
               f"{len(diffs)} فروقات")
    await pool.execute("""
        INSERT INTO audit_log (table_name, record_id, action, description, created_at)
        VALUES ('stock_take_sessions', $1::text, 'close', $2, $3)
    """, str(session_id), summary, now)

    return {
        "closed": True,
        "closed_at": now.isoformat(),
        "counted_items": len(items),
        "differences": diffs,
    }


@router.get("/sessions/{session_id}/report")
async def session_report(session_id: str):
    """Full comparison report for a session."""
    pool = await get_pool()
    session = await pool.fetchrow(
        "SELECT * FROM stock_take_sessions WHERE id=$1", session_id
    )
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    items = await pool.fetch("""
        SELECT *,
          CASE WHEN actual_qty IS NOT NULL
               THEN ROUND((actual_qty - system_qty)::numeric, 3) END AS difference,
          CASE WHEN system_qty > 0 AND actual_qty IS NOT NULL
               THEN ROUND(((actual_qty - system_qty) / system_qty * 100)::numeric, 2) END AS diff_pct
        FROM stock_take_items
        WHERE session_id=$1
        ORDER BY material_name
    """, session_id)

    rows = [_row(r) for r in items]
    counted  = sum(1 for r in rows if r.get("actual_qty") is not None)
    matched  = sum(1 for r in rows if r.get("difference") is not None and abs(float(r["difference"])) <= 0.01)
    over     = sum(1 for r in rows if r.get("difference") is not None and float(r["difference"]) > 0.01)
    short    = sum(1 for r in rows if r.get("difference") is not None and float(r["difference"]) < -0.01)

    return {
        "session": _row(session),
        "items": rows,
        "summary": {
            "total_items": len(rows),
            "counted": counted,
            "pending": len(rows) - counted,
            "matched": matched,
            "over_stock": over,
            "short_stock": short,
        },
    }
