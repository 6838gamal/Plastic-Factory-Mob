---
name: Production readiness config
description: Centralized settings pattern, Flutter rebuild rule, and deployment files for Render.
---

## Central settings pattern

All env vars live in `backend/settings.py` — routers import from there, never call `os.getenv()` directly.
Flutter config lives in `lib/core/config/app_config.dart` (const String.fromEnvironment).

**Why:** Prevents scattered os.getenv() calls and makes production config auditable from one file.

## Flutter rebuild rule (updated 2026-07-10)

User explicitly requested the opposite of the old rule: workflow now runs `bash start.sh`, which
does `flutter clean` + removes `build/web`/`.dart_tool` + full `flutter build web --release
--dart-define=API_BASE_URL=...` on every single start, before launching uvicorn.

**Why:** User was repeatedly hit by stale `build/web` (edited Dart source never reflected in the
running app) and explicitly asked to force cache clearing + rebuild on every server start attempt,
accepting the ~40s extra startup cost. This supersedes the earlier "don't rebuild on every
start" convention — do not revert to manual-rebuild-only unless the user asks again.

**How to apply:** Keep `start.sh` as the workflow entrypoint (`bash start.sh`), not a bare
uvicorn command. If editing the workflow, preserve the clean+build+run sequence.

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
