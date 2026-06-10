import bcrypt
import jwt
from datetime import datetime, timedelta
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
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
