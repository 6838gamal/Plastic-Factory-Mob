"""
SMS Notifications router — send SMS alerts via sms-gateway.app
Settings keys used (stored in settings table):
  sms_enabled        — 'true'/'false'
  sms_api_key        — API key for sms-gateway.app
  sms_phone_numbers  — comma-separated phone numbers
  sms_device_id      — device ID (default '0')
"""
import logging
import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional, List
from database import get_pool

logger = logging.getLogger("plastic_factory")
router = APIRouter(prefix="/api/sms", tags=["sms"])


class SmsSendRequest(BaseModel):
    message: str
    phone_numbers: Optional[List[str]] = None


async def _get_sms_settings(pool) -> dict:
    rows = await pool.fetch(
        "SELECT key, value FROM settings WHERE key LIKE 'sms_%'"
    )
    return {r["key"]: r["value"] for r in rows}


@router.get("/settings")
async def get_sms_settings():
    pool = await get_pool()
    s = await _get_sms_settings(pool)
    return {
        "sms_enabled": s.get("sms_enabled", "false"),
        "sms_api_key": s.get("sms_api_key", ""),
        "sms_phone_numbers": s.get("sms_phone_numbers", ""),
        "sms_device_id": s.get("sms_device_id", "0"),
    }


@router.put("/settings")
async def update_sms_settings(data: dict):
    pool = await get_pool()
    allowed = {"sms_enabled", "sms_api_key", "sms_phone_numbers", "sms_device_id"}
    for key, value in data.items():
        if key not in allowed:
            continue
        await pool.execute(
            """INSERT INTO settings (key, value, description)
               VALUES ($1, $2, $3)
               ON CONFLICT (key)
               DO UPDATE SET value=$2, updated_at=NOW()""",
            key, str(value),
            {"sms_enabled": "تفعيل إشعارات SMS",
             "sms_api_key": "مفتاح API لخدمة SMS",
             "sms_phone_numbers": "أرقام الهواتف (مفصولة بفاصلة)",
             "sms_device_id": "معرّف الجهاز"}.get(key, key),
        )
    return {"success": True, "message": "تم حفظ إعدادات SMS"}


@router.post("/send")
async def send_sms(body: SmsSendRequest):
    pool = await get_pool()
    s = await _get_sms_settings(pool)

    if s.get("sms_enabled", "false") != "true":
        raise HTTPException(status_code=400, detail="إشعارات SMS غير مفعّلة")

    api_key = s.get("sms_api_key", "").strip()
    if not api_key:
        raise HTTPException(status_code=400, detail="مفتاح SMS API غير مضبوط في الإعدادات")

    phones = body.phone_numbers
    if not phones:
        stored = s.get("sms_phone_numbers", "").strip()
        if not stored:
            raise HTTPException(status_code=400, detail="لا توجد أرقام هواتف مضبوطة")
        phones = [p.strip() for p in stored.split(",") if p.strip()]

    device_id = s.get("sms_device_id", "0")
    results = []

    async with httpx.AsyncClient(timeout=15.0) as client:
        for phone in phones:
            try:
                resp = await client.post(
                    "https://app.sms-gateway.app/services/send.php",
                    data={
                        "number": phone,
                        "message": body.message,
                        "key": api_key,
                        "devices": device_id,
                        "type": "sms",
                    },
                )
                ok = resp.status_code < 400
                results.append({"phone": phone, "success": ok, "status": resp.status_code})
                logger.info(f"[SMS] {'✅' if ok else '❌'} → {phone}: {resp.status_code}")
            except Exception as e:
                logger.error(f"[SMS] Error → {phone}: {e}")
                results.append({"phone": phone, "success": False, "error": str(e)})

    sent = len([r for r in results if r["success"]])
    return {"sent": sent, "total": len(phones), "results": results}


@router.post("/test")
async def test_sms(body: SmsSendRequest):
    body.message = f"[اختبار — مصنع البلاستيك] {body.message or 'هذه رسالة اختبار من نظام ERP'}"
    return await send_sms(body)
