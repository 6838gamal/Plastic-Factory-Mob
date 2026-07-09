---
name: Deduction UUID mismatch — name-based fallback
description: _apply_deductions now falls back to name lookup when UUID finds no mixer row; prevents 400 from duplicate-material UUID mismatch.
---

## Rule
When `inventory.material_id` in the mixer doesn't match the UUID Flutter sends in the batch, `_apply_deductions` falls back to a name-based lookup (same resolution order as `_resolve_names_to_ids`).

**Why:** The raw-materials table had duplicate rows for the same physical material — one set from an old DB (Render), another inserted by the seed restore. Each set had a different UUID. The transfer voucher was confirmed using UUID_A; the batch entry sent UUID_B. The deduction query found nothing for UUID_B → available=0 → HTTP 400.

**Root cause:** `restore_raw_materials_seed` used `ON CONFLICT (id) DO NOTHING`. When Render's old materials (old UUIDs) coexisted with the seed file's materials (new UUIDs but same names), both sets were inserted → duplicates.

**How to apply:**
- `_apply_deductions` step 3 (sufficiency check): after UUID lookup fails, try name-based lookup with exact → DB-prefix → Flutter-prefix order; store `_resolved_id` on item.
- `_apply_deductions` step 4 (actual deduction): `effective_id = item.get("_resolved_id") or item["material_id"]`; all upserts/transactions/alerts use `effective_id`.
- `restore_raw_materials_seed`: before inserting, check by UUID OR exact name; skip if found. Prevents future duplicate creation.

**Files changed:** `backend/routers/batches.py` (_apply_deductions), `backend/materials_seed.py` (restore_raw_materials_seed)
