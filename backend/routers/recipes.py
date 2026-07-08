from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional, List
from database import get_pool
from materials_seed import export_raw_materials_seed

router = APIRouter(prefix="/api/recipes", tags=["recipes"])

# ── DB table init ──────────────────────────────────────────────────────────
async def ensure_tables():
    pool = await get_pool()
    # Create tables with TEXT mixture_type_id (no FK — Flutter uses plain string IDs)
    await pool.execute("""
        CREATE TABLE IF NOT EXISTS recipes (
            id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            mixture_type_id TEXT,
            name            TEXT NOT NULL,
            notes           TEXT,
            is_active       BOOLEAN DEFAULT true,
            created_at      TIMESTAMPTZ DEFAULT NOW(),
            updated_at      TIMESTAMPTZ DEFAULT NOW(),
            UNIQUE(mixture_type_id)
        );
        CREATE TABLE IF NOT EXISTS recipe_items (
            id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            recipe_id     UUID REFERENCES recipes(id) ON DELETE CASCADE,
            material_name TEXT NOT NULL,
            standard_qty  NUMERIC(12,4) DEFAULT 0,
            unit          TEXT DEFAULT 'كجم',
            created_at    TIMESTAMPTZ DEFAULT NOW()
        );
    """)
    # Migrate: add missing columns idempotently using individual ALTER TABLE statements
    migrations = [
        """ALTER TABLE recipes ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW()""",
        """ALTER TABLE recipes ADD COLUMN IF NOT EXISTS notes TEXT""",
        """ALTER TABLE recipes ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true""",
        # recipe_items: old schema had material_id + quantity as NOT NULL; drop both
        # constraints so we can insert rows with only material_name/standard_qty.
        """ALTER TABLE recipe_items ALTER COLUMN material_id DROP NOT NULL""",
        """ALTER TABLE recipe_items ALTER COLUMN quantity DROP NOT NULL""",
        """ALTER TABLE recipe_items ALTER COLUMN quantity SET DEFAULT 0""",
    ]
    for stmt in migrations:
        try:
            await pool.execute(stmt)
        except Exception:
            pass  # column already exists, no constraint to drop, or table not yet created

    # Convert mixture_type_id UUID → TEXT if needed (run only when type is uuid)
    uuid_cols = await pool.fetch(
        """SELECT 1 FROM information_schema.columns
           WHERE table_name='recipes' AND column_name='mixture_type_id' AND data_type='uuid'"""
    )
    if uuid_cols:
        await pool.execute(
            "ALTER TABLE recipes DROP CONSTRAINT IF EXISTS recipes_mixture_type_id_fkey"
        )
        await pool.execute(
            "ALTER TABLE recipes ALTER COLUMN mixture_type_id TYPE TEXT USING mixture_type_id::text"
        )

    # Ensure UNIQUE index on mixture_type_id exists (required for ON CONFLICT)
    await pool.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS recipes_mixture_type_id_key ON recipes (mixture_type_id)"
    )

    # Normalized-name uniqueness on raw_materials, so recipe items can never
    # race-create duplicate materials for the same name (matches the
    # case-insensitive/trimmed matching used by batch-entry deduction).
    try:
        await pool.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS raw_materials_norm_name_key "
            "ON raw_materials (LOWER(TRIM(name)))"
        )
    except Exception:
        # Existing data already has case/whitespace-variant duplicate names;
        # leave them as-is (do not delete production data), the ON CONFLICT
        # insert below simply falls back to relying on the pre-insert
        # existence check in that case.
        pass


# ── Pydantic models ────────────────────────────────────────────────────────
class RecipeItemIn(BaseModel):
    material_name: str
    standard_qty: float = 0
    unit: str = "كجم"


class RecipeUpsert(BaseModel):
    mixture_type_id: str
    name: str
    notes: Optional[str] = None
    items: List[RecipeItemIn] = []


# ── Helpers ────────────────────────────────────────────────────────────────
async def _recipe_with_items(pool, recipe_id):
    recipe_id_str = str(recipe_id)  # recipe_items.recipe_id is TEXT
    recipe = await pool.fetchrow("SELECT * FROM recipes WHERE id=$1::uuid", recipe_id_str)
    if not recipe:
        return None
    items = await pool.fetch(
        "SELECT * FROM recipe_items WHERE recipe_id=$1 ORDER BY material_name",
        recipe_id_str,
    )
    return {**dict(recipe), "items": [dict(i) for i in items]}


