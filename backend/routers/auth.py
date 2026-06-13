import bcrypt
import jwt
from datetime import datetime, timedelta
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional
from database import get_pool
from settings import SECRET_KEY

router = APIRouter(prefix="/api/auth", tags=["auth"])

JWT_EXPIRY_DAYS = 7


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


class ForgotPasswordRequest(BaseModel):
    email: str
    new_password: str


def make_token(user_id: str, email: str) -> str:
    payload = {
        "id": user_id,
        "email": email,
        "role": "admin",
        "exp": datetime.utcnow() + timedelta(days=JWT_EXPIRY_DAYS),
    }
    return jwt.encode(payload, SECRET_KEY, algorithm="HS256")


@router.post("/signin")
async def sign_in(body: SignInRequest):
    pool = await get_pool()
    row = await pool.fetchrow("SELECT * FROM admin_users WHERE email=$1", body.email)
    if not row:
        raise HTTPException(status_code=401, detail="بيانات خاطئة")
    if not bcrypt.checkpw(body.password.encode(), row["password_hash"].encode()):
        raise HTTPException(status_code=401, detail="بيانات خاطئة")
    token = make_token(str(row["id"]), row["email"])
    return {"token": token, "user": {"id": str(row["id"]), "email": row["email"]}}


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


@router.post("/forgot-password")
async def forgot_password(body: ForgotPasswordRequest):
    pool = await get_pool()
    row = await pool.fetchrow("SELECT * FROM admin_users WHERE email=$1", body.email)
    if not row:
        raise HTTPException(status_code=404, detail="البريد الإلكتروني غير مسجّل في النظام")
    if len(body.new_password) < 6:
        raise HTTPException(status_code=400, detail="كلمة المرور يجب أن تكون 6 أحرف على الأقل")
    hashed = bcrypt.hashpw(body.new_password.encode(), bcrypt.gensalt()).decode()
    await pool.execute(
        "UPDATE admin_users SET password_hash=$1 WHERE email=$2",
        hashed, body.email,
    )
    return {"success": True, "message": "تم إعادة تعيين كلمة المرور بنجاح"}
