---
name: inventory_summary VIEW definition
description: How total_in/total_out/current_balance are computed; which transaction types map to which column.
---

# inventory_summary VIEW

The VIEW is NOT in schema.sql (file may not exist). It is rebuilt idempotently in `_init_db()` in `backend/main.py` via DROP IF EXISTS CASCADE + CREATE VIEW.

**Why:** DROP + CREATE is needed because CREATE OR REPLACE fails when column count changes.

## Column mapping

| VIEW column       | Source transaction_types                          |
|-------------------|---------------------------------------------------|
| `current_balance` | `inventory.balance` (raw, updated by all ops)    |
| `total_in`        | `'in'`, `'return'`, **`'transfer_in'`**          |
| `total_out`       | `'out'`, **`'transfer_out'`**                    |
| `total_transfers` | net of transfer_in − transfer_out (kept for compat) |
| `total_adjustments_pos/neg` | `'adjustment'` split by balance_after vs balance_before |
| `opening_balance` | latest row from `opening_balances` table         |

**Why transfer_in is in total_in:** When transferring main → mixer, the mixer card "وارد" chip must reflect the incoming transfer. Previously it only counted direct receipts, leaving "وارد" = 0 even after a real transfer.

**Why transfer_out is in total_out:** When transferring main → mixer, the main warehouse card "منصرف" should reflect materials sent out.

## How to apply
Any change to this VIEW must be done via DROP + CREATE in the `_init_db` migration block (after column migrations). Never use CREATE OR REPLACE.
