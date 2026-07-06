import bcrypt
import jwt
import random
import hashlib
import httpx
import logging
from datetime import datetime, timedelta
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional
from database import get_pool
from settings import SECRET_KEY

logger = logging.getLogger("plastic_factory")
router = APIRouter(prefix="/api/auth", tags=["auth"])

JWT_EXPIRY_DAYS = 7

# ── In-memory OTP store (single-process; sufficient for single-admin ERP) ─────
# Structure: { phone: { "hash": str, "expiry": datetime, "attempts": int } }
_otp_store: dict = {}
OTP_EXPIRY_MINUTES = 5
OTP_MAX_ATTEMPTS = 5

# Reset tokens: { token: { "expiry": datetime } }
_reset_tokens: dict = {}
RESET_TOKEN_EXPIRY_MINUTES = 10


# ── Models ────────────────────────────────────────────────────────────────────

class SignInRequest(BaseModel):
    email: str
    password: str


class SignUpRequest(BaseModel):
    email: str
    password: str


class ChangePasswordRequest(BaseModel):
    user_id: str
    current_password: str
    new_password: str


class ChangeEmailRequest(BaseModel):
    user_id: str
    current_password: str
    new_email: str


class SendOtpRequest(BaseModel):
    phone: str


class VerifyOtpRequest(BaseModel):
    phone: str
    code: str


class ResetPasswordWithTokenRequest(BaseModel):
    reset_token: str
    new_password: str


# ── Helpers ───────────────────────────────────────────────────────────────────

def make_token(user_id: str, email: str) -> str:
    payload = {
        "id": user_id,
        "email": email,
        "role": "admin",
        "exp": datetime.utcnow() + timedelta(days=JWT_EXPIRY_DAYS),
    }
    return jwt.encode(payload, SECRET_KEY, algorithm="HS256")


def _hash_otp(code: str) -> str:
    return hashlib.sha256(code.encode()).hexdigest()


async def _fetch_sms_settings(pool) -> dict:
    rows = await pool.fetch("SELECT key, value FROM settings WHERE key LIKE 'sms_%'")
    return {r["key"]: r["value"] for r in rows}


async def _send_sms_to_phone(pool, phone: str, message: str) -> None:
    """Send a single SMS via sms-gateway.app using stored settings."""
    s = await _fetch_sms_settings(pool)

    if s.get("sms_enabled", "false") != "true":
        raise HTTPException(
            status_code=400,
            detail="إشعارات SMS غير مفعّلة — فعّل SMS من الإعدادات أولاً",
        )

    api_key = s.get("sms_api_key", "").strip()
    if not api_key:
        raise HTTPException(
            status_code=400,
            detail="مفتاح SMS API غير مضبوط — أدخله من إعدادات SMS",
        )

    device_id = s.get("sms_device_id", "0")

    async with httpx.AsyncClient(timeout=15.0) as client:
        try:
            resp = await client.post(
                "https://app.sms-gateway.app/services/send.php",
                data={
                    "number": phone,
                    "message": message,
                    "key": api_key,
                    "devices": device_id,
                    "type": "sms",
                },
            )
            if resp.status_code >= 400:
                logger.error(f"[OTP-SMS] Failed → {phone}: {resp.status_code} {resp.text}")
                raise HTTPException(
                    status_code=502,
                    detail=f"فشل إرسال SMS (كود الخطأ: {resp.status_code})",
                )
            logger.info(f"[OTP-SMS] ✅ Sent to {phone}")
        except httpx.RequestError as e:
            logger.error(f"[OTP-SMS] Network error → {phone}: {e}")
            raise HTTPException(status_code=502, detail="خطأ في الاتصال بخدمة SMS")


# ── Auth endpoints ────────────────────────────────────────────────────────────

@router.post("/signin")
async def sign_in(body: SignInRequest):
    pool = await get_pool()
    row = await pool.fetchrow("SELECT * FROM admin_users WHERE email=$1", body.email)
    if not row:
        raise HTTPException(status_code=401, detail="بيانات خاطئة")
    if not bcrypt.checkpw(body.password.encode(), row["password_hash"].encode()):
        raise HTTPException(status_code=401, detail="بيانات خاطئة")
    token = make_token(str(row["id"]), row["email"])
    return {
        "token": token,
        "user": {
            "id": str(row["id"]),
            "email": row["email"],
            "name": row.get("name") or None,
            "role": row.get("role") or "admin",
        },
    }


@router.post("/signup")
async def sign_up(body: SignUpRequest):
    pool = await get_pool()
    hashed = bcrypt.hashpw(body.password.encode(), bcrypt.gensalt()).decode()
    try:
        row = await pool.fetchrow(
            "INSERT INTO admin_users (id, email, password_hash) VALUES (gen_random_uuid(), $1, $2) RETURNING id, email",
            body.email, hashed,
        )
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
    token = make_token(str(row["id"]), row["email"])
    return {"token": token, "user": {"id": str(row["id"]), "email": row["email"]}}


