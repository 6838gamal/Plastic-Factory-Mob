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
from routers import (
    auth, materials, inventory, workers, products,
    machines, mixers, mixture_types, batches,
    machine_production, alerts, audit, dashboard, config,
    shifts, opening_balances, reports,
)
from routers import stock_take

WEB_DIR = Path(__file__).parent.parent / "build" / "web"


async def _run_daily_report():
    """Generate and lock the daily report for today."""
    try:
        pool = await get_pool()
        today = str(datetime.now().date())

        existing = await pool.fetchrow(
            "SELECT is_locked FROM daily_reports WHERE report_date=$1::date", today
        )
        if existing and existing["is_locked"]:
            print(f"[scheduler] Daily report {today} already locked — skipping.")
            return

        # Import inline to avoid circular imports
        from routers.reports import generate_daily_report
        await generate_daily_report(report_date=today, lock=True)
        print(f"✅ [scheduler] Daily report generated and locked for {today}")
    except Exception as exc:
        print(f"❌ [scheduler] Daily report error: {exc}")


async def _daily_report_scheduler():
    """Loop: sleep until 23:59, generate report, sleep 61 s, repeat."""
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


@asynccontextmanager
async def lifespan(app: FastAPI):
    await get_pool()
    print("✅ Database pool ready")
    await _seed_default_admin()
    scheduler_task = asyncio.create_task(_daily_report_scheduler())
    yield
    scheduler_task.cancel()
    await close_pool()
    print("Database pool closed")


app = FastAPI(title="Plastic Factory ERP API", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
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
