---
name: daily_reports schema mismatch
description: Column names in daily_reports differ from what the reports.py code expects
---

## Actual DB columns (as of June 2026)
total_batches, total_produced, total_production_kg, total_scrap_kg, total_waste_kg,
total_inputs, total_alerts, day_cost, efficiency_pct, deviation_pct, waste_pct,
most_consumed_material, least_consumed_material, snapshot, is_locked, locked_at,
generated_at, created_at, updated_at, notes, total_waste, total_scrap (added via ALTER TABLE).

## Mismatch fixed
Code used `total_waste` / `total_scrap` but DB had `total_waste_kg` / `total_scrap_kg`.
Fix: added `total_waste` and `total_scrap` as alias columns via `ALTER TABLE ... ADD COLUMN IF NOT EXISTS`.

**Why:** Schema was created before code was finalized; column names diverged. The `_kg` suffix columns still exist and hold the authoritative values.
