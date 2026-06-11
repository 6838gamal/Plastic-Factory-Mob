from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional, List
from database import get_pool

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
    # Migrate existing UUID column → TEXT (idempotent)
    await pool.execute("""
        DO $$
        BEGIN
            -- Drop FK if still present
            IF EXISTS (
                SELECT 1 FROM information_schema.table_constraints
                WHERE table_name='recipes'
                  AND constraint_type='FOREIGN KEY'
                  AND constraint_name LIKE '%mixture_type_id%'
            ) THEN
                ALTER TABLE recipes DROP CONSTRAINT IF EXISTS recipes_mixture_type_id_fkey;
            END IF;
            -- Convert UUID → TEXT if needed
            IF EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_name='recipes'
                  AND column_name='mixture_type_id'
                  AND data_type='uuid'
            ) THEN
                ALTER TABLE recipes ALTER COLUMN mixture_type_id TYPE TEXT USING mixture_type_id::text;
            END IF;
        END$$;
    """)


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
async def _recipe_with_items(pool, recipe_id: str):
    recipe = await pool.fetchrow("SELECT * FROM recipes WHERE id=$1", recipe_id)
    if not recipe:
        return None
    items = await pool.fetch(
        "SELECT * FROM recipe_items WHERE recipe_id=$1 ORDER BY material_name",
        recipe_id,
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
            rec["id"],
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
        recipe["id"],
    )
    return {**dict(recipe), "items": [dict(i) for i in items]}


@router.post("")
async def upsert_recipe(body: RecipeUpsert):
    """Creates or updates a recipe for the given mixture type."""
    await ensure_tables()
    pool = await get_pool()

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
            recipe_id = recipe["id"]

            # Replace all items
            await conn.execute("DELETE FROM recipe_items WHERE recipe_id=$1", recipe_id)
            for item in body.items:
                if item.standard_qty > 0:
                    await conn.execute(
                        """INSERT INTO recipe_items (id, recipe_id, material_name, standard_qty, unit)
                           VALUES (gen_random_uuid(), $1, $2, $3, $4)""",
                        recipe_id, item.material_name, item.standard_qty, item.unit,
                    )

    return await _recipe_with_items(await get_pool(), recipe_id)


@router.delete("/{recipe_id}")
async def delete_recipe(recipe_id: str):
    await ensure_tables()
    pool = await get_pool()
    await pool.execute(
        "UPDATE recipes SET is_active=false, updated_at=NOW() WHERE id=$1", recipe_id
    )
    return {"success": True}
