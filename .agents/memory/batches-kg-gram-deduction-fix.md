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

## Duplicate raw_materials rows (widespread — resolved)
This app is prone to accumulating 2-3 `raw_materials` rows with the *exact same name* (repeated seed/import runs). Batch entry resolves a material by *name* (not id) when the client's stored id no longer exists, so an exact-duplicate name is a real hazard: the wrong (empty) twin can get matched, causing false "insufficient stock".

**Rule going forward:** raw_materials.name must stay globally unique among active rows. When duplicates appear: if one sibling holds real stock and the other(s) are zero in both warehouses, deactivate (`is_active=false`) the zero ones. If *all* siblings are zero (no signal which is "real"), keep exactly one active under the original unmodified name and deactivate the rest — never leave two active rows with an identical name, and never rename a material that's referenced by a fixed name constant elsewhere in code (see below).

## Fixed material-name constants (must match raw_materials.name exactly)
`lib/presentation/pages/worker/batch_entry_page.dart` hardcodes exact material names for dashboard/report columns (`_kNamePvc`, `_kNameDop`, `_kScrapNames`, `_kNameCalcium`, `_kNameWax`, `_kNameStabilizer`, `_kNameTitanium`). Renaming or deactivating the `raw_materials` row these point to silently zeroes that report indicator — grep this file for `_kName`/`_kScrapNames` before any bulk rename/dedup of materials.
