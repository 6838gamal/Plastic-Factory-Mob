---
name: UUID→VARCHAR schema migration
description: DB schema used UUID for app-provided ID columns; Flutter stores plain strings from SharedPreferences — caused asyncpg DataError on batch/production save.
---

## The Rule
Columns populated by **application-provided identifiers** (worker_id, mixer_id, product_id, mixture_type_id, machine_id in batches/machine_production/alerts) must be VARCHAR, not UUID. Only auto-generated PK columns (`id`) and material references (`inventory.material_id → raw_materials.id`) should stay UUID.

**Why:** Flutter stores dropdown values (workers, mixers, products, mixture types, machines) in SharedPreferences as arbitrary strings, not UUIDs. asyncpg tries to coerce `$N` parameter to UUID when the column type is UUID → `DataError: invalid UUID` on every INSERT/query.

**How to apply:**
- In `_init_db()` → `_drop_fks` list: drop FK constraints that reference UUID PKs from VARCHAR columns BEFORE altering types.
- In `_init_db()` → `_uuid_to_varchar` list: ALTER TABLE ... ALTER COLUMN ... TYPE VARCHAR(100) USING col::text for all app-provided ID columns.
- Do NOT convert `inventory.material_id` or `inventory_transactions.material_id` — they join to `raw_materials.id` (UUID PKs from API) and are blocked by `inventory_summary` view anyway.
- inventory_summary view blocks `inventory.material_id` type change — leave as UUID; real material_ids from API are valid UUIDs.

## Columns converted to VARCHAR
- `batches`: worker_id, mixer_id, product_id, mixture_type_id
- `machine_production`: machine_id, product_id, worker_id
- `alerts`: material_id, batch_id, machine_id

## Alert status update bug fixed
`PUT /api/alerts/{id}/status` was setting `resolved_at=NOW()` for all status changes. Fixed: only set `resolved_at` when `status='resolved'`.

## Missing columns added via migration
- `alerts`: worker_id VARCHAR(50), worker_name VARCHAR(200), assigned_to VARCHAR(200)
- `machine_production`: batch_id VARCHAR(50)
