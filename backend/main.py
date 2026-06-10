import os
import sys
import asyncio
import bcrypt
from contextlib import asynccontextmanager
from datetime import datetime, timedelta
from pathlib import Path

sys.path.insert(0, os.path.dirname(__file__))

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse

from database import get_pool, close_pool

SCHEMA_PATH = Path(__file__).parent.parent / "schema.sql"


async def _init_db():
    """Initialize DB schema on first deployment only.

    Uses CREATE TABLE IF NOT EXISTS + CREATE INDEX IF NOT EXISTS in schema.sql,
    so re-running on every restart is safe and fast (no-op if tables exist).
    Checks for the presence of the primary table first to skip the SQL parse
    step entirely on normal restarts.
    """
    pool = await get_pool()
    already_exists = await pool.fetchval(
        "SELECT EXISTS("
        "  SELECT 1 FROM information_schema.tables"
        "  WHERE table_schema='public' AND table_name='raw_materials'"
        ")"
    )
    if already_exists:
        print("✅ [init_db] Schema already present — skipping.")
        # Ensure partial unique index on alerts.transaction_id (idempotent migration)
        await pool.execute(
            """CREATE UNIQUE INDEX IF NOT EXISTS alerts_transaction_id_key
               ON alerts (transaction_id)
               WHERE transaction_id IS NOT NULL"""
        )
        return

    if not SCHEMA_PATH.exists():
        print(f"⚠️  [init_db] schema.sql not found at {SCHEMA_PATH} — skipping.")
        return

    sql = SCHEMA_PATH.read_text(encoding="utf-8")
    try:
        await pool.execute(sql)
        print("✅ [init_db] Schema created from schema.sql")
    except Exception as exc:
        print(f"❌ [init_db] Schema init error: {exc}")


from routers import (
    auth, materials, inventory, workers, products,
    machines, mixers, mixture_types, batches,
    machine_production, alerts, audit, dashboard, config,
    shifts, opening_balances, reports, settings, day,
)
from routers import stock_take
from routers import recipes

WEB_DIR = Path(__file__).parent.parent / "build" / "web"


async def _archive_previous_day(pool, yesterday: str):
    """Automation 17: Archive yesterday's data as a snapshot."""
    try:
        existing = await pool.fetchrow(
            "SELECT id FROM daily_archive WHERE archive_date=$1::date", yesterday
        )
        if existing:
            return

        # Snapshot daily report
        report = await pool.fetchrow(
            "SELECT * FROM daily_reports WHERE report_date=$1::date", yesterday
        )
        # Snapshot inventory state
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
        print(f"✅ [scheduler] Archive created for {yesterday}")
    except Exception as exc:
        print(f"❌ [scheduler] Archive error: {exc}")


async def _run_daily_report():
    """Automation 15 & 16: Generate daily report snapshot and lock it."""
    try:
        pool = await get_pool()
        today = str(datetime.now().date())
        yesterday = str((datetime.now() - timedelta(days=1)).date())

        existing = await pool.fetchrow(
            "SELECT is_locked FROM daily_reports WHERE report_date=$1::date", today
        )
        if existing and existing["is_locked"]:
            print(f"[scheduler] Daily report {today} already locked — skipping.")
        else:
            from routers.reports import generate_daily_report
            await generate_daily_report(report_date=today, lock=True)
            print(f"✅ [scheduler] Daily report generated and locked for {today}")

        # Automation 17: archive yesterday after locking today
        await _archive_previous_day(pool, yesterday)

    except Exception as exc:
        print(f"❌ [scheduler] Daily report error: {exc}")


async def _daily_report_scheduler():
    """Loop: sleep until 23:59, generate report + archive, repeat."""
    while True:
        now = datetime.now()
        target = now.replace(hour=23, minute=59, second=0, microsecond=0)
        if now >= target:
            target += timedelta(days=1)
        sleep_secs = (target - now).total_seconds()
        print(f"[scheduler] Next daily report in {sleep_secs/3600:.1f} h")
        await asyncio.sleep(sleep_secs)
        await _run_daily_report()
        await asyncio.sleep(61)   # avoid double-fire within the same minute


async def _seed_default_admin():
    """Ensure a default admin user always exists on startup."""
    pool = await get_pool()
    existing = await pool.fetchval("SELECT COUNT(*) FROM admin_users")
    if existing == 0:
        default_email = os.getenv("ADMIN_EMAIL", "admin@factory.com")
        default_password = os.getenv("ADMIN_PASSWORD", "admin123")
        hashed = bcrypt.hashpw(default_password.encode(), bcrypt.gensalt()).decode()
        await pool.execute(
            "INSERT INTO admin_users (id, email, password_hash) VALUES (gen_random_uuid(), $1, $2) ON CONFLICT (email) DO NOTHING",
            default_email, hashed,
        )
        print(f"✅ Default admin created: {default_email}")
    else:
        print(f"✅ Admin users found: {existing}")


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
            """INSERT INTO settings (key, value, description)
               VALUES ($1, $2, $3)
               ON CONFLICT (key) DO NOTHING""",
            key, value, description,
        )


async def _run_safe_migrations():
    """Apply only SAFE idempotent migrations (no CREATE TABLE, no DROP).
    The schema is assumed to already exist — this function only adds
    missing indexes or constraints that were introduced after initial setup.
    """
    pool = await get_pool()
    # Partial unique index on alerts.transaction_id (safe / idempotent)
    await pool.execute(
        """CREATE UNIQUE INDEX IF NOT EXISTS alerts_transaction_id_key
           ON alerts (transaction_id)
           WHERE transaction_id IS NOT NULL"""
    )


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Connect to existing database — retries automatically until successful
    pool = await get_pool()
    print("✅ Database pool ready")

    # Safe migrations only — never re-creates or drops existing data
    try:
        await _run_safe_migrations()
        print("✅ Safe migrations applied")
    except Exception as exc:
        print(f"⚠️  Safe migrations skipped: {exc}")

    await _seed_default_admin()
    await _seed_default_settings()
    scheduler_task = asyncio.create_task(_daily_report_scheduler())
    yield
    scheduler_task.cancel()
    await close_pool()
    print("Database pool closed")


app = FastAPI(title="Plastic Factory ERP API", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "https://plastic-factory-mob-1.netlify.app",
    ],
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

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


@app.get("/api/health")
async def health():
    try:
        pool = await get_pool()
        await pool.fetchval("SELECT 1")
        return {"status": "ok", "db": "connected"}
    except Exception as e:
        return {"status": "error", "db": str(e)}


_NO_CACHE = {"Cache-Control": "no-cache, no-store, must-revalidate", "Pragma": "no-cache"}

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

    app.mount("/", StaticFiles(directory=str(WEB_DIR), html=True), name="flutter")
