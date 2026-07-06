---
name: Voucher item silent-drop bug (warehouse vouchers)
description: Why warehouse keeper vouchers could save with 0 items even though items were visibly added in the dialog
---

The receipt/transfer/withdrawal voucher dialogs (`_ReceiptVoucherDialog`, `_TransferVoucherDialog`,
`_WithdrawalVoucherDialog` in `warehouse_manager_page.dart`) used to build the items payload with
`.where((e) => e.name.isNotEmpty && e.qty > 0)` right before saving, silently dropping any row where
the keeper hadn't picked a material from the dropdown (name stays `''`) or left qty at 0/blank.

**Why:** A keeper could type a quantity without selecting the material (or vice versa), hit "Save",
and the voucher would save successfully but with an empty item list — with no error shown. Later,
submitting that voucher ("إرسال إلى الإدارة") fails with "لا يوجد بنود في السند" since it's genuinely
empty. From the user's perspective this looked like "everything disappeared" — data they entered
vanished without any feedback about which row was incomplete.

**How to apply:** Never silently filter/drop user-entered rows before persisting. Validate explicitly
and tell the user which item index is incomplete before allowing save. All three voucher dialogs now
check `_items[i].name.isEmpty || _items[i].qty <= 0` up front and show `أكمل بيانات البند رقم N` instead
of silently filtering. Apply the same explicit-validation pattern to any future list-of-rows form in
this app (e.g. batch material rows) instead of a bare `.where()` before submit.
