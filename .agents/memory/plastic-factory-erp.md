---
name: Plastic Factory ERP setup
description: Key quirks and decisions for the plastic-factory Flutter/FastAPI ERP on Replit
---

## Database SSL
Replit's internal PostgreSQL host is `helium:5432` and rejects SSL upgrades. The `database.py` conditionally disables SSL when the URL contains `helium`, `localhost`, or `127.0.0.1`.

**Why:** asyncpg defaults to `ssl="require"` which crashes on startup against Replit's internal DB.

**How to apply:** Any future DB URL change — check if the host is internal before enabling SSL.

## API Base URL (Flutter → backend)
Flutter's `ApiDataSource` fetches `/api/config` (relative, same-origin) at runtime to resolve the base URL. Default returned by backend: `https://plastic-factory-api.onrender.com`. Override by setting `API_BASE_URL` env var.

**Why:** `String.fromEnvironment` is compile-time only; runtime config endpoint allows changing the URL without rebuilding Flutter.

## Rebuilding Flutter
After any Dart source change in `lib/`, run `flutter build web --release` then restart the workflow. The pre-built output in `build/web/` is what FastAPI serves.

## Dropdowns are local
Workers, machines, mixers, products, and mixture types are stored in SharedPreferences (`LocalDataService`) — no network calls. This is intentional for offline support.

## Admin auth
App uses its own JWT-based auth against an `admin_users` table. `JWT_SECRET` is in Replit Secrets. The auth is NOT Replit Auth — it's a custom login screen.

## RENDER_DATABASE_URL as plain env var, not secret
A prior setup mistakenly stored the credential-bearing `RENDER_DATABASE_URL` as a plain `.replit` shared env var instead of a Secret. A plain env var with the same key always wins over a Secret of that name.

**Why:** Saving a new value via `requestSecrets` silently had no effect until the stale plain env var was deleted with `deleteEnvVars` — the shell kept showing the old DB host even after the secret was confirmed saved.

**How to apply:** If a newly-saved secret doesn't seem to take effect, check `viewEnvVars({ type: "env" })` for a same-named plain env var shadowing it, and delete the plain one. Any credential/connection-string env var should live only in Secrets, never in `.replit`.
