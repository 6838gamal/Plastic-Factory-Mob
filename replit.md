# Plastic Factory ERP — نظام إدارة مصنع البلاستيك

A Flutter web + FastAPI ERP system for managing plastic factory operations: batches, inventory, machines, workers, and production.

## Architecture

- **Frontend**: Flutter web (pre-built in `build/web/`), served by FastAPI
- **Backend**: Python FastAPI on port 5000 (`backend/`)
- **Database**: Replit PostgreSQL (schema in `schema.sql`)

## Running

The `Start application` workflow runs `uvicorn main:app --host 0.0.0.0 --port 5000` from the `backend/` directory.

## Environment Variables / Secrets

| Name | Description | Default |
|------|-------------|---------|
| `DATABASE_URL` | Replit PostgreSQL connection string | Auto-provisioned |
| `JWT_SECRET` | Secret key for signing login tokens | — (required) |
| `API_BASE_URL` | External API base URL used by Flutter frontend | `https://plastic-factory-api.onrender.com` |

## Rebuilding the Flutter Frontend

After editing any Dart source in `lib/`:

```bash
flutter build web --release
```

Then restart the workflow.

## User preferences

- Dropdown values (workers, machines, mixers, products, mixture types) should always remain locally stored (SharedPreferences) — no network calls.
- API base URL must remain configurable via `API_BASE_URL` env var without code changes.
