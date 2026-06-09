"""
Settings router — read/write factory configuration values.

Keys in the settings table:
  prevent_negative_stock    — 'true'/'false'
  deviation_alert_threshold — float %
  deviation_notes_threshold — float %
  scrap_material_id         — UUID string
"""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional
from database import get_pool

router = APIRouter(prefix="/api/settings", tags=["settings"])

_DEFAULTS = {
    "prevent_negative_stock": "true",
    "deviation_alert_threshold": "2.0",
    "deviation_notes_threshold": "5.0",
    "scrap_material_id": "",
}


class SettingUpdate(BaseModel):
    value: str
    description: Optional[str] = None


@router.get("")
async def list_settings():
    """Return all settings as a flat dict."""
    pool = await get_pool()
    rows = await pool.fetch("SELECT key, value, description FROM settings ORDER BY key")
    return [dict(r) for r in rows]


@router.get("/{key}")
async def get_setting(key: str):
    pool = await get_pool()
    row = await pool.fetchrow(
        "SELECT key, value, description FROM settings WHERE key=$1", key
    )
    if not row:
        if key in _DEFAULTS:
            return {"key": key, "value": _DEFAULTS[key], "description": None}
        raise HTTPException(status_code=404, detail=f"Setting '{key}' not found")
    return dict(row)


@router.put("/{key}")
async def update_setting(key: str, body: SettingUpdate):
    pool = await get_pool()
    row = await pool.fetchrow(
        """INSERT INTO settings (key, value, description)
           VALUES ($1, $2, $3)
           ON CONFLICT (key)
           DO UPDATE SET value=$2,
                         description=COALESCE($3, settings.description),
                         updated_at=NOW()
           RETURNING key, value, description""",
        key, body.value, body.description,
    )
    await pool.execute(
        """INSERT INTO audit_log (id, action, table_name, record_id, description)
           VALUES (gen_random_uuid(), 'update', 'settings', $1, $2)""",
        key,
        f"تحديث إعداد {key} إلى {body.value}",
    )
    return dict(row)


@router.post("/reset-defaults")
async def reset_defaults():
    """Restore all settings to their default values."""
    pool = await get_pool()
    for k, v in _DEFAULTS.items():
        await pool.execute(
            """INSERT INTO settings (key, value)
               VALUES ($1, $2)
               ON CONFLICT (key) DO NOTHING""",
            k, v,
        )
    return {"message": "تم استعادة الإعدادات الافتراضية", "defaults": _DEFAULTS}
