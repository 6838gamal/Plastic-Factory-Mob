# Plastic Factory ERP — نظام إدارة مصنع البلاستيك

A Flutter web + FastAPI ERP system for managing plastic factory operations: batches, inventory, machines, workers, and production.

## Architecture

- **Frontend**: Flutter web (pre-built in `build/web/`), served by FastAPI
- **Backend**: Python FastAPI on port 5000 (`backend/`)
- **Database**: PostgreSQL (Render) — connection via `DATABASE_URL`
- **Central config**: `backend/settings.py` (backend) · `lib/core/config/app_config.dart` (Flutter)

## Running

The `Start application` workflow runs `bash start.sh`, which on every start:
1. Runs `flutter clean` and removes `build/web` + `.dart_tool` to purge stale caches.
2. Rebuilds the Flutter web app from source (`flutter build web --release --dart-define=API_BASE_URL=...`).
3. Starts `uvicorn main:app --host 0.0.0.0 --port 5000` from `backend/`.

This guarantees any Dart change is always reflected on restart, at the cost of ~40s extra startup time per restart (by explicit user request — previously the workflow only ran uvicorn and required a manual `flutter build web` after Dart edits).

## Environment Variables / Secrets

| Name | Description | Default |
|------|-------------|---------|
| `RENDER_DATABASE_URL` | PostgreSQL connection string (Replit Secret — **required**) | — |
| `DATABASE_URL` | Fallback PostgreSQL connection string | — |
| `JWT_SECRET` | Secret key for signing login tokens | — (required in production) |
| `SECRET_KEY` | Alias for JWT_SECRET | — |
| `API_BASE_URL` | External API base URL baked into Flutter build | `https://plastic-factory-api-backend.onrender.com` |
| `FRONTEND_URL` | Netlify frontend URL for CORS | `https://plastic-factory-mob-1.netlify.app` |
| `ENVIRONMENT` | `production` or `development` | `development` |
| `ADMIN_EMAIL` | Default admin email (first-run seeding) | `admin@factory.com` |
| `ADMIN_PASSWORD` | Default admin password (first-run seeding) | `admin123` |

### Replit Setup (first-time)

1. Add `RENDER_DATABASE_URL` as a Replit Secret (the Render PostgreSQL connection string).
2. Python dependencies are declared in `pyproject.toml` and installed automatically by Replit's package manager.
3. Start the `Start application` workflow — it builds Flutter (~40s) then starts uvicorn on port 5000.

## Deployment Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Production Docker image (Python 3.12 + pre-built Flutter) |
| `docker-compose.yml` | Docker Compose for local / self-hosted deployment |
| `render.yaml` | Render.com deployment config |
| `netlify.toml` | Netlify redirects (API proxy + SPA fallback) |

## API Endpoints — Monitoring

- `GET /api/health` — DB connectivity + version
- `GET /api/system-info` — Full environment status (version, URLs, services)

## User preferences

- Dropdown values (workers, machines, mixers, products, mixture types) should always remain locally stored (SharedPreferences) — no network calls.
- API base URL must remain configurable via `API_BASE_URL` env var without code changes.
- The production database (Render PostgreSQL) must never be dropped, truncated, or reset.
- Workflow command must NOT rebuild Flutter on every start — rebuild manually when Dart files change.
- Do NOT replace external links/URLs with local ones. Do NOT change any details unless explicitly requested — leave everything as-is.
