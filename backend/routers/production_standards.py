"""
Production Standards router — معايير الإنتاج

Manages gram-per-pair consumption standards for each product type.
Business rules:
 - Cannot delete a standard that is used in production records.
 - All CRUD actions are logged to audit_log.
 - standard_kg_per_pair is computed as standard_gram_per_pair / 1000.
"""
from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import Optional
from database import get_pool

router = APIRouter(prefix="/api/production-standards", tags=["production_standards"])


class StandardCreate(BaseModel):
    product_name: str
    product_code: Optional[str] = None
    standard_gram_per_pair: float
    is_active: Optional[bool] = True
    notes: Optional[str] = None


async def _ensure_table(pool):
    """Create production_standards table idempotently."""
    await pool.execute("""
        CREATE TABLE IF NOT EXISTS production_standards (
            id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            product_name    VARCHAR(200) NOT NULL,
            product_code    VARCHAR(50),
            standard_gram_per_pair DECIMAL(10,3) NOT NULL CHECK (standard_gram_per_pair > 0),
            is_active       BOOLEAN NOT NULL DEFAULT TRUE,
            notes           TEXT,
            created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
    """)
    await pool.execute(
        "CREATE INDEX IF NOT EXISTS idx_production_standards_active "
        "ON production_standards (is_active, product_name)"
    )


@router.get("")
async def get_standards(
    active_only: bool = Query(False),
):
    pool = await get_pool()
    await _ensure_table(pool)
    if active_only:
        rows = await pool.fetch(
            "SELECT *, (standard_gram_per_pair / 1000.0) AS standard_kg_per_pair "
            "FROM production_standards WHERE is_active = TRUE ORDER BY product_name"
        )
    else:
        rows = await pool.fetch(
            "SELECT *, (standard_gram_per_pair / 1000.0) AS standard_kg_per_pair "
            "FROM production_standards ORDER BY product_name"
        )
    return [dict(r) for r in rows]


@router.get("/by-product")
async def get_standard_by_product(name: str = Query(...)):
    """Lookup active standard by product name (case-insensitive)."""
    pool = await get_pool()
    await _ensure_table(pool)
    row = await pool.fetchrow(
        "SELECT *, (standard_gram_per_pair / 1000.0) AS standard_kg_per_pair "
        "FROM production_standards WHERE LOWER(product_name) = LOWER($1) AND is_active = TRUE "
        "ORDER BY updated_at DESC LIMIT 1",
        name,
    )
    if not row:
        return None
    return dict(row)


@router.get("/{standard_id}")
async def get_standard(standard_id: str):
    pool = await get_pool()
    await _ensure_table(pool)
    row = await pool.fetchrow(
        "SELECT *, (standard_gram_per_pair / 1000.0) AS standard_kg_per_pair "
        "FROM production_standards WHERE id=$1",
        standard_id,
    )
    if not row:
        raise HTTPException(status_code=404, detail="المعيار غير موجود")
    return dict(row)


@router.post("")
async def create_standard(body: StandardCreate):
    pool = await get_pool()
    await _ensure_table(pool)
    row = await pool.fetchrow(
        """INSERT INTO production_standards
           (id, product_name, product_code, standard_gram_per_pair, is_active, notes)
           VALUES (gen_random_uuid(), $1, $2, $3, $4, $5)
           RETURNING *, (standard_gram_per_pair / 1000.0) AS standard_kg_per_pair""",
        body.product_name, body.product_code, body.standard_gram_per_pair,
        body.is_active, body.notes,
    )
    await pool.execute(
        """INSERT INTO audit_log (id, action, table_name, record_id, description)
           VALUES (gen_random_uuid(), 'create', 'production_standards', $1, $2)""",
        str(row["id"]),
        f"إنشاء معيار إنتاج: {body.product_name} — {body.standard_gram_per_pair} جرام/زوج",
    )
    return dict(row)


@router.put("/{standard_id}")
async def update_standard(standard_id: str, body: StandardCreate):
    pool = await get_pool()
    await _ensure_table(pool)
    old = await pool.fetchrow(
        "SELECT * FROM production_standards WHERE id=$1", standard_id
    )
    if not old:
        raise HTTPException(status_code=404, detail="المعيار غير موجود")

    row = await pool.fetchrow(
        """UPDATE production_standards SET
           product_name=$1, product_code=$2, standard_gram_per_pair=$3,
           is_active=$4, notes=$5, updated_at=NOW()
           WHERE id=$6
           RETURNING *, (standard_gram_per_pair / 1000.0) AS standard_kg_per_pair""",
        body.product_name, body.product_code, body.standard_gram_per_pair,
        body.is_active, body.notes, standard_id,
    )
    import json as _json
    await pool.execute(
        """INSERT INTO audit_log
           (id, action, table_name, record_id, old_values, new_values, description)
           VALUES (gen_random_uuid(), 'update', 'production_standards', $1, $2, $3, $4)""",
        standard_id,
        _json.dumps({
            "product_name": old["product_name"],
            "standard_gram_per_pair": float(old["standard_gram_per_pair"]),
            "is_active": old["is_active"],
            "notes": old["notes"],
        }),
        _json.dumps({
            "product_name": body.product_name,
            "standard_gram_per_pair": body.standard_gram_per_pair,
            "is_active": body.is_active,
            "notes": body.notes,
        }),
        (
            f"تعديل معيار: {old['product_name']} "
            f"({old['standard_gram_per_pair']}→{body.standard_gram_per_pair} جرام/زوج)"
        ),
    )
    return dict(row)


@router.delete("/{standard_id}")
async def delete_standard(standard_id: str):
    pool = await get_pool()
    await _ensure_table(pool)
    # Check usage in production records — do NOT swallow errors (silent 0 is unsafe)
    used = await pool.fetchval(
        "SELECT COUNT(*) FROM machine_production WHERE standard_id=$1", standard_id
    )
    if used and used > 0:
        raise HTTPException(
            status_code=400,
            detail=(
                f"لا يمكن حذف هذا المعيار — مستخدم في {used} سجل إنتاج. "
                "يمكنك تعطيله بدلاً من حذفه."
            ),
        )
    std = await pool.fetchrow(
        "SELECT product_name FROM production_standards WHERE id=$1", standard_id
    )
    if not std:
        raise HTTPException(status_code=404, detail="المعيار غير موجود")
    await pool.execute("DELETE FROM production_standards WHERE id=$1", standard_id)
    await pool.execute(
        """INSERT INTO audit_log (id, action, table_name, record_id, description)
           VALUES (gen_random_uuid(), 'delete', 'production_standards', $1, $2)""",
        standard_id,
        f"حذف معيار إنتاج: {std['product_name']}",
    )
    return {"success": True}
