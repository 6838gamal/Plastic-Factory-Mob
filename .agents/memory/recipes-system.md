---
name: Recipes system
description: How the recipe/formula system works — DB tables, API, and Flutter auto-fill integration.
---

## Rule
Recipes are keyed by `mixture_type_id` (UNIQUE constraint). The `recipe_items` table uses `material_name TEXT` as the key — it must match the exact label string used in `batch_entry_page.dart`'s `_fieldByName` map.

**Why:** The batch entry page uses fixed `TextEditingController` fields with Arabic labels. Mapping by name avoids needing foreign keys to `raw_materials` and keeps the recipe system decoupled from the materials table.

**How to apply:**
- `backend/routers/recipes.py` calls `ensure_tables()` on every request (idempotent `CREATE TABLE IF NOT EXISTS`). No schema.sql change needed.
- Auto-fill in `batch_entry_page.dart`: `_applyRecipe()` calls `/api/recipes/by-mixture/{id}` and fills matching controllers via `_fieldByName` map.
- `dataSourceProvider` lives in `auth_provider.dart` — do NOT redefine it elsewhere.
- Service worker cache key: bump to `flutter-app-cache-v20260609d` (last known value after this session's builds).
- Seed key is `lref_seeded_v3` — next bump must use `v4`.
- `raw_materials` must contain a row whose `name` exactly matches every hardcoded Arabic label used in `batch_entry_page.dart`'s `_fieldByName`/`pigmentDefs`/`additiveDefs` — otherwise that material is invisible on the admin/warehouse-keeper materials screens (which read from `/api/materials`) even though batch entry still accepts and saves it. When adding a new hardcoded field there, also insert a matching `raw_materials` row (and re-run `materials_seed.export_raw_materials_seed()` to refresh the durable JSON backup).
