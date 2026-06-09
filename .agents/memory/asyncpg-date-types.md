---
name: asyncpg date type requirement
description: asyncpg requires datetime.date objects for DATE columns, not Python strings
---

## Rule
Never pass a Python `str` like `"2026-06-09"` to asyncpg for a `DATE` column parameter. asyncpg will raise:
`DataError: invalid input for query argument $N: '2026-06-09' ('str' object has no attribute 'toordinal')`

## How to apply
- In Pydantic models: use `Optional[date]` (from `datetime import date`) instead of `str` for date fields.
- When date comes in as a string from a Query param: convert with `datetime.date.fromisoformat(s[:10])` before passing to asyncpg.
- asyncpg also accepts `datetime.datetime` for `TIMESTAMPTZ` columns — these work correctly.

**Why:** asyncpg performs native type encoding at the protocol level. It calls `.toordinal()` on date objects, which str doesn't have. Pydantic with `date` type auto-parses ISO strings from JSON bodies.
