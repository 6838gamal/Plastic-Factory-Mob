import sys
import os
import time
import asyncio
import logging
import bcrypt
from contextlib import asynccontextmanager
from datetime import datetime, timedelta
from pathlib import Path

sys.path.insert(0, os.path.dirname(__file__))

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, JSONResponse
from fastapi.exceptions import RequestValidationError

import settings as cfg
from database import get_pool, close_pool

# ─── Logging ──────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s — %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("plastic_factory")

SCHEMA_PATH = Path(__file__).parent.parent / "schema.sql"
WEB_DIR     = Path(__file__).parent.parent / "build" / "web"


# ─── DB helpers ───────────────────────────────────────────────────────────────

async def _init_db():
    """Apply full schema on every startup — completely idempotent."""
    pool = await get_pool()

    if not SCHEMA_PATH.exists():
        logger.warning(f"[init_db] schema.sql not found at {SCHEMA_PATH} — skipping.")
        return

    sql = SCHEMA_PATH.read_text(encoding="utf-8")
    try:
        await pool.execute(sql)
        logger.info("[init_db] Schema applied (idempotent — existing data untouched)")
    except Exception as exc:
        logger.error(f"[init_db] Schema error: {exc}")
        raise

    await pool.execute(
        """CREATE UNIQUE INDEX IF NOT EXISTS alerts_transaction_id_key
           ON alerts (transaction_id)
           WHERE transaction_id IS NOT NULL"""
    )

    # ── Idempotent column migrations (ADD IF NOT EXISTS) ──────────────
    _col_migrations = [
        "ALTER TABLE raw_materials ADD COLUMN IF NOT EXISTS code VARCHAR(50)",
        "ALTER TABLE raw_materials ADD COLUMN IF NOT EXISTS cost_per_unit NUMERIC(12,4) NOT NULL DEFAULT 0",
        "ALTER TABLE inventory_transactions ADD COLUMN IF NOT EXISTS balance_before DECIMAL(12,3)",
        "ALTER TABLE inventory_transactions ADD COLUMN IF NOT EXISTS balance_after DECIMAL(12,3)",
    ]
    for stmt in _col_migrations:
        try:
            await pool.execute(stmt)
        except Exception as exc:
            logger.warning(f"[init_db] Column migration skipped: {exc}")
    logger.info("[init_db] Column migrations applied")


async def _seed_default_admin():
    """Ensure a default admin user always exists on startup."""
    pool = await get_pool()
    existing = await pool.fetchval("SELECT COUNT(*) FROM admin_users")
    if existing == 0:
        hashed = bcrypt.hashpw(cfg.ADMIN_PASSWORD.encode(), bcrypt.gensalt()).decode()
        await pool.execute(
            "INSERT INTO admin_users (id, email, password_hash) "
            "VALUES (gen_random_uuid(), $1, $2) ON CONFLICT (email) DO NOTHING",
            cfg.ADMIN_EMAIL, hashed,
        )
        logger.info(f"Default admin created: {cfg.ADMIN_EMAIL}")
    else:
        logger.info(f"Admin users found: {existing}")


async def _seed_default_settings():
    """Seed required settings rows if they don't exist yet."""
    pool = await get_pool()
    defaults = [
        ("prevent_negative_stock",    "true",  "منع الخصم عند نقص المخزون"),
        ("deviation_alert_threshold", "2.0",   "نسبة الانحراف لإنشاء تنبيه (%)"),
        ("deviation_notes_threshold", "5.0",   "نسبة الانحراف لإلزام الملاحظة (%)"),
        ("scrap_material_id",         "",      "معرف مادة الهالك"),
    ]
    for key, value, description in defaults:
        await pool.execute(
            "INSERT INTO settings (key, value, description) VALUES ($1, $2, $3) "
            "ON CONFLICT (key) DO NOTHING",
            key, value, description,
        )


# ─── Scheduler ────────────────────────────────────────────────────────────────

