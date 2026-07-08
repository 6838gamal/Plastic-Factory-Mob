---
name: Inventory summary provider consolidation
description: Why mixer/main warehouse balance cards went stale across screens, and the fix pattern.
---

Multiple screens (inventory_page.dart, warehouse_manager_page.dart, batch_entry_page.dart) each
defined their OWN local Riverpod FutureProvider hitting the same `GET /api/inventory/summary`
endpoint. Riverpod providers are compared by instance, so invalidating one screen's copy never
refreshed another screen's copy — mixer/main balance cards looked stale after transfers, receipts,
returns, or batch saves performed from a different screen, even though the backend data was
already correct.

**Why:** Backend deduction/transfer logic (backend/routers/batches.py, vouchers.py) was verified
correct via live end-to-end API testing — the bug was purely duplicated frontend provider state,
not a data/deduction bug.

**How to apply:** Use the single shared `inventorySummaryProvider` in
`lib/presentation/providers/reference_data_provider.dart` for ANY screen that displays inventory/
material balances. After ANY action that mutates inventory (receipt post, transfer confirm, return
post, withdrawal approve, opening balance, batch save), call
`ref.invalidate(inventorySummaryProvider)` — never rely on a screen-local copy of this fetch.
