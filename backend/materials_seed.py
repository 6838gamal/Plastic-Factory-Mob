"""
Durable backup for the raw-materials catalog.

Raw materials only ever lived inside the live PostgreSQL database. If that
database is ever wiped, recreated, or swapped for a new instance (a real risk
here since it is an external Render database, not something this project
controls), every material — both the ones seeded initially and any added
later by a warehouse keeper or admin through the app — would simply
disappear, because schema.sql only defines empty table structure.

This module keeps a JSON snapshot of the raw_materials table on disk,
committed alongside the code:
  - export_raw_materials_seed() is called after every create/update/delete
    so the file always mirrors the live catalog.
  - restore_raw_materials_seed() is called once during startup (after the
    schema is applied) and re-inserts any material from the seed file that
    is missing from the live table — filling gaps after a reset without
    ever touching or overwriting rows that already exist.
"""
import json
import logging
import os
import tempfile
from pathlib import Path

from database import get_pool

logger = logging.getLogger("plastic_factory")

SEED_PATH = Path(__file__).parent / "seed_data" / "raw_materials_seed.json"


async def export_raw_materials_seed() -> None:
    """Dump the full raw_materials table (active + inactive) to disk."""
    try:
        pool = await get_pool()
        rows = await pool.fetch(
            """SELECT id, name, code, category, unit, min_stock, cost_per_unit,
                      is_active, notes
               FROM raw_materials
               ORDER BY created_at"""
        )
        data = [dict(r) for r in rows]
        for d in data:
            d["id"] = str(d["id"])
        SEED_PATH.parent.mkdir(parents=True, exist_ok=True)

        # Write atomically: a crash mid-write must never leave a truncated/
        # corrupt seed file, since it's the only durable backup this feature
        # relies on. Write to a temp file in the same directory, fsync it,
        # then atomically replace the real path (os.replace is atomic on
        # POSIX as long as src/dst are on the same filesystem).
        fd, tmp_path = tempfile.mkstemp(
            dir=str(SEED_PATH.parent), prefix=".raw_materials_seed.", suffix=".tmp"
        )
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, indent=2, default=str)
                f.flush()
                os.fsync(f.fileno())
            os.replace(tmp_path, SEED_PATH)
        except Exception:
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
            raise
    except Exception:
        logger.exception("[materials_seed] Failed to export raw materials seed")


async def restore_raw_materials_seed() -> None:
    """Re-insert any materials from the seed file missing from the live DB.

    Existing rows are never touched or overwritten — this only fills gaps
    left by a database reset/recreation, so live edits always win.
    """
    if not SEED_PATH.exists():
        return
    try:
        data = json.loads(SEED_PATH.read_text(encoding="utf-8"))
    except Exception:
        logger.exception("[materials_seed] Failed to read raw materials seed file")
        return
    if not data:
        return

    pool = await get_pool()
    restored = 0
    for m in data:
        try:
            result = await pool.execute(
                """INSERT INTO raw_materials
                       (id, name, code, category, unit, min_stock, cost_per_unit, is_active, notes)
                   VALUES ($1::uuid, $2, $3, $4, $5, $6, $7, $8, $9)
                   ON CONFLICT (id) DO NOTHING""",
                m["id"], m["name"], m.get("code"), m.get("category") or "عام",
                m.get("unit") or "كجم", m.get("min_stock") or 0,
                m.get("cost_per_unit") or 0, m.get("is_active", True), m.get("notes"),
            )
            if result and result.split()[-1] == "1":
                restored += 1
        except Exception:
            logger.exception(f"[materials_seed] Failed to restore material {m.get('name')!r}")

    if restored:
        logger.info(f"[materials_seed] Restored {restored} raw material(s) from seed file")
