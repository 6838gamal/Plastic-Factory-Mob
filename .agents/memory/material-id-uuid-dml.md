---
name: material_id ::uuid cast in DML
description: asyncpg does NOT auto-cast Python str to UUID for parameterized INSERT/UPDATE/DELETE; every material_id param must use $N::uuid in SQL.
---

## Rule
Every parameter (`$N`) representing `material_id` passed as a Python `str` to any DML query (`INSERT`, `UPDATE`, `DELETE`, `SELECT … WHERE material_id=$N`) against `inventory` or `inventory_transactions` tables **must** have an explicit `::uuid` suffix in the SQL string.

**Why:** `inventory.material_id` and `inventory_transactions.material_id` are `UUID NOT NULL` columns (they stay UUID because they reference `raw_materials.id`). asyncpg passes Python `str` values as PostgreSQL `text` type; PostgreSQL will not implicitly cast `text → uuid` in parameterized queries, causing silent query failures or 500 errors on Render's Postgres (strict type enforcement).

**How to apply:**
- `SELECT … WHERE material_id=$1` → `WHERE material_id=$1::uuid`
- `INSERT INTO inventory (id, material_id, …) VALUES (gen_random_uuid(), $1, …)` → `VALUES (gen_random_uuid(), $1::uuid, …)`
- `UPDATE inventory SET … WHERE material_id = $N` → `WHERE material_id = $N::uuid`
- `DELETE FROM inventory_transactions WHERE material_id=$N` → `WHERE material_id=$N::uuid`

**Routers fixed (all 6):**
- `backend/routers/inventory.py` — transfer, balance, transactions, reset-material, reset-material-both, GET material/{id}, GET transactions filter
- `backend/routers/batches.py` — pre-check balance, deduct loop, reverse loop
- `backend/routers/machine_production.py` — add/remove scrap inventory
- `backend/routers/opening_balances.py` — upsert inventory on opening balance create/update
- `backend/routers/shift_handover.py` — _add_to_scrap_warehouse helper
- `backend/routers/vouchers.py` — already used ::uuid correctly (reference pattern)

**Note:** JOIN conditions (`ON rm.id::text = i.material_id::text`) use `::text` on both sides (separate fix, see material-id-uuid-cast.md); DML params use `::uuid` on the parameter side.
