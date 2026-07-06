---
name: audit/inventory date string asyncpg fix
description: audit.py and inventory.py were passing raw date strings to asyncpg for TIMESTAMPTZ comparisons; fixed with _parse_dt() helper.
---

## Rule
asyncpg requires Python datetime objects for TIMESTAMPTZ column params. Raw strings cause 500 errors.

**Affected routers fixed:**
- `backend/routers/audit.py` — added `_parse_dt(s, end_of_day=False)` helper; `to` filter uses `end_of_day=True` and strict `<` (next-day midnight) for inclusive date range.
- `backend/routers/inventory.py` (transactions endpoint) — same pattern applied inline.

**Already correct:** machine_production.py uses `dt.fromisoformat(from_.replace("Z", ""))`, reports.py uses `_parse_dt()`.

**Why:** Flutter sends dates as ISO strings (with or without T/Z); asyncpg needs datetime objects; TIMESTAMPTZ mismatch causes internal 500.