async def _archive_previous_day(pool, yesterday: str):
    """Automation 17: Archive yesterday's data as a snapshot."""
    try:
        existing = await pool.fetchrow(
            "SELECT id FROM daily_archive WHERE archive_date=$1::date", yesterday
        )
        if existing:
            return

        report = await pool.fetchrow(
            "SELECT * FROM daily_reports WHERE report_date=$1::date", yesterday
        )
        inv_rows = await pool.fetch(
            """SELECT i.material_id, rm.name, i.warehouse_type, i.balance, rm.unit
               FROM inventory i JOIN raw_materials rm ON rm.id=i.material_id
               ORDER BY rm.name"""
        )
        batch_count = await pool.fetchval(
            "SELECT COUNT(*) FROM batches WHERE date=$1::date", yesterday
        )

        import json as _json
        inv_snapshot = [dict(r) for r in inv_rows]

        await pool.execute(
            """INSERT INTO daily_archive
               (id, archive_date, report_data, inventory_snapshot, batch_count, archived_at)
               VALUES (gen_random_uuid(), $1::date, $2, $3, $4, NOW())
               ON CONFLICT (archive_date) DO NOTHING""",
            yesterday,
            _json.dumps(dict(report) if report else {}, default=str),
            _json.dumps(inv_snapshot, default=str),
            int(batch_count),
        )
        logger.info(f"[scheduler] Archive created for {yesterday}")
    except Exception as exc:
        logger.error(f"[scheduler] Archive error: {exc}")


async def _run_daily_report():
    """Automation 15 & 16: Generate daily report snapshot and lock it."""
    try:
        pool  = await get_pool()
        today     = str(datetime.now().date())
        yesterday = str((datetime.now() - timedelta(days=1)).date())

        existing = await pool.fetchrow(
            "SELECT is_locked FROM daily_reports WHERE report_date=$1::date", today
        )
        if existing and existing["is_locked"]:
            logger.info(f"[scheduler] Daily report {today} already locked — skipping.")
        else:
            from routers.reports import generate_daily_report
            await generate_daily_report(report_date=today, lock=True)
            logger.info(f"[scheduler] Daily report generated and locked for {today}")

        await _archive_previous_day(pool, yesterday)

    except Exception as exc:
        logger.error(f"[scheduler] Daily report error: {exc}")


async def _daily_report_scheduler():
    """Loop: sleep until 23:59, generate report + archive, repeat."""
    while True:
        now    = datetime.now()
        target = now.replace(hour=23, minute=59, second=0, microsecond=0)
        if now >= target:
            target += timedelta(days=1)
        sleep_secs = (target - now).total_seconds()
        logger.info(f"[scheduler] Next daily report in {sleep_secs/3600:.1f} h")
        await asyncio.sleep(sleep_secs)
        await _run_daily_report()
        await asyncio.sleep(61)


# ─── Startup validation ───────────────────────────────────────────────────────

async def _validate_startup():
    """Fail fast if critical configuration is missing."""
    if not cfg.DATABASE_URL:
        raise RuntimeError("DATABASE_URL is not configured — cannot start.")
    if cfg.SECRET_KEY.startswith("plastic_factory_jwt_secret_2024") and cfg.ENVIRONMENT == "production":
        logger.warning("⚠️  Using default SECRET_KEY in production — set JWT_SECRET env var!")
    logger.info(f"✅ Environment  : {cfg.ENVIRONMENT}")
    logger.info(f"✅ API base URL : {cfg.API_BASE_URL}")
    logger.info(f"✅ Frontend URL : {cfg.FRONTEND_URL}")
    logger.info(f"✅ App version  : {cfg.APP_VERSION}")


# ─── Lifespan ─────────────────────────────────────────────────────────────────

from routers import (
    auth, materials, inventory, workers, products,
    machines, mixers, mixture_types, batches,
    machine_production, alerts, audit, dashboard, config,
    shifts, opening_balances, reports, settings, day,
)
from routers import stock_take, recipes


@asynccontextmanager
async def lifespan(app: FastAPI):
    await _validate_startup()
    pool = await get_pool()
    logger.info("✅ Database pool ready")
    await _init_db()
    await _seed_default_admin()
    await _seed_default_settings()
    scheduler_task = asyncio.create_task(_daily_report_scheduler())
    yield
    scheduler_task.cancel()
    await close_pool()
    logger.info("Database pool closed")


# ─── App ──────────────────────────────────────────────────────────────────────

app = FastAPI(
    title="Plastic Factory ERP API",
    version=cfg.APP_VERSION,
    description="نظام إدارة مصنع البلاستيك — FastAPI + PostgreSQL",
    lifespan=lifespan,
)

# CORS — allow * for maximum compatibility (API is auth-protected via JWT)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ─── Middleware: request logging ───────────────────────────────────────────────

