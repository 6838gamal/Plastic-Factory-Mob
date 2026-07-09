---
name: Batch deduction kg/gram unit mismatch
description: inventory.balance is stored per-material native unit (kg or gram), not always kg — deduction code must convert
---

## The convention
Across the whole app, `inventory.balance`, `inventory_transactions.quantity`, and `raw_materials.min_stock` are stored in each material's **own native unit** (`raw_materials.unit`, e.g. `كجم` or `جرام`), never normalized to kg. Flutter entry dialogs (opening balances, receive, transfer, admin override) label the field with the material's unit and save the raw number as-is; `Helpers.formatQuantityInKg`/`formatQuantityInKgCompact` convert to kg only for *display*. `dashboard.py`'s low-stock check (`i.balance <= r.min_stock`) also compares raw native-unit values directly — confirming this is the system-wide convention, not a bug in the Flutter/dashboard side.

**Why this matters:** `backend/routers/batches.py`'s `_extract_materials()` normalizes every batch material's quantity to KG via `_to_kg()` for internal aggregation. The deduction engine (`_apply_deductions`) used to compare/subtract that KG-normalized quantity directly against `inventory.balance` — comparing kg vs. grams for any gram-unit material (dyes/pigments), either falsely blocking batches ("insufficient balance") or silently over-deducting near-empty stock by 1000x, depending on direction.

## The fix
Added `_from_kg(qty_kg, unit)` (inverse of `_to_kg`) in `batches.py`. Both the sufficiency check and the actual deduction/write now convert the KG-normalized requirement back to the material's native unit via `_from_kg` before comparing to or writing `inventory.balance`/`inventory_transactions.quantity`; `_to_kg` is used only when formatting alert/error messages for humans.

**How to apply:** Unit resolution order when a material's mixer inventory row doesn't exist yet: `inv.unit` (joined row) → `raw_materials.unit` by id (explicit lookup) → payload `item.unit` → default `كجم`. Never trust only the payload unit — always check the row's inventory/raw_materials.unit first. Apply this same pattern (fetch/convert unit before touching `balance`) to any other router that writes `inventory.balance` from a KG-normalized quantity (checked: `machine_production.py`'s `_to_kg` usage is stats-only, doesn't touch balance, so it's fine as-is).

## Also found: duplicate raw_materials rows
Production DB (Render) has 2-3 duplicate `raw_materials` rows per name (same issue as the earlier "UUID→VARCHAR FK" duplicate-seed problem) — e.g. 3 different UUIDs all named "PVC صيني"/"مواد خام PVC صيني" family, most with zero or no inventory row at all. When a recipe's material name doesn't match the batch-entry dropdown's material name via the exact/prefix fuzzy-match rules in `_resolve_names_to_ids`, deduction can silently target the wrong (empty) duplicate. This is a data hygiene issue, not something to "fix" by inventing data — flag it to the user; they need to consolidate duplicates or enter opening balances for the correct IDs.
