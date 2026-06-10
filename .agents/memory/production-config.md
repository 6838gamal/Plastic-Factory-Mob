---
name: Production readiness config
description: Centralized settings pattern, Flutter rebuild rule, and deployment files for Render.
---

## Central settings pattern

All env vars live in `backend/settings.py` — routers import from there, never call `os.getenv()` directly.
Flutter config lives in `lib/core/config/app_config.dart` (const String.fromEnvironment).

**Why:** Prevents scattered os.getenv() calls and makes production config auditable from one file.

## Flutter rebuild rule

Workflow command is `cd backend && uvicorn main:app --host 0.0.0.0 --port 5000` — NO Flutter rebuild.
Flutter must be rebuilt manually after Dart changes:
```bash
flutter build web --release --dart-define=API_BASE_URL=https://plastic-factory-api.onrender.com
```

**Why:** flutter clean + dart2js compiler crashes (Dart 3.8.0 / Flutter 3.32.0 known issue on Replit).
Running clean before rebuild is required to fix stale cache crashes.

## dart2js crash fix

If `flutter build web --release` crashes with "Bad state: Non-constant annotation":
1. Run `flutter clean` first
2. Run `flutter pub get`  
3. Rebuild — crash is gone after cache clear

## Deployment files

- `Dockerfile` — Python 3.12-slim, copies pre-built `build/web`, runs uvicorn from `/app/backend`
- `docker-compose.yml` — all env vars via ${VAR} substitution
- `render.yaml` — start command uses `$PORT` (Render injects it); build command is `pip install -r backend/requirements.txt`

## Production database

User's Render PostgreSQL — set as DATABASE_URL env var. Never drop/truncate/reset.
schema.sql is applied idempotently on every startup (CREATE TABLE IF NOT EXISTS).

## Splash page health check

`splash_page.dart` must use `AppConfig.apiBaseUrl + '/api/health'` — never a bare relative `/api/health`
which only works when Flutter and API share the same origin.
