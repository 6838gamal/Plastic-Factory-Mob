import json
from fastapi import APIRouter, Query
from pydantic import BaseModel
from typing import Optional, List, Any
from database import get_pool

router = APIRouter(prefix="/api/batches", tags=["batches"])


class BatchCreate(BaseModel):
    batch_number: str
    date: str
    shift: Optional[str] = None
    worker_id: Optional[str] = None
    worker_name: Optional[str] = None
    mixer_id: Optional[str] = None
    mixer_name: Optional[str] = None
    product_id: Optional[str] = None
    product_name: Optional[str] = None
    mixture_type_id: Optional[str] = None
    mixture_type_name: Optional[str] = None
    pvc_qty: Optional[float] = 0
    dop_qty: Optional[float] = 0
    scrap_qty: Optional[float] = 0
    calcium_qty: Optional[float] = 0
    wax_qty: Optional[float] = 0
    stabilizer_qty: Optional[float] = 0
    titanium_qty: Optional[float] = 0
    pigments: Optional[List[Any]] = []
    additives: Optional[List[Any]] = []
    materials: Optional[List[Any]] = []
    notes: Optional[str] = None
    scale_image_url: Optional[str] = None
    transaction_id: Optional[str] = None
    status: Optional[str] = "saved"


class BatchUpdate(BatchCreate):
    pass


def serialize_row(row) -> dict:
    d = dict(row)
    for k in ("pigments", "additives", "materials"):
        if k in d and isinstance(d[k], str):
            d[k] = json.loads(d[k])
    return d


@router.get("")
async def get_batches(
    from_: Optional[str] = Query(None, alias="from"),
    to: Optional[str] = Query(None),
    worker_id: Optional[str] = Query(None),
):
    pool = await get_pool()
    conditions = ["1=1"]
    params = []
    i = 1
    if from_:
        conditions.append(f"date::text>=${i}"); params.append(from_[:10]); i += 1
    if to:
        conditions.append(f"date::text<=${i}"); params.append(to[:10]); i += 1
    if worker_id:
        conditions.append(f"worker_id=${i}"); params.append(worker_id); i += 1
    query = f"SELECT * FROM batches WHERE {' AND '.join(conditions)} ORDER BY created_at DESC"
    rows = await pool.fetch(query, *params)
    return [serialize_row(r) for r in rows]


@router.get("/check-transaction/{transaction_id}")
async def check_transaction(transaction_id: str):
    pool = await get_pool()
    row = await pool.fetchrow("SELECT id FROM batches WHERE transaction_id=$1", transaction_id)
    return {"exists": row is not None}


@router.post("")
async def create_batch(body: BatchCreate):
    pool = await get_pool()
    row = await pool.fetchrow(
        """INSERT INTO batches (
            id, batch_number, date, shift, worker_id, worker_name, mixer_id, mixer_name,
            product_id, product_name, mixture_type_id, mixture_type_name,
            pvc_qty, dop_qty, scrap_qty, calcium_qty, wax_qty, stabilizer_qty, titanium_qty,
            pigments, additives, materials, notes, scale_image_url, transaction_id, status
        ) VALUES (
            gen_random_uuid(), $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11,
            $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, $22, $23, $24, $25
        ) RETURNING *""",
        body.batch_number, body.date, body.shift,
        body.worker_id, body.worker_name, body.mixer_id, body.mixer_name,
        body.product_id, body.product_name, body.mixture_type_id, body.mixture_type_name,
        body.pvc_qty, body.dop_qty, body.scrap_qty, body.calcium_qty,
        body.wax_qty, body.stabilizer_qty, body.titanium_qty,
        json.dumps(body.pigments or []),
        json.dumps(body.additives or []),
        json.dumps(body.materials or []),
        body.notes, body.scale_image_url, body.transaction_id, body.status,
    )
    return serialize_row(row)


@router.put("/{batch_id}")
async def update_batch(batch_id: str, body: BatchUpdate):
    pool = await get_pool()
    row = await pool.fetchrow(
        """UPDATE batches SET
            batch_number=$1, date=$2, shift=$3, worker_id=$4, worker_name=$5,
            mixer_id=$6, mixer_name=$7, product_id=$8, product_name=$9,
            mixture_type_id=$10, mixture_type_name=$11,
            pvc_qty=$12, dop_qty=$13, scrap_qty=$14, calcium_qty=$15,
            wax_qty=$16, stabilizer_qty=$17, titanium_qty=$18,
            pigments=$19, additives=$20, materials=$21, notes=$22,
            scale_image_url=$23, status=$24, updated_at=NOW()
           WHERE id=$25 RETURNING *""",
        body.batch_number, body.date, body.shift,
        body.worker_id, body.worker_name, body.mixer_id, body.mixer_name,
        body.product_id, body.product_name, body.mixture_type_id, body.mixture_type_name,
        body.pvc_qty, body.dop_qty, body.scrap_qty, body.calcium_qty,
        body.wax_qty, body.stabilizer_qty, body.titanium_qty,
        json.dumps(body.pigments or []),
        json.dumps(body.additives or []),
        json.dumps(body.materials or []),
        body.notes, body.scale_image_url, body.status, batch_id,
    )
    return serialize_row(row)