@router.put("/change-password")
async def change_password(body: ChangePasswordRequest):
    pool = await get_pool()
    row = await pool.fetchrow("SELECT * FROM admin_users WHERE id=$1::uuid", body.user_id)
    if not row:
        raise HTTPException(status_code=404, detail="المستخدم غير موجود")
    if not bcrypt.checkpw(body.current_password.encode(), row["password_hash"].encode()):
        raise HTTPException(status_code=401, detail="كلمة المرور الحالية غير صحيحة")
    if len(body.new_password) < 6:
        raise HTTPException(status_code=400, detail="كلمة المرور الجديدة يجب أن تكون 6 أحرف على الأقل")
    hashed = bcrypt.hashpw(body.new_password.encode(), bcrypt.gensalt()).decode()
    await pool.execute(
        "UPDATE admin_users SET password_hash=$1 WHERE id=$2::uuid",
        hashed, body.user_id,
    )
    return {"success": True, "message": "تم تغيير كلمة المرور بنجاح"}


@router.put("/change-email")
async def change_email(body: ChangeEmailRequest):
    pool = await get_pool()
    row = await pool.fetchrow("SELECT * FROM admin_users WHERE id=$1::uuid", body.user_id)
    if not row:
        raise HTTPException(status_code=404, detail="المستخدم غير موجود")
    if not bcrypt.checkpw(body.current_password.encode(), row["password_hash"].encode()):
        raise HTTPException(status_code=401, detail="كلمة المرور غير صحيحة")
    existing = await pool.fetchrow(
        "SELECT id FROM admin_users WHERE email=$1 AND id!=$2::uuid",
        body.new_email, body.user_id,
    )
    if existing:
        raise HTTPException(status_code=400, detail="البريد الإلكتروني مستخدم من قِبَل حساب آخر")
    await pool.execute(
        "UPDATE admin_users SET email=$1 WHERE id=$2::uuid",
        body.new_email, body.user_id,
    )
    token = make_token(body.user_id, body.new_email)
    return {
        "success": True,
        "message": "تم تغيير البريد الإلكتروني بنجاح",
        "token": token,
        "user": {"id": body.user_id, "email": body.new_email},
    }


# ── Warehouse Manager Account (admin-controlled) ──────────────────────────────

class WarehouseAccountRequest(BaseModel):
    email: str
    password: str
    name: Optional[str] = None


@router.get("/warehouse-account")
async def get_warehouse_account():
    """Return the warehouse manager account (email + name) or null if not yet created."""
    pool = await get_pool()
    row = await pool.fetchrow(
        "SELECT id, email, name FROM admin_users WHERE role='warehouse_manager' LIMIT 1"
    )
    if row:
        return {"exists": True, "email": row["email"], "name": row["name"]}
    return {"exists": False, "email": None, "name": None}


@router.put("/warehouse-account")
async def upsert_warehouse_account(body: WarehouseAccountRequest):
    """Admin creates or updates the warehouse manager credentials (no old-password required)."""
    pool = await get_pool()
    if not body.email or not body.password:
        raise HTTPException(status_code=400, detail="البريد وكلمة المرور مطلوبان")
    if len(body.password) < 6:
        raise HTTPException(status_code=400, detail="كلمة المرور يجب أن تكون 6 أحرف على الأقل")

    # Check if email used by a non-warehouse account
    conflict = await pool.fetchrow(
        "SELECT id FROM admin_users WHERE email=$1 AND role!='warehouse_manager'", body.email
    )
    if conflict:
        raise HTTPException(status_code=400, detail="هذا البريد مستخدم من قِبَل حساب إداري آخر")

    hashed = bcrypt.hashpw(body.password.encode(), bcrypt.gensalt()).decode()
    existing = await pool.fetchrow(
        "SELECT id FROM admin_users WHERE role='warehouse_manager' LIMIT 1"
    )
    if existing:
        await pool.execute(
            "UPDATE admin_users SET email=$1, password_hash=$2, name=$3 WHERE id=$4",
            body.email, hashed, body.name, existing["id"],
        )
    else:
        await pool.execute(
            "INSERT INTO admin_users (id, email, password_hash, role, name) "
            "VALUES (gen_random_uuid(), $1, $2, 'warehouse_manager', $3)",
            body.email, hashed, body.name,
        )
    return {"success": True, "message": "تم حفظ بيانات أمين المخزن بنجاح"}


# ── OTP / Forgot-password flow ────────────────────────────────────────────────

