---
name: BatchModel null-safe fromJson
description: Dart model fields that are Optional in the DB must use nullable-safe casts in fromJson to avoid TypeError crashes.
---

## Rule
All fields that are `Optional[...]` (Python) or can be NULL in the DB must use `as Type? ?? default` in Dart's fromJson, never bare `as String` or `as num`.

**Confirmed null fields that caused crashes:**
- `batches.shift` — Optional[str] in DB, was `json['shift'] as String` → fixed to `as String? ?? ''`
- `batch_materials.quantity` — was `(json['quantity'] as num).toDouble()` → fixed to `(json['quantity'] as num?)?.toDouble() ?? 0`

**Why:** Two test records (TEST-PVC-BLOCK, TEST-DEDUCT-001) had null shift, causing getBatches() to throw TypeError in Dart, which made batches screen and reports page both show "تعذر تحميل البيانات".

**How to apply:** Whenever adding a new field to fromJson, check if the Python model or DB column is Optional/nullable. If so, use `as Type?` with a fallback.
