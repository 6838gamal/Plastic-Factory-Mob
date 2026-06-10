"""
Central configuration — all env vars live here.
Every module should import from this file, never call os.getenv() directly.
"""
import os

# ─── Environment ──────────────────────────────────────────────────────────────
ENVIRONMENT: str = os.getenv("ENVIRONMENT", "production")
APP_VERSION: str = "1.0.0"

# ─── API / Frontend ───────────────────────────────────────────────────────────
API_BASE_URL: str = os.getenv(
    "API_BASE_URL", "https://plastic-factory-api.onrender.com"
)
FRONTEND_URL: str = os.getenv(
    "FRONTEND_URL", "https://plastic-factory-mob-1.netlify.app"
)

# ─── Database ─────────────────────────────────────────────────────────────────
_DEFAULT_DB_URL = (
    "postgresql://gamalalmaqtary:tqL6D95VvkoCR9f1gE1fZykYakFU9sXb"
    "@dpg-d8j5350jo6nc73duopqg-a.virginia-postgres.render.com/plastic_factory_db"
)
DATABASE_URL: str = (
    os.getenv("RENDER_DATABASE_URL")
    or os.getenv("DATABASE_URL")
    or os.getenv("PG_DATABASE_URL")
    or _DEFAULT_DB_URL
)

# ─── Security ─────────────────────────────────────────────────────────────────
SECRET_KEY: str = (
    os.getenv("SECRET_KEY")
    or os.getenv("JWT_SECRET")
    or "plastic_factory_jwt_secret_2024_replit_secure"
)

# ─── Admin defaults (used only when no admin user exists) ─────────────────────
ADMIN_EMAIL: str = os.getenv("ADMIN_EMAIL", "admin@factory.com")
ADMIN_PASSWORD: str = os.getenv("ADMIN_PASSWORD", "admin123")

# ─── CORS ─────────────────────────────────────────────────────────────────────
_base_origins = [
    "https://plastic-factory-mob-1.netlify.app",
    "https://plastic-factory-api.onrender.com",
    "http://localhost:3000",
    "http://localhost:5000",
    "http://localhost:8080",
]
if FRONTEND_URL not in _base_origins:
    _base_origins.append(FRONTEND_URL)
_extra = os.getenv("CORS_ORIGINS", "")
if _extra:
    for _o in _extra.split(","):
        _o = _o.strip()
        if _o and _o not in _base_origins:
            _base_origins.append(_o)
CORS_ORIGINS: list[str] = _base_origins