@router.post("/send-otp")
async def send_otp(body: SendOtpRequest):
    """
    Step 1 — generate a 6-digit OTP, send it via SMS, store its hash.
    The phone number must match sms_phone_numbers stored in settings.
    """
    phone = body.phone.strip()
    if not phone:
        raise HTTPException(status_code=400, detail="أدخل رقم الهاتف")

    pool = await get_pool()

    # Verify the phone is registered in SMS settings
    s = await _fetch_sms_settings(pool)
    stored_phones = [p.strip() for p in s.get("sms_phone_numbers", "").split(",") if p.strip()]

    # Normalize: strip spaces / leading zeros for loose match
    def _norm(p: str) -> str:
        return p.replace(" ", "").replace("+", "").lstrip("0")

    norm_input = _norm(phone)
    matched = any(_norm(sp) == norm_input for sp in stored_phones)
    if not matched:
        raise HTTPException(
            status_code=404,
            detail="رقم الهاتف غير مسجّل في إعدادات النظام",
        )

    # Generate OTP
    code = f"{random.randint(100000, 999999)}"
    expiry = datetime.utcnow() + timedelta(minutes=OTP_EXPIRY_MINUTES)
    _otp_store[phone] = {
        "hash": _hash_otp(code),
        "expiry": expiry,
        "attempts": 0,
    }

    message = f"كود التحقق لإعادة تعيين كلمة مرور نظام مصنع البلاستيك: {code}\nصالح لمدة {OTP_EXPIRY_MINUTES} دقائق."

    await _send_sms_to_phone(pool, phone, message)
    logger.info(f"[OTP] Code sent to {phone} (expires {expiry})")

    return {"success": True, "message": f"تم إرسال كود التحقق إلى {phone}"}


@router.post("/verify-otp")
async def verify_otp(body: VerifyOtpRequest):
    """
    Step 2 — verify the OTP code. Returns a short-lived reset_token on success.
    """
    phone = body.phone.strip()
    entry = _otp_store.get(phone)

    if not entry:
        raise HTTPException(status_code=400, detail="لا يوجد كود تحقق لهذا الرقم — أرسل كوداً جديداً")

    if datetime.utcnow() > entry["expiry"]:
        _otp_store.pop(phone, None)
        raise HTTPException(status_code=400, detail="انتهت صلاحية كود التحقق — أرسل كوداً جديداً")

    entry["attempts"] += 1
    if entry["attempts"] > OTP_MAX_ATTEMPTS:
        _otp_store.pop(phone, None)
        raise HTTPException(status_code=429, detail="تجاوزت الحد المسموح به — أرسل كوداً جديداً")

    if _hash_otp(body.code.strip()) != entry["hash"]:
        remaining = OTP_MAX_ATTEMPTS - entry["attempts"]
        raise HTTPException(
            status_code=400,
            detail=f"كود التحقق غير صحيح — محاولات متبقية: {max(remaining, 0)}",
        )

    # OTP correct — generate reset token
    _otp_store.pop(phone, None)
    import uuid
    reset_token = str(uuid.uuid4())
    _reset_tokens[reset_token] = {
        "expiry": datetime.utcnow() + timedelta(minutes=RESET_TOKEN_EXPIRY_MINUTES),
    }
    logger.info(f"[OTP] ✅ Verified for {phone} → reset_token issued")

    return {"success": True, "reset_token": reset_token, "message": "تم التحقق بنجاح"}


@router.post("/reset-password-with-token")
async def reset_password_with_token(body: ResetPasswordWithTokenRequest):
    """
    Step 3 — reset the admin password using the reset_token from step 2.
    Only one admin user is assumed (the first row).
    """
    entry = _reset_tokens.get(body.reset_token)
    if not entry:
        raise HTTPException(status_code=400, detail="رمز إعادة التعيين غير صالح أو منتهي الصلاحية")

    if datetime.utcnow() > entry["expiry"]:
        _reset_tokens.pop(body.reset_token, None)
        raise HTTPException(status_code=400, detail="انتهت صلاحية رمز إعادة التعيين — ابدأ العملية مجدداً")

    if len(body.new_password) < 6:
        raise HTTPException(status_code=400, detail="كلمة المرور يجب أن تكون 6 أحرف على الأقل")

    pool = await get_pool()
    row = await pool.fetchrow("SELECT id, email FROM admin_users ORDER BY created_at LIMIT 1")
    if not row:
        raise HTTPException(status_code=404, detail="لا يوجد مستخدم أدمن مسجّل")

    hashed = bcrypt.hashpw(body.new_password.encode(), bcrypt.gensalt()).decode()
    await pool.execute(
        "UPDATE admin_users SET password_hash=$1 WHERE id=$2",
        hashed, row["id"],
    )

    _reset_tokens.pop(body.reset_token, None)
    logger.info(f"[OTP] ✅ Password reset for admin {row['email']}")

    return {"success": True, "message": "تم إعادة تعيين كلمة المرور بنجاح — يمكنك تسجيل الدخول الآن"}