# ── Endpoints ──────────────────────────────────────────────────────────────
@router.get("")
async def list_recipes():
    await ensure_tables()
    pool = await get_pool()
    recipes = await pool.fetch(
        """SELECT r.*, mt.name as mixture_type_name
           FROM recipes r
           LEFT JOIN mixture_types mt ON mt.id::text = r.mixture_type_id
           WHERE r.is_active=true ORDER BY r.created_at"""
    )
    result = []
    for rec in recipes:
        items = await pool.fetch(
            "SELECT * FROM recipe_items WHERE recipe_id=$1 ORDER BY material_name",
            str(rec["id"]),  # recipe_items.recipe_id is TEXT, not UUID
        )
        result.append({**dict(rec), "items": [dict(i) for i in items]})
    return result


@router.get("/by-mixture/{mixture_type_id}")
async def get_recipe_by_mixture(mixture_type_id: str):
    """Returns the recipe for a given mixture type, used for auto-fill on batch entry."""
    await ensure_tables()
    pool = await get_pool()
    recipe = await pool.fetchrow(
        "SELECT * FROM recipes WHERE mixture_type_id=$1 AND is_active=true",
        mixture_type_id,
    )
    if not recipe:
        return None
    items = await pool.fetch(
        "SELECT * FROM recipe_items WHERE recipe_id=$1 ORDER BY material_name",
        str(recipe["id"]),  # recipe_items.recipe_id is TEXT, not UUID
    )
    return {**dict(recipe), "items": [dict(i) for i in items]}


@router.post("")
async def upsert_recipe(body: RecipeUpsert):
    """Creates or updates a recipe for the given mixture type."""
    await ensure_tables()
    pool = await get_pool()

    created_material = False
    async with pool.acquire() as conn:
        async with conn.transaction():
            # Upsert the recipe header
            recipe = await conn.fetchrow(
                """INSERT INTO recipes (id, mixture_type_id, name, notes, is_active, updated_at)
                   VALUES (gen_random_uuid(), $1, $2, $3, true, NOW())
                   ON CONFLICT (mixture_type_id) DO UPDATE
                     SET name=$2, notes=$3, is_active=true, updated_at=NOW()
                   RETURNING *""",
                body.mixture_type_id, body.name, body.notes,
            )
            recipe_id = str(recipe["id"])  # recipe_items.recipe_id is TEXT, not UUID

            # Replace all items
            await conn.execute("DELETE FROM recipe_items WHERE recipe_id=$1", recipe_id)
            for item in body.items:
                if item.standard_qty > 0:
                    await conn.execute(
                        """INSERT INTO recipe_items (id, recipe_id, material_name, standard_qty, unit)
                           VALUES (gen_random_uuid(), $1, $2, $3, $4)""",
                        recipe_id, item.material_name, item.standard_qty, item.unit,
                    )
                    # Recipes only carry a free-text material_name, with no FK
                    # to raw_materials. Any material used in a recipe must show
                    # up on the warehouse keeper's / admin's raw-materials
                    # screens, so ensure a matching row exists there — this is
                    # also what lets batch-entry deduction resolve the name to
                    # an actual inventory item. Matching is case-insensitive +
                    # trimmed to match the resolution logic in batches.py, and
                    # relies on the normalized-name unique index (created in
                    # ensure_tables) plus ON CONFLICT to stay race-safe under
                    # concurrent recipe upserts. Never overwrite an existing
                    # material; only fill the gap when one is missing.
                    row = await conn.fetchrow(
                        "SELECT 1 FROM raw_materials WHERE LOWER(TRIM(name)) = LOWER(TRIM($1))",
                        item.material_name,
                    )
                    if not row:
                        # Use a savepoint (nested transaction) for the insert
                        # attempt: if the normalized-name unique index is
                        # absent (legacy duplicate data blocked its creation
                        # in ensure_tables) the ON CONFLICT clause itself can
                        # raise, and without a savepoint that would abort the
                        # whole outer recipe-upsert transaction.
                        try:
                            async with conn.transaction():
                                await conn.execute(
                                    """INSERT INTO raw_materials (id, name, category, unit, min_stock, is_active)
                                       VALUES (gen_random_uuid(), $1, 'من الوصفات', $2, 0, true)
                                       ON CONFLICT (LOWER(TRIM(name))) DO NOTHING""",
                                    item.material_name, item.unit,
                                )
                            created_material = True
                        except Exception:
                            async with conn.transaction():
                                await conn.execute(
                                    """INSERT INTO raw_materials (id, name, category, unit, min_stock, is_active)
                                       VALUES (gen_random_uuid(), $1, 'من الوصفات', $2, 0, true)""",
                                    item.material_name, item.unit,
                                )
                            created_material = True

    if created_material:
        await export_raw_materials_seed()
    return await _recipe_with_items(await get_pool(), recipe_id)


@router.delete("/{recipe_id}")
async def delete_recipe(recipe_id: str):
    await ensure_tables()
    pool = await get_pool()
    await pool.execute(
        "UPDATE recipes SET is_active=false, updated_at=NOW() WHERE id=$1", recipe_id
    )
    return {"success": True}
