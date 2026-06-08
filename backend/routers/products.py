from fastapi import APIRouter
from pydantic import BaseModel
from typing import Optional
from database import get_pool

router = APIRouter(prefix="/api/products", tags=["products"])


class ProductUpsert(BaseModel):
    id: Optional[str] = None
    name: str
    code: Optional[str] = None
    description: Optional[str] = None
    is_active: Optional[bool] = True


@router.get("")
async def get_products():
    pool = await get_pool()
    rows = await pool.fetch("SELECT * FROM products WHERE is_active=true ORDER BY name")
    return [dict(r) for r in rows]


@router.post("/upsert")
async def upsert_product(body: ProductUpsert):
    pool = await get_pool()
    if body.id:
        row = await pool.fetchrow(
            "UPDATE products SET name=$1, code=$2, description=$3, is_active=$4 WHERE id=$5 RETURNING *",
            body.name, body.code, body.description, body.is_active, body.id,
        )
    else:
        row = await pool.fetchrow(
            "INSERT INTO products (id, name, code, description, is_active) VALUES (gen_random_uuid(), $1, $2, $3, $4) RETURNING *",
            body.name, body.code, body.description, body.is_active,
        )
    return dict(row)
