import logging
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional
from database import get_pool
from materials_seed import export_raw_materials_seed

logger = logging.getLogger("plastic_factory.materials")

router = APIRouter(prefix="/api/materials", tags=["materials"])

# ── تعيين بادئة الكود حسب الفئة ──────────────────────────────────────────────
_CATEGORY_PREFIX: dict[str, str] = {
    "PVC":            "PVC",
    "سكراب":          "SCR",
    "زيوت وإضافات":  "OIL",
    "أصباغ":          "DYE",
    "بيكربونات":      "BIC",
    "لواصق":          "ADH",
    "خلطات":          "MIX",
    "مواد أساسية":    "MAT",
    "إضافات":         "ADD",
}
_DEFAULT_PREFIX = "MAT"


def _prefix_for(category: str) -> str:
    return _CATEGORY_PREFIX.get((category or "").strip(), _DEFAULT_PREFIX)


async def _generate_code(pool, category: str) -> str:
    """توليد كود فريد مختصر للمادة بناءً على فئتها. مثال: OIL-003

    يستخدم advisory lock على مستوى قاعدة البيانات لتجنب race condition
    عند الإضافة المتزامنة. يحاول حتى 50 مرة قبل الاستسلام.
    """
    prefix = _prefix_for(category)
    # advisory lock key ثابت لكل بادئة (hashبسيط)
    lock_key = hash(prefix) & 0x7FFFFFFF
    async with pool.acquire() as conn:
        await conn.execute(f"SELECT pg_advisory_xact_lock({lock_key})")
        # أعلى رقم مستخدم حالياً لهذه البادئة
        row = await conn.fetchrow(
            """SELECT MAX(CAST(REGEXP_REPLACE(code, '^[A-Z]+-', '') AS INTEGER)) AS max_num
               FROM raw_materials
               WHERE code SIMILAR TO $1""",
            f"{prefix}-[0-9]+",
        )
        next_num = (int(row["max_num"] or 0)) + 1
        for _ in range(50):
            candidate = f"{prefix}-{next_num:03d}"
            exists = await conn.fetchrow(
                "SELECT 1 FROM raw_materials WHERE code=$1", candidate
            )
            if not exists:
                return candidate
            next_num += 1
    # احتياطي نادر الحدوث
    import uuid
    return f"{prefix}-{uuid.uuid4().hex[:4].upper()}"


async def ensure_material_codes() -> None:
    """يُستدعى عند بدء الخادم — يملأ حقل code لأي مادة (نشطة أو غير نشطة)
    لم يُعيَّن لها كود بعد."""
    try:
        pool = await get_pool()
        # جميع المواد بغض النظر عن is_active
        rows = await pool.fetch(
            "SELECT id::text AS id, category FROM raw_materials WHERE (code IS NULL OR TRIM(code)='')"
        )
        if not rows:
            return
        logger.info(f"[materials] توليد أكواد لـ {len(rows)} مادة بدون كود...")
        for row in rows:
            code = await _generate_code(pool, row["category"])
            await pool.execute(
                "UPDATE raw_materials SET code=$1, updated_at=NOW() WHERE id=$2::uuid",
                code, row["id"],
            )
            logger.info(f"[materials]   {row['id']} → {code}")
        await export_raw_materials_seed()
        logger.info("[materials] اكتمل توليد الأكواد.")
    except Exception as exc:
        logger.warning(f"[materials] فشل توليد الأكواد: {exc}")


class MaterialUpsert(BaseModel):
    id: Optional[str] = None
    name: str
    code: Optional[str] = None
    category: Optional[str] = "عام"
    unit: Optional[str] = "كجم"
    min_stock: Optional[float] = 0
    cost_per_unit: Optional[float] = 0
    is_active: Optional[bool] = True
    notes: Optional[str] = None


@router.get("")
async def get_materials():
    pool = await get_pool()
    rows = await pool.fetch(
        "SELECT * FROM raw_materials WHERE is_active=true ORDER BY category, name"
    )
    return [dict(r) for r in rows]


@router.get("/all")
async def get_all_materials():
    pool = await get_pool()
    rows = await pool.fetch("SELECT * FROM raw_materials ORDER BY category, name")
    return [dict(r) for r in rows]


@router.post("/upsert")
async def upsert_material(body: MaterialUpsert):
    pool = await get_pool()
    # ── إذا لم يُعطَ كود، نولّده تلقائياً (فقط عند الإضافة أو إذا كان فارغاً) ──
    code = (body.code or "").strip() or None
    if body.id:
        # تعديل: إذا كان الكود فارغاً نجلب القديم، وإن كان هو الآخر فارغاً نولّد جديداً
        if code is None:
            existing = await pool.fetchrow(
                "SELECT code FROM raw_materials WHERE id=$1", body.id
            )
            existing_code = (existing["code"] or "").strip() if existing else ""
            code = existing_code if existing_code else await _generate_code(pool, body.category or "عام")
        row = await pool.fetchrow(
            """UPDATE raw_materials SET name=$1, code=$2, category=$3, unit=$4,
               min_stock=$5, cost_per_unit=$6, is_active=$7, notes=$8, updated_at=NOW()
               WHERE id=$9 RETURNING *""",
            body.name, code, body.category, body.unit, body.min_stock,
            body.cost_per_unit, body.is_active, body.notes, body.id,
        )
    else:
        # إضافة جديدة: نولّد الكود إن لم يُعطَ
        if code is None:
            code = await _generate_code(pool, body.category or "عام")
        row = await pool.fetchrow(
            """INSERT INTO raw_materials (id, name, code, category, unit, min_stock, cost_per_unit, is_active, notes)
               VALUES (gen_random_uuid(), $1, $2, $3, $4, $5, $6, $7, $8) RETURNING *""",
            body.name, code, body.category, body.unit, body.min_stock,
            body.cost_per_unit, body.is_active, body.notes,
        )
    await export_raw_materials_seed()
    return dict(row)


@router.delete("/{material_id}")
async def delete_material(material_id: str):
    pool = await get_pool()
    await pool.execute(
        "UPDATE raw_materials SET is_active=false, updated_at=NOW() WHERE id=$1", material_id
    )
    await export_raw_materials_seed()
    return {"success": True}