_SKIP_LOG_PREFIXES = ("/assets/", "/flutter", "/main.dart", "/index.html", "/favicon")

@app.middleware("http")
async def log_requests(request: Request, call_next):
    path = request.url.path
    start = time.time()
    response = await call_next(request)
    duration_ms = (time.time() - start) * 1000
    if not any(path.startswith(p) for p in _SKIP_LOG_PREFIXES):
        logger.info(
            f"{request.method} {path} → {response.status_code} ({duration_ms:.0f}ms)"
        )
    return response


# ─── Global error handlers ────────────────────────────────────────────────────

@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error(f"Unhandled error on {request.method} {request.url.path}: {exc}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={"error": "حدث خطأ داخلي في الخادم. يرجى المحاولة مجدداً."},
    )


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    logger.warning(f"Validation error on {request.method} {request.url.path}: {exc.errors()}")
    return JSONResponse(
        status_code=422,
        content={"error": "بيانات الطلب غير صحيحة.", "details": exc.errors()},
    )


# ─── Routers ──────────────────────────────────────────────────────────────────

app.include_router(auth.router)
app.include_router(materials.router)
app.include_router(inventory.router)
app.include_router(workers.router)
app.include_router(products.router)
app.include_router(machines.router)
app.include_router(mixers.router)
app.include_router(mixture_types.router)
app.include_router(batches.router)
app.include_router(machine_production.router)
app.include_router(alerts.router)
app.include_router(audit.router)
app.include_router(dashboard.router)
app.include_router(config.router)
app.include_router(shifts.router)
app.include_router(opening_balances.router)
app.include_router(reports.router)
app.include_router(stock_take.router)
app.include_router(settings.router)
app.include_router(day.router)
app.include_router(recipes.router)


# ─── Health & System Info ─────────────────────────────────────────────────────

@app.get("/api/health", tags=["monitoring"])
async def health():
    try:
        pool = await get_pool()
        await pool.fetchval("SELECT 1")
        db_status = "connected"
        ok = True
    except Exception as e:
        db_status = str(e)
        ok = False
    return {
        "status": "ok" if ok else "error",
        "db": db_status,
        "version": cfg.APP_VERSION,
        "environment": cfg.ENVIRONMENT,
    }


@app.get("/api/system-info", tags=["monitoring"])
async def system_info():
    """System status for monitoring dashboards and ops tooling."""
    try:
        pool = await get_pool()
        await pool.fetchval("SELECT 1")
        db_connected = True
        db_message   = "connected"
    except Exception as e:
        db_connected = False
        db_message   = str(e)

    return {
        "version":     cfg.APP_VERSION,
        "environment": cfg.ENVIRONMENT,
        "api_base_url": cfg.API_BASE_URL,
        "frontend_url": cfg.FRONTEND_URL,
        "services": {
            "database": db_message,
            "api":      "running",
        },
        "database_connected": db_connected,
        "timestamp": datetime.utcnow().isoformat() + "Z",
    }


# ─── Static Flutter Web ───────────────────────────────────────────────────────

_NO_CACHE = {
    "Cache-Control": "no-cache, no-store, must-revalidate",
    "Pragma": "no-cache",
}

if WEB_DIR.exists():
    @app.get("/flutter_service_worker.js")
    async def service_worker():
        return FileResponse(str(WEB_DIR / "flutter_service_worker.js"), headers=_NO_CACHE)

    @app.get("/index.html")
    async def index_html():
        return FileResponse(str(WEB_DIR / "index.html"), headers=_NO_CACHE)

    @app.get("/flutter_bootstrap.js")
    async def flutter_bootstrap():
        return FileResponse(str(WEB_DIR / "flutter_bootstrap.js"), headers=_NO_CACHE)

    # SPA catch-all: serve index.html for any path not matched by API or static files
    @app.get("/{full_path:path}")
    async def spa_fallback(full_path: str):
        # Only serve index.html for non-API, non-asset paths
        if full_path.startswith("api/") or full_path.startswith("assets/"):
            from fastapi import HTTPException as _HTTPException
            raise _HTTPException(status_code=404)
        static_file = WEB_DIR / full_path
        if static_file.exists() and static_file.is_file():
            return FileResponse(str(static_file))
        return FileResponse(str(WEB_DIR / "index.html"), headers=_NO_CACHE)

    app.mount("/", StaticFiles(directory=str(WEB_DIR), html=True), name="flutter")
