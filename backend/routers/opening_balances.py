from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import Optional
from database import get_pool

router = APIRouter(prefix="/api/opening-balances", tags=["opening_balances"])


class OpeningBalanceCreate(BaseModel):
    material_id: str
    warehouse_type: Optional[str] = "mixer"
    balance: float
    balance_date: Optional[str] = None
    reason: Optional[str] = None
    created_by: Optional[str] = None


@router.get("")
async def get_opening_balances(
    material_id: Optional[str] = Query(None),
    warehouse_type: Optional[str] = Query(None),
):
    pool = await get_pool()
    conditions = ["1=1"]
    params = []
    i = 1
    if material_id:
        conditions.append(f"ob.material_id=${i}"); params.append(material_id); i += 1
    if warehouse_type:
        conditions.append(f"ob.warehouse_type=${i}"); params.append(warehouse_type); i += 1
    query = f"""
        SELECT ob.*, r.name AS material_name, r.unit
        FROM opening_balances ob
        JOIN raw_materials r ON r.id = ob.material_id
        WHERE {' AND '.join(conditions)}
        ORDER BY ob.balance_date DESC, ob.created_at DESC
    """
    rows = await pool.fetch(query, *params)
    return [dict(r) for r in rows]


@router.post("")
async def create_opening_balance(body: OpeningBalanceCreate):
    pool = await get_pool()
    try:
        row = await pool.fetchrow(
            """INSERT INTO opening_balances
               (material_id, warehouse_type, balance, balance_date, reason, created_by)
               VALUES ($1, $2, $3, COALESCE($4::date, CURRENT_DATE), $5, $6)
               ON CONFLICT (material_id, warehouse_type, balance_date)
               DO UPDATE SET balance=$3, reason=$5, created_by=$6
               RETURNING *""",
            body.material_id, body.warehouse_type, body.balance,
            body.balance_date, body.reason, body.created_by,
        )
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
    return dict(row)


@router.put("/{ob_id}")
async def update_opening_balance(ob_id: str, body: OpeningBalanceCreate):
    pool = await get_pool()
    row = await pool.fetchrow(
        """UPDATE opening_balances
           SET material_id=$1, warehouse_type=$2, balance=$3,
               balance_date=COALESCE($4::date, CURRENT_DATE), reason=$5, created_by=$6
           WHERE id=$7 RETURNING *""",
        body.material_id, body.warehouse_type, body.balance,
        body.balance_date, body.reason, body.created_by, ob_id,
    )
    if not row:
        raise HTTPException(status_code=404, detail="Not found")
    return dict(row)


@router.delete("/{ob_id}")
async def delete_opening_balance(ob_id: str):
    pool = await get_pool()
    await pool.execute("DELETE FROM opening_balances WHERE id=$1", ob_id)
    return {"success": True}
