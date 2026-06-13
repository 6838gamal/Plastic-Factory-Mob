"""
Central configuration — all env vars live here.
Every module should import from this file, never call os.getenv() directly.
"""
import os

# ─── Environment ──────────────────────────────────────────────────────────────
ENVIRONMENT: str = os.getenv("ENVIRONMENT", "development")
APP_VERSION: str = "1.0.0"

# ─── API / Frontend ───────────────────────────────────────────────────────────
API_BASE_URL: str = os.getenv("API_BASE_URL", "")
FRONTEND_URL: str = os.getenv("FRONTEND_URL", "")

# ─── Database ─────────────────────────────────────────────────────────────────
# RENDER_DATABASE_URL is the permanent production database (Render PostgreSQL).
# Falls back to DATABASE_URL (Replit built-in) if not set.
DATABASE_URL: str = (
    os.getenv("RENDER_DATABASE_URL")
    or os.getenv("DATABASE_URL")
    or ""
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
    "http://localhost:3000",
    "http://localhost:5000",
    "http://localhost:8080",
]

# Add Replit dev domain if available
_replit_dev = os.getenv("REPLIT_DEV_DOMAIN", "")
if _replit_dev:
    _base_origins.append(f"https://{_replit_dev}")

_replit_domains = os.getenv("REPLIT_DOMAINS", "")
if _replit_domains:
    for _d in _replit_domains.split(","):
        _d = _d.strip()
        if _d:
            _base_origins.append(f"https://{_d}")

if FRONTEND_URL and FRONTEND_URL not in _base_origins:
    _base_origins.append(FRONTEND_URL)

_extra = os.getenv("CORS_ORIGINS", "")
if _extra:
    for _o in _extra.split(","):
        _o = _o.strip()
        if _o and _o not in _base_origins:
            _base_origins.append(_o)

CORS_ORIGINS: list[str] = _base_origins
