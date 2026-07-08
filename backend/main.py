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
from materials_seed import restore_raw_materials_seed, export_raw_materials_seed

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

    # ── Ensure UNIQUE constraint on opening_balances ────────────────────
    await pool.execute("""
        CREATE UNIQUE INDEX IF NOT EXISTS opening_balances_mat_wh_date_key
        ON opening_balances (material_id, warehouse_type, balance_date)
    """)

    # ── Idempotent column migrations (ADD IF NOT EXISTS) ──────────────
    # ── Shift handover tables ──────────────────────────────────
    for _tbl_stmt in [
        """CREATE TABLE IF NOT EXISTS shift_handovers (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          shift_name VARCHAR(100) NOT NULL,
          supervisor_name VARCHAR(200) NOT NULL,
          handover_date DATE NOT NULL DEFAULT CURRENT_DATE,
          opening_stock_kg DECIMAL(12,3) NOT NULL DEFAULT 0,
          received_from_main_kg DECIMAL(12,3) NOT NULL DEFAULT 0,
          total_batch_inputs_kg DECIMAL(12,3) NOT NULL DEFAULT 0,
          expected_stock_kg DECIMAL(12,3) NOT NULL DEFAULT 0,
          actual_stock_kg DECIMAL(12,3),
          flashing_kg DECIMAL(12,3) NOT NULL DEFAULT 0,
          rejected_kg DECIMAL(12,3) NOT NULL DEFAULT 0,
          waste_kg DECIMAL(12,3) NOT NULL DEFAULT 0,
          scrap_added_kg DECIMAL(12,3) NOT NULL DEFAULT 0,
          deficit_kg DECIMAL(12,3) NOT NULL DEFAULT 0,
          status VARCHAR(20) NOT NULL DEFAULT 'open',
          notes TEXT,
          next_supervisor_name VARCHAR(200),
          confirmed_at TIMESTAMPTZ,
          frozen_at TIMESTAMPTZ,
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )""",
        """CREATE TABLE IF NOT EXISTS custody_debts (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          handover_id UUID NOT NULL REFERENCES shift_handovers(id),
          supervisor_name VARCHAR(200) NOT NULL,
          shift_name VARCHAR(100),
          deficit_kg DECIMAL(12,3) NOT NULL,
          handover_date DATE NOT NULL,
          status VARCHAR(20) NOT NULL DEFAULT 'pending',
          notes TEXT,
          resolved_at TIMESTAMPTZ,
          resolved_by VARCHAR(200),
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )""",
        "CREATE INDEX IF NOT EXISTS idx_shift_handovers_date ON shift_handovers(handover_date)",
        "CREATE INDEX IF NOT EXISTS idx_shift_handovers_status ON shift_handovers(status)",
        "CREATE INDEX IF NOT EXISTS idx_custody_debts_status ON custody_debts(status)",
        "CREATE INDEX IF NOT EXISTS idx_custody_debts_supervisor ON custody_debts(supervisor_name)",
    ]:
        try:
            await pool.execute(_tbl_stmt)
        except Exception as exc:
            logger.warning(f"[init_db] Shift handover migration skipped: {exc}")

    # ── Vouchers tables (سندات الاستلام والتحويل والمرتجع) ─────────────────
    for _v_stmt in [
        """CREATE TABLE IF NOT EXISTS receipt_vouchers (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          voucher_number VARCHAR(50) NOT NULL,
          supplier_name VARCHAR(200),
          date DATE NOT NULL DEFAULT CURRENT_DATE,
          status VARCHAR(20) NOT NULL DEFAULT 'draft',
          notes TEXT,
          created_by VARCHAR(200) DEFAULT 'admin',
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )""",
        """CREATE TABLE IF NOT EXISTS receipt_voucher_items (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          voucher_id UUID NOT NULL REFERENCES receipt_vouchers(id) ON DELETE CASCADE,
          material_id TEXT,
          material_name VARCHAR(300) NOT NULL,
          unit VARCHAR(20) NOT NULL DEFAULT 'كجم',
          quantity DECIMAL(12,3) NOT NULL DEFAULT 0,
          notes TEXT,
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )""",
        """CREATE TABLE IF NOT EXISTS transfer_vouchers (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          voucher_number VARCHAR(50) NOT NULL,
          status VARCHAR(20) NOT NULL DEFAULT 'draft',
          warehouse_from VARCHAR(20) NOT NULL DEFAULT 'main',
          warehouse_to VARCHAR(20) NOT NULL DEFAULT 'mixer',
          notes TEXT,
          created_by VARCHAR(200) DEFAULT 'admin',
          confirmed_by VARCHAR(200),
          confirmed_at TIMESTAMPTZ,
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )""",
        """CREATE TABLE IF NOT EXISTS transfer_voucher_items (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          voucher_id UUID NOT NULL REFERENCES transfer_vouchers(id) ON DELETE CASCADE,
          material_id TEXT,
          material_name VARCHAR(300) NOT NULL,
          unit VARCHAR(20) NOT NULL DEFAULT 'كجم',
          requested_qty DECIMAL(12,3) NOT NULL DEFAULT 0,
          confirmed_qty DECIMAL(12,3),
          notes TEXT,
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )""",
        """CREATE TABLE IF NOT EXISTS return_vouchers (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          voucher_number VARCHAR(50) NOT NULL,
          original_voucher_id UUID REFERENCES transfer_vouchers(id),
          reason TEXT,
          status VARCHAR(20) NOT NULL DEFAULT 'draft',
          created_by VARCHAR(200) DEFAULT 'admin',
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )""",
        """CREATE TABLE IF NOT EXISTS return_voucher_items (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          voucher_id UUID NOT NULL REFERENCES return_vouchers(id) ON DELETE CASCADE,
          material_id TEXT,
          material_name VARCHAR(300) NOT NULL,
          unit VARCHAR(20) NOT NULL DEFAULT 'كجم',
          quantity DECIMAL(12,3) NOT NULL DEFAULT 0,
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )""",
        "CREATE INDEX IF NOT EXISTS idx_receipt_vouchers_status ON receipt_vouchers(status)",
        "CREATE INDEX IF NOT EXISTS idx_transfer_vouchers_status ON transfer_vouchers(status)",
        "CREATE INDEX IF NOT EXISTS idx_transfer_vouchers_created ON transfer_vouchers(created_at DESC)",
        "CREATE INDEX IF NOT EXISTS idx_return_vouchers_original ON return_vouchers(original_voucher_id)",
        # ── Withdrawal Vouchers (سندات الصرف/السحب) ──────────────────────
        """CREATE TABLE IF NOT EXISTS withdrawal_vouchers (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          voucher_number VARCHAR(50) NOT NULL,
          purpose TEXT,
          status VARCHAR(20) NOT NULL DEFAULT 'draft',
          notes TEXT,
          created_by VARCHAR(200) DEFAULT 'admin',
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )""",
        """CREATE TABLE IF NOT EXISTS withdrawal_voucher_items (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          voucher_id UUID NOT NULL REFERENCES withdrawal_vouchers(id) ON DELETE CASCADE,
          material_id TEXT,
          material_name VARCHAR(300) NOT NULL,
          unit VARCHAR(20) NOT NULL DEFAULT 'كجم',
          quantity DECIMAL(12,3) NOT NULL DEFAULT 0,
          notes TEXT,
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )""",
        "CREATE INDEX IF NOT EXISTS idx_withdrawal_vouchers_status ON withdrawal_vouchers(status)",
    ]:
        try:
            await pool.execute(_v_stmt)
        except Exception as exc:
            logger.warning(f"[init_db] Voucher table migration skipped: {exc}")

    # ── Counter resets table ───────────────────────────────────────────────
    await pool.execute("""
        CREATE TABLE IF NOT EXISTS counter_resets (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          counter_name VARCHAR(50) NOT NULL,
          reset_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          reset_by VARCHAR(200) DEFAULT 'admin'
        )
    """)
    await pool.execute(
        "CREATE INDEX IF NOT EXISTS idx_counter_resets_name_at ON counter_resets(counter_name, reset_at)"
    )

    # ── Suppliers table ──────────────────────────────────────────────
    await pool.execute("""
        CREATE TABLE IF NOT EXISTS suppliers (
            id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            name        VARCHAR(200) NOT NULL,
            phone       VARCHAR(50),
            email       VARCHAR(200),
            address     TEXT,
            category    VARCHAR(100),
            notes       TEXT,
            is_active   BOOLEAN NOT NULL DEFAULT TRUE,
            created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
    """)

    # ── Production Standards table ─────────────────────────────────────
    await pool.execute("""
        CREATE TABLE IF NOT EXISTS production_standards (
            id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            product_name    VARCHAR(200) NOT NULL,
            product_code    VARCHAR(50),
            standard_gram_per_pair DECIMAL(10,3) NOT NULL,
            is_active       BOOLEAN NOT NULL DEFAULT TRUE,
            notes           TEXT,
            created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
    """)
    await pool.execute(
        "CREATE INDEX IF NOT EXISTS idx_production_standards_active "
        "ON production_standards (is_active, product_name)"
    )

    _col_migrations = [
        "ALTER TABLE admin_users ADD COLUMN IF NOT EXISTS role VARCHAR(50) NOT NULL DEFAULT 'admin'",
        "ALTER TABLE admin_users ADD COLUMN IF NOT EXISTS name VARCHAR(200)",
        "ALTER TABLE receipt_vouchers ADD COLUMN IF NOT EXISTS received_by VARCHAR(200)",
        "ALTER TABLE receipt_vouchers ADD COLUMN IF NOT EXISTS supplier_phone VARCHAR(100)",
        "ALTER TABLE receipt_vouchers ADD COLUMN IF NOT EXISTS supplier_ref VARCHAR(200)",
        "ALTER TABLE shift_handovers ADD COLUMN IF NOT EXISTS unknown_waste_kg DECIMAL(12,3) NOT NULL DEFAULT 0",
        "ALTER TABLE shift_handovers ADD COLUMN IF NOT EXISTS received_from_main_kg DECIMAL(12,3) NOT NULL DEFAULT 0",
        "ALTER TABLE raw_materials ADD COLUMN IF NOT EXISTS code VARCHAR(50)",
        "ALTER TABLE raw_materials ADD COLUMN IF NOT EXISTS cost_per_unit NUMERIC(12,4) NOT NULL DEFAULT 0",
        "ALTER TABLE inventory_transactions ADD COLUMN IF NOT EXISTS balance_before DECIMAL(12,3)",
        "ALTER TABLE inventory_transactions ADD COLUMN IF NOT EXISTS balance_after DECIMAL(12,3)",
        # alerts: worker and assignee tracking
        "ALTER TABLE alerts ADD COLUMN IF NOT EXISTS worker_id VARCHAR(50)",
        "ALTER TABLE alerts ADD COLUMN IF NOT EXISTS worker_name VARCHAR(200)",
        "ALTER TABLE alerts ADD COLUMN IF NOT EXISTS assigned_to VARCHAR(200)",
        # machine_production: optional batch FK for cross-referencing
        "ALTER TABLE machine_production ADD COLUMN IF NOT EXISTS batch_id VARCHAR(50)",
        # recipe_items: add name-based columns (recipes.py uses material_name + standard_qty)
        # The table was originally created with material_id + quantity via schema.sql
        "ALTER TABLE recipe_items ADD COLUMN IF NOT EXISTS material_name TEXT",
        "ALTER TABLE recipe_items ADD COLUMN IF NOT EXISTS standard_qty NUMERIC(12,4) DEFAULT 0",
        "ALTER TABLE recipe_items ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW()",
        # stock_take_items: counted_at timestamp for when item was physically counted
        "ALTER TABLE stock_take_items ADD COLUMN IF NOT EXISTS counted_at TIMESTAMPTZ",
        # stock_take_sessions: closed_at timestamp for when session was closed
        "ALTER TABLE stock_take_sessions ADD COLUMN IF NOT EXISTS closed_at TIMESTAMPTZ",
        # machine_production: yield standard fields
        "ALTER TABLE machine_production ADD COLUMN IF NOT EXISTS standard_id VARCHAR(100)",
        "ALTER TABLE machine_production ADD COLUMN IF NOT EXISTS pairs_produced INTEGER DEFAULT 0",
        "ALTER TABLE machine_production ADD COLUMN IF NOT EXISTS actual_gram_per_pair DECIMAL(10,3)",
        "ALTER TABLE machine_production ADD COLUMN IF NOT EXISTS standard_gram_per_pair DECIMAL(10,3)",
        "ALTER TABLE machine_production ADD COLUMN IF NOT EXISTS deviation_from_standard_pct DECIMAL(10,3)",
        "ALTER TABLE machine_production ADD COLUMN IF NOT EXISTS waste_indicator VARCHAR(20)",
        # receipt_vouchers: per-step tracking for audit trail
        "ALTER TABLE receipt_vouchers ADD COLUMN IF NOT EXISTS submitted_by VARCHAR(200)",
        "ALTER TABLE receipt_vouchers ADD COLUMN IF NOT EXISTS submitted_at TIMESTAMPTZ",
        "ALTER TABLE receipt_vouchers ADD COLUMN IF NOT EXISTS approved_by VARCHAR(200)",
        "ALTER TABLE receipt_vouchers ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ",
        "ALTER TABLE receipt_vouchers ADD COLUMN IF NOT EXISTS posted_by VARCHAR(200)",
        "ALTER TABLE receipt_vouchers ADD COLUMN IF NOT EXISTS posted_at TIMESTAMPTZ",
    ]
    for stmt in _col_migrations:
        try:
            await pool.execute(stmt)
        except Exception as exc:
            logger.warning(f"[init_db] Column migration skipped: {exc}")

    # ── Drop FK constraints that block UUID→VARCHAR conversion ─────────────
    _drop_fks = [
        "ALTER TABLE alerts DROP CONSTRAINT IF EXISTS alerts_material_id_fkey",
        "ALTER TABLE alerts DROP CONSTRAINT IF EXISTS alerts_batch_id_fkey",
        "ALTER TABLE alerts DROP CONSTRAINT IF EXISTS alerts_machine_id_fkey",
        "ALTER TABLE batch_items DROP CONSTRAINT IF EXISTS batch_items_batch_id_fkey",
        "ALTER TABLE batch_items DROP CONSTRAINT IF EXISTS batch_items_material_id_fkey",
        "ALTER TABLE deduction_log DROP CONSTRAINT IF EXISTS deduction_log_batch_id_fkey",
        "ALTER TABLE deduction_log DROP CONSTRAINT IF EXISTS deduction_log_material_id_fkey",
        "ALTER TABLE inventory DROP CONSTRAINT IF EXISTS inventory_material_id_fkey",
        "ALTER TABLE inventory_transactions DROP CONSTRAINT IF EXISTS inventory_transactions_material_id_fkey",
        "ALTER TABLE opening_balances DROP CONSTRAINT IF EXISTS opening_balances_material_id_fkey",
        "ALTER TABLE recipe_items DROP CONSTRAINT IF EXISTS recipe_items_material_id_fkey",
        "ALTER TABLE recipe_items DROP CONSTRAINT IF EXISTS recipe_items_recipe_id_fkey",
        "ALTER TABLE recipes DROP CONSTRAINT IF EXISTS recipes_mixture_type_id_fkey",
        "ALTER TABLE recipes DROP CONSTRAINT IF EXISTS recipes_product_id_fkey",
        "ALTER TABLE stock_take_items DROP CONSTRAINT IF EXISTS stock_take_items_material_id_fkey",
        "ALTER TABLE stock_take_items DROP CONSTRAINT IF EXISTS stock_take_items_session_id_fkey",
        # batches — FK constraints that block worker/mixer/product/mixture_type UUID→VARCHAR
        "ALTER TABLE batches DROP CONSTRAINT IF EXISTS batches_worker_id_fkey",
        "ALTER TABLE batches DROP CONSTRAINT IF EXISTS batches_mixer_id_fkey",
        "ALTER TABLE batches DROP CONSTRAINT IF EXISTS batches_product_id_fkey",
        "ALTER TABLE batches DROP CONSTRAINT IF EXISTS batches_mixture_type_id_fkey",
        # machine_production — FK constraints that block machine/product UUID→VARCHAR
        "ALTER TABLE machine_production DROP CONSTRAINT IF EXISTS machine_production_machine_id_fkey",
        "ALTER TABLE machine_production DROP CONSTRAINT IF EXISTS machine_production_product_id_fkey",
        "ALTER TABLE machine_production DROP CONSTRAINT IF EXISTS machine_production_worker_id_fkey",
    ]
    for stmt in _drop_fks:
        try:
            await pool.execute(stmt)
        except Exception as exc:
            logger.warning(f"[init_db] Drop FK skipped: {exc}")

    # ── UUID → VARCHAR conversions (Flutter stores plain strings, not UUIDs) ──
    # Must run after FK drops above.
    _uuid_to_varchar = [
        # batches
        "ALTER TABLE batches ALTER COLUMN worker_id TYPE VARCHAR(100) USING worker_id::text",
        "ALTER TABLE batches ALTER COLUMN mixer_id TYPE VARCHAR(100) USING mixer_id::text",
        "ALTER TABLE batches ALTER COLUMN product_id TYPE VARCHAR(100) USING product_id::text",
        "ALTER TABLE batches ALTER COLUMN mixture_type_id TYPE VARCHAR(100) USING mixture_type_id::text",
        # machine_production
        "ALTER TABLE machine_production ALTER COLUMN machine_id TYPE VARCHAR(100) USING machine_id::text",
        "ALTER TABLE machine_production ALTER COLUMN product_id TYPE VARCHAR(100) USING product_id::text",
        "ALTER TABLE machine_production ALTER COLUMN worker_id TYPE VARCHAR(100) USING worker_id::text",
        # alerts
        "ALTER TABLE alerts ALTER COLUMN material_id TYPE VARCHAR(100) USING material_id::text",
        "ALTER TABLE alerts ALTER COLUMN batch_id TYPE VARCHAR(100) USING batch_id::text",
        "ALTER TABLE alerts ALTER COLUMN machine_id TYPE VARCHAR(100) USING machine_id::text",
        # Note: inventory.material_id stays as UUID (references raw_materials.id)
        # inventory_transactions.material_id stays as UUID (references raw_materials.id)
    ]
    for stmt in _uuid_to_varchar:
        try:
            await pool.execute(stmt)
        except Exception as exc:
            logger.warning(f"[init_db] UUID→VARCHAR skipped: {exc}")

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
    # SMS settings
    sms_defaults = [
        ("sms_enabled",        "false", "تفعيل إشعارات SMS"),
        ("sms_api_key",        "",      "مفتاح API لخدمة SMS Gateway"),
        ("sms_phone_numbers",  "",      "أرقام الهواتف (مفصولة بفاصلة)"),
        ("sms_device_id",      "0",     "معرّف الجهاز في SMS Gateway"),
    ]
    for key, value, description in sms_defaults:
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
from routers import stock_take, recipes, shift_handover, sms
from routers import vouchers
from routers import suppliers
from routers import production_standards, waste_monitoring


