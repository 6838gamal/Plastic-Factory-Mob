---
name: Inventory full reset (تصفير بيانات مادة)
description: How "reset all details" for a material/warehouse works, since inventory_summary fields are computed, not stored.
---

Most inventory_summary columns (total_in, total_out, total_transfers, total_adjustments_pos/neg, opening_balance)
are NOT stored directly — they are computed on the fly from `inventory_transactions` and `opening_balances` rows.

**Why this matters:** setting `inventory.balance = 0` (the old "تصفير الرصيد" admin action) only zeroed the
current balance shown; total_in/total_out/etc kept showing old historical totals because the underlying
transaction rows were untouched.

**How to apply:** a true "zero everything for this material" action must DELETE the underlying
`inventory_transactions` and `opening_balances` rows for that `material_id` + `warehouse_type` (not just
update `inventory.balance`), then log one `audit_log` entry (action='reset') for traceability. This is
irreversible — always require an explicit confirm checkbox in the UI before calling it.