async def _init_db_background(app: FastAPI):
    """Runs the DB connect/migrate/seed sequence without blocking the
    server from opening its port. get_pool() retries forever on failure,
    so if this ran directly inside `lifespan` (before `yield`), uvicorn
    would never bind its listening socket while the DB is unreachable —
    which is exactly what produced 'No open ports detected'. Doing it in
    a background task lets the HTTP port open immediately; requests that
    need the DB simply await get_pool() themselves and wait it out."""
    try:
        await get_pool()
        logger.info("✅ Database pool ready")
        await _init_db()
        await restore_raw_materials_seed()
        await export_raw_materials_seed()
        await _seed_default_admin()
        await _seed_default_settings()
        app.state.db_ready.set()
        app.state.scheduler_task = asyncio.create_task(_daily_report_scheduler())
    except asyncio.CancelledError:
        raise
    except Exception:
        logger.exception("[startup] Background DB initialization failed")


async def _cancel_and_await(task: "asyncio.Task | None"):
    if task is None:
        return
    task.cancel()
    try:
        await task
    except asyncio.CancelledError:
        pass
    except Exception:
        logger.exception("[shutdown] Background task raised while being cancelled")


@asynccontextmanager
async def lifespan(app: FastAPI):
    await _validate_startup()
    app.state.scheduler_task = None
    app.state.db_ready = asyncio.Event()
    db_init_task = asyncio.create_task(_init_db_background(app))
    yield
    await _cancel_and_await(db_init_task)
    await _cancel_and_await(app.state.scheduler_task)
    await close_pool()
    logger.info("Database pool closed")


# ─── App ──────────────────────────────────────────────────────────────────────

app = FastAPI(
    title="Plastic Factory ERP API",
    version=cfg.APP_VERSION,
    description="نظام إدارة مصنع البلاستيك — FastAPI + PostgreSQL",
    lifespan=lifespan,
)

# CORS — allow all origins (API is auth-protected via JWT)
_cors_origins = cfg.CORS_ORIGINS or ["*"]
app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins,
    allow_origin_regex=r"https?://.*",
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
app.include_router(shift_handover.router)
app.include_router(sms.router)
app.include_router(vouchers.router)
app.include_router(suppliers.router)
app.include_router(production_standards.router)
app.include_router(waste_monitoring.router)


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
        # Try serving the exact static file first
        static_file = WEB_DIR / full_path
        if static_file.exists() and static_file.is_file():
            return FileResponse(str(static_file))
        # For API paths, return 404
        if full_path.startswith("api/"):
            from fastapi import HTTPException as _HTTPException
            raise _HTTPException(status_code=404)
        # For everything else, serve the Flutter SPA entry point
        return FileResponse(str(WEB_DIR / "index.html"), headers=_NO_CACHE)
