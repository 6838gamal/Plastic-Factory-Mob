"""
Vouchers router — Receipt, Transfer, and Return vouchers.

Flows:
  Receipt Vouchers (وارد خارجي):
    POST /receipt             — create draft
    GET  /receipt             — list all
    GET  /receipt/{id}        — single voucher with items
    PATCH /receipt/{id}       — edit (only if draft)
    POST /receipt/{id}/post   — post: add inventory 'in' transactions

  Transfer Vouchers (تحويل داخلي):
    POST /transfer            — create draft
    GET  /transfer            — list all (filter by status)
    GET  /transfer/{id}       — single voucher with items
    PATCH /transfer/{id}      — edit items/notes (only if draft/pending)
    POST /transfer/{id}/submit   — change to 'pending' (send to mixer)
    POST /transfer/{id}/confirm  — mixing supervisor confirms → inventory moves
    POST /transfer/{id}/cancel   — cancel (only if not confirmed)

  Return Vouchers (مرتجع):
    POST /return              — create from confirmed transfer
    GET  /return              — list all
    GET  /return/{id}         — single voucher with items
    POST /return/{id}/post    — post: reverse inventory (mixer→main)
"""
import logging
from datetime import date as DateType, datetime, timezone
from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import Optional, List, Any
from database import get_pool

logger = logging.getLogger("plastic_factory.vouchers")
router = APIRouter(prefix="/api/vouchers", tags=["vouchers"])


# ─────────────────────── Pydantic Models ─────────────────────────

class VoucherItem(BaseModel):
    material_id: Optional[str] = None
    material_name: str
    unit: str = "كجم"
    requested_qty: float
    confirmed_qty: Optional[float] = None
    notes: Optional[str] = None


class ReceiptVoucherCreate(BaseModel):
    supplier_name: Optional[str] = None
    supplier_phone: Optional[str] = None
    supplier_ref: Optional[str] = None
    date: Optional[DateType] = None
    notes: Optional[str] = None
    created_by: Optional[str] = "admin"
    received_by: Optional[str] = None
    items: List[VoucherItem] = []


class TransferVoucherCreate(BaseModel):
    notes: Optional[str] = None
    created_by: Optional[str] = "admin"
    items: List[VoucherItem] = []


class ReturnVoucherCreate(BaseModel):
    original_voucher_id: str
    reason: Optional[str] = None
    created_by: Optional[str] = "admin"
    items: List[VoucherItem] = []


class ConfirmTransferRequest(BaseModel):
    confirmed_by: Optional[str] = "مشرف الخلطات"
    items: Optional[List[VoucherItem]] = None  # override confirmed_qty per item


class ItemsUpdate(BaseModel):
    supplier_name: Optional[str] = None
    supplier_phone: Optional[str] = None
    supplier_ref: Optional[str] = None
    received_by: Optional[str] = None
    notes: Optional[str] = None
    items: List[VoucherItem] = []


# ─────────────────────── Helpers ─────────────────────────────────

async def _next_voucher_number(pool, prefix: str) -> str:
    today = DateType.today().strftime("%Y%m%d")
    count = await pool.fetchval(
        f"SELECT COUNT(*) FROM {prefix}_vouchers WHERE created_at::date = CURRENT_DATE"
    )
    return f"{prefix.upper()}-{today}-{int(count)+1:03d}"


async def _write_audit(pool, action: str, entity_type: str, entity_id: str,
                       performed_by: str, details: dict):
    import json
    try:
        await pool.execute(
            """INSERT INTO audit_log (entity_type, entity_id, action, performed_by, details)
               VALUES ($1, $2, $3, $4, $5)""",
            entity_type, entity_id, action, performed_by, json.dumps(details, ensure_ascii=False),
        )
    except Exception as exc:
        logger.warning(f"[audit] Could not write audit log: {exc}")


def _row_to_dict(row) -> dict:
    if row is None:
        return {}
    d = dict(row)
    for k, v in d.items():
        if isinstance(v, datetime):
            d[k] = v.isoformat()
        elif isinstance(v, DateType):
            d[k] = v.isoformat()
    return d


# ═══════════════════════════════════════════════════════════════════
#  RECEIPT VOUCHERS  (سندات الاستلام - وارد خارجي)
# ═══════════════════════════════════════════════════════════════════

@router.get("/receipt")
async def list_receipt_vouchers(status: Optional[str] = Query(None)):
    pool = await get_pool()
    rows = await pool.fetch(
        """SELECT rv.*, COUNT(ri.id)::int AS item_count
           FROM receipt_vouchers rv
           LEFT JOIN receipt_voucher_items ri ON ri.voucher_id = rv.id
           WHERE ($1::text IS NULL OR rv.status = $1)
           GROUP BY rv.id
           ORDER BY rv.created_at DESC""",
        status
    )
    return [_row_to_dict(r) for r in rows]


@router.get("/receipt/{voucher_id}")
async def get_receipt_voucher(voucher_id: str):
    pool = await get_pool()
    voucher = await pool.fetchrow("SELECT * FROM receipt_vouchers WHERE id=$1::uuid", voucher_id)
    if not voucher:
        raise HTTPException(404, "سند الاستلام غير موجود")
    items = await pool.fetch(
        "SELECT * FROM receipt_voucher_items WHERE voucher_id=$1::uuid ORDER BY created_at",
        voucher_id
    )
    result = _row_to_dict(voucher)
    result["items"] = [_row_to_dict(i) for i in items]
    return result


@router.post("/receipt")
async def create_receipt_voucher(body: ReceiptVoucherCreate):
    pool = await get_pool()
    voucher_no = await _next_voucher_number(pool, "receipt")
    voucher_date = body.date or DateType.today()

    vid = await pool.fetchval(
        """INSERT INTO receipt_vouchers
             (voucher_number, supplier_name, supplier_phone, supplier_ref, date, notes, created_by, received_by)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id""",
        voucher_no, body.supplier_name, body.supplier_phone, body.supplier_ref,
        voucher_date, body.notes, body.created_by, body.received_by
    )

    for item in body.items:
        await pool.execute(
            """INSERT INTO receipt_voucher_items
                 (voucher_id, material_id, material_name, unit, quantity, notes)
               VALUES ($1::uuid, $2, $3, $4, $5, $6)""",
            str(vid), item.material_id, item.material_name, item.unit,
            item.requested_qty, item.notes
        )

    await _write_audit(pool, "create", "receipt_voucher", str(vid), body.created_by or "admin",
                       {"voucher_number": voucher_no, "items": len(body.items)})
    return {"id": str(vid), "voucher_number": voucher_no, "status": "draft"}


@router.patch("/receipt/{voucher_id}")
async def update_receipt_voucher(voucher_id: str, body: ItemsUpdate):
    pool = await get_pool()
    v = await pool.fetchrow("SELECT status FROM receipt_vouchers WHERE id=$1::uuid", voucher_id)
    if not v:
        raise HTTPException(404, "سند الاستلام غير موجود")
    if v["status"] == "posted":
        raise HTTPException(400, "لا يمكن تعديل سند مُرحَّل")

    await pool.execute(
        """UPDATE receipt_vouchers
           SET supplier_name=COALESCE($1, supplier_name),
               supplier_phone=COALESCE($2, supplier_phone),
               supplier_ref=COALESCE($3, supplier_ref),
               received_by=COALESCE($4, received_by),
               notes=$5,
               updated_at=NOW()
           WHERE id=$6::uuid""",
        body.supplier_name, body.supplier_phone, body.supplier_ref,
        body.received_by, body.notes, voucher_id
    )
    await pool.execute("DELETE FROM receipt_voucher_items WHERE voucher_id=$1::uuid", voucher_id)
    for item in body.items:
        await pool.execute(
            """INSERT INTO receipt_voucher_items
                 (voucher_id, material_id, material_name, unit, quantity, notes)
               VALUES ($1::uuid, $2, $3, $4, $5, $6)""",
            voucher_id, item.material_id, item.material_name, item.unit,
            item.requested_qty, item.notes
        )
    await _write_audit(pool, "update", "receipt_voucher", voucher_id, "admin",
                       {"items_updated": len(body.items)})
    return {"status": "updated"}


@router.post("/receipt/{voucher_id}/post")
async def post_receipt_voucher(voucher_id: str, performed_by: str = "admin"):
    pool = await get_pool()
    v = await pool.fetchrow("SELECT * FROM receipt_vouchers WHERE id=$1::uuid", voucher_id)
    if not v:
        raise HTTPException(404, "سند الاستلام غير موجود")
    if v["status"] == "posted":
        raise HTTPException(400, "السند مُرحَّل مسبقاً")

    items = await pool.fetch(
        "SELECT * FROM receipt_voucher_items WHERE voucher_id=$1::uuid", voucher_id
    )
    if not items:
        raise HTTPException(400, "لا يوجد بنود في السند")

    for item in items:
        mat_id = item["material_id"]

        # Fallback: look up by name when ID is missing
        if not mat_id:
            found = await pool.fetchrow(
                "SELECT id FROM raw_materials WHERE LOWER(name) = LOWER($1)",
                item["material_name"],
            )
            if found:
                mat_id = str(found["id"])
                await pool.execute(
                    "UPDATE receipt_voucher_items SET material_id=$1::uuid WHERE id=$2",
                    mat_id, item["id"],
                )
            else:
                logger.warning(
                    f"[post_receipt] No raw_material found for name='{item['material_name']}' — skipping"
                )
                continue

        qty = float(item["quantity"])

        # Add to main warehouse inventory
        existing = await pool.fetchrow(
            "SELECT id, balance FROM inventory WHERE material_id=$1::uuid AND warehouse_type='main'",
            mat_id
        )
        if existing:
            balance_before = float(existing["balance"])
            balance_after = balance_before + qty
            await pool.execute(
                "UPDATE inventory SET balance=$1, updated_at=NOW() WHERE id=$2",
                balance_after, existing["id"]
            )
        else:
            balance_before = 0.0
            balance_after = qty
            await pool.execute(
                """INSERT INTO inventory (material_id, warehouse_type, balance)
                   VALUES ($1::uuid, 'main', $2)""",
                mat_id, qty
            )

        await pool.execute(
            """INSERT INTO inventory_transactions
                 (material_id, warehouse_type, transaction_type, quantity,
                  balance_before, balance_after, transaction_ref, created_by, notes)
               VALUES ($1::uuid,'main','in',$2,$3,$4,$5,$6,$7)""",
            mat_id, qty, balance_before, balance_after,
            v["voucher_number"], performed_by,
            f"سند استلام رقم {v['voucher_number']}"
        )

    await pool.execute(
        "UPDATE receipt_vouchers SET status='posted', updated_at=NOW() WHERE id=$1::uuid",
        voucher_id
    )
    await _write_audit(pool, "post", "receipt_voucher", voucher_id, performed_by,
                       {"voucher_number": v["voucher_number"], "items": len(items)})
    return {"status": "posted", "items_processed": len(items)}


# ═══════════════════════════════════════════════════════════════════
#  TRANSFER VOUCHERS  (سندات التحويل الداخلي)
# ═══════════════════════════════════════════════════════════════════

@router.get("/transfer")
async def list_transfer_vouchers(status: Optional[str] = Query(None)):
    pool = await get_pool()
    rows = await pool.fetch(
        """SELECT tv.*, COUNT(ti.id)::int AS item_count
           FROM transfer_vouchers tv
           LEFT JOIN transfer_voucher_items ti ON ti.voucher_id = tv.id
           WHERE ($1::text IS NULL OR tv.status = $1)
           GROUP BY tv.id
           ORDER BY tv.created_at DESC""",
        status
    )
    return [_row_to_dict(r) for r in rows]


@router.get("/transfer/pending")
async def list_pending_transfers():
    pool = await get_pool()
    rows = await pool.fetch(
        """SELECT tv.*, COUNT(ti.id)::int AS item_count
           FROM transfer_vouchers tv
           LEFT JOIN transfer_voucher_items ti ON ti.voucher_id = tv.id
           WHERE tv.status = 'pending'
           GROUP BY tv.id
           ORDER BY tv.created_at ASC""",
    )
    return [_row_to_dict(r) for r in rows]


@router.get("/transfer/{voucher_id}")
async def get_transfer_voucher(voucher_id: str):
    pool = await get_pool()
    voucher = await pool.fetchrow("SELECT * FROM transfer_vouchers WHERE id=$1::uuid", voucher_id)
    if not voucher:
        raise HTTPException(404, "سند التحويل غير موجود")
    items = await pool.fetch(
        "SELECT * FROM transfer_voucher_items WHERE voucher_id=$1::uuid ORDER BY created_at",
        voucher_id
    )
    result = _row_to_dict(voucher)
    result["items"] = [_row_to_dict(i) for i in items]
    return result


@router.post("/transfer")
async def create_transfer_voucher(body: TransferVoucherCreate):
    pool = await get_pool()
    voucher_no = await _next_voucher_number(pool, "transfer")

    vid = await pool.fetchval(
        """INSERT INTO transfer_vouchers (voucher_number, notes, created_by)
           VALUES ($1, $2, $3) RETURNING id""",
        voucher_no, body.notes, body.created_by
    )

    for item in body.items:
        await pool.execute(
            """INSERT INTO transfer_voucher_items
                 (voucher_id, material_id, material_name, unit, requested_qty, notes)
               VALUES ($1::uuid, $2, $3, $4, $5, $6)""",
            str(vid), item.material_id, item.material_name, item.unit,
            item.requested_qty, item.notes
        )

    await _write_audit(pool, "create", "transfer_voucher", str(vid), body.created_by or "admin",
                       {"voucher_number": voucher_no})
    return {"id": str(vid), "voucher_number": voucher_no, "status": "draft"}


@router.patch("/transfer/{voucher_id}")
async def update_transfer_voucher(voucher_id: str, body: ItemsUpdate):
    pool = await get_pool()
    v = await pool.fetchrow("SELECT status FROM transfer_vouchers WHERE id=$1::uuid", voucher_id)
    if not v:
        raise HTTPException(404, "سند التحويل غير موجود")
    if v["status"] == "confirmed":
        raise HTTPException(400, "لا يمكن تعديل سند مُؤكَّد — أنشئ سند مرتجع للتسوية")
    if v["status"] == "cancelled":
        raise HTTPException(400, "السند ملغى")

    await pool.execute(
        "UPDATE transfer_vouchers SET notes=$1, updated_at=NOW() WHERE id=$2::uuid",
        body.notes, voucher_id
    )
    await pool.execute("DELETE FROM transfer_voucher_items WHERE voucher_id=$1::uuid", voucher_id)
    for item in body.items:
        await pool.execute(
            """INSERT INTO transfer_voucher_items
                 (voucher_id, material_id, material_name, unit, requested_qty, notes)
               VALUES ($1::uuid, $2, $3, $4, $5, $6)""",
            voucher_id, item.material_id, item.material_name, item.unit,
            item.requested_qty, item.notes
        )
    await _write_audit(pool, "update", "transfer_voucher", voucher_id, "admin",
                       {"items_updated": len(body.items)})
    return {"status": "updated"}


@router.post("/transfer/{voucher_id}/submit")
async def submit_transfer_voucher(voucher_id: str, submitted_by: str = "admin"):
    pool = await get_pool()
    v = await pool.fetchrow("SELECT * FROM transfer_vouchers WHERE id=$1::uuid", voucher_id)
    if not v:
        raise HTTPException(404, "سند التحويل غير موجود")
    if v["status"] != "draft":
        raise HTTPException(400, f"لا يمكن إرسال سند بحالة: {v['status']}")

    items = await pool.fetch(
        "SELECT * FROM transfer_voucher_items WHERE voucher_id=$1::uuid", voucher_id
    )
    if not items:
        raise HTTPException(400, "لا يوجد بنود في السند")

    await pool.execute(
        "UPDATE transfer_vouchers SET status='pending', updated_at=NOW() WHERE id=$1::uuid",
        voucher_id
    )
    await _write_audit(pool, "submit", "transfer_voucher", voucher_id, submitted_by,
                       {"voucher_number": v["voucher_number"]})
    return {"status": "pending", "message": "السند في انتظار التأكيد من مشرف الخلطات"}


@router.post("/transfer/{voucher_id}/confirm")
async def confirm_transfer_voucher(voucher_id: str, body: ConfirmTransferRequest):
    pool = await get_pool()
    v = await pool.fetchrow("SELECT * FROM transfer_vouchers WHERE id=$1::uuid", voucher_id)
    if not v:
        raise HTTPException(404, "سند التحويل غير موجود")
    if v["status"] == "confirmed":
        raise HTTPException(400, "السند مُؤكَّد مسبقاً")
    if v["status"] not in ("pending", "draft"):
        raise HTTPException(400, f"لا يمكن تأكيد سند بحالة: {v['status']}")

    items_db = await pool.fetch(
        "SELECT * FROM transfer_voucher_items WHERE voucher_id=$1::uuid", voucher_id
    )
    if not items_db:
        raise HTTPException(400, "لا يوجد بنود في السند")

    # Build confirmed quantities map (override from body if provided)
    override_map = {}
    if body.items:
        for oi in body.items:
            override_map[oi.material_name] = oi.confirmed_qty or oi.requested_qty

    processed = 0
    skipped = 0
    for item in items_db:
        mat_id = item["material_id"]

        # Fallback: look up material by name if ID is missing
        if not mat_id:
            found = await pool.fetchrow(
                "SELECT id FROM raw_materials WHERE LOWER(name) = LOWER($1)",
                item["material_name"],
            )
            if found:
                mat_id = str(found["id"])
                # Update the item row so future operations use the correct ID
                await pool.execute(
                    "UPDATE transfer_voucher_items SET material_id=$1::uuid WHERE id=$2",
                    mat_id, item["id"],
                )
            else:
                logger.warning(
                    f"[confirm_transfer] No raw_material found for name='{item['material_name']}' — skipping"
                )
                skipped += 1
                continue

        confirmed_qty = override_map.get(item["material_name"], float(item["requested_qty"]))
        if confirmed_qty <= 0:
            continue

        # Update confirmed_qty on the item
        await pool.execute(
            "UPDATE transfer_voucher_items SET confirmed_qty=$1 WHERE id=$2",
            confirmed_qty, item["id"]
        )

        # Deduct from main warehouse
        main_inv = await pool.fetchrow(
            "SELECT id, balance FROM inventory WHERE material_id=$1::uuid AND warehouse_type='main'",
            mat_id
        )
        main_balance_before = float(main_inv["balance"]) if main_inv else 0.0
        main_balance_after = max(0, main_balance_before - confirmed_qty)
        if main_inv:
            await pool.execute(
                "UPDATE inventory SET balance=$1, updated_at=NOW() WHERE id=$2",
                main_balance_after, main_inv["id"]
            )
        await pool.execute(
            """INSERT INTO inventory_transactions
                 (material_id, warehouse_type, transaction_type, quantity,
                  balance_before, balance_after, transaction_ref, created_by, notes)
               VALUES ($1::uuid,'main','transfer_out',$2,$3,$4,$5,$6,$7)""",
            mat_id, confirmed_qty, main_balance_before, main_balance_after,
            v["voucher_number"], body.confirmed_by,
            f"تحويل للخلاط — سند {v['voucher_number']}"
        )

        # Add to mixer warehouse
        mix_inv = await pool.fetchrow(
            "SELECT id, balance FROM inventory WHERE material_id=$1::uuid AND warehouse_type='mixer'",
            mat_id
        )
        mix_balance_before = float(mix_inv["balance"]) if mix_inv else 0.0
        mix_balance_after = mix_balance_before + confirmed_qty
        if mix_inv:
            await pool.execute(
                "UPDATE inventory SET balance=$1, updated_at=NOW() WHERE id=$2",
                mix_balance_after, mix_inv["id"]
            )
        else:
            await pool.execute(
                """INSERT INTO inventory (material_id, warehouse_type, balance)
                   VALUES ($1::uuid, 'mixer', $2)""",
                mat_id, mix_balance_after
            )
        await pool.execute(
            """INSERT INTO inventory_transactions
                 (material_id, warehouse_type, transaction_type, quantity,
                  balance_before, balance_after, transaction_ref, created_by, notes)
               VALUES ($1::uuid,'mixer','transfer_in',$2,$3,$4,$5,$6,$7)""",
            mat_id, confirmed_qty, mix_balance_before, mix_balance_after,
            v["voucher_number"], body.confirmed_by,
            f"وارد من المخزن الرئيسي — سند {v['voucher_number']}"
        )
        processed += 1

    now = datetime.now(timezone.utc)
    await pool.execute(
        """UPDATE transfer_vouchers
           SET status='confirmed', confirmed_by=$1, confirmed_at=$2, updated_at=NOW()
           WHERE id=$3::uuid""",
        body.confirmed_by, now, voucher_id
    )
    await _write_audit(pool, "confirm", "transfer_voucher", voucher_id,
                       body.confirmed_by or "مشرف الخلطات",
                       {"voucher_number": v["voucher_number"], "items_processed": processed, "items_skipped": skipped})
    return {"status": "confirmed", "items_processed": processed, "items_skipped": skipped}


@router.post("/transfer/{voucher_id}/cancel")
async def cancel_transfer_voucher(voucher_id: str, cancelled_by: str = "admin"):
    pool = await get_pool()
    v = await pool.fetchrow("SELECT status FROM transfer_vouchers WHERE id=$1::uuid", voucher_id)
    if not v:
        raise HTTPException(404, "سند التحويل غير موجود")
    if v["status"] == "confirmed":
        raise HTTPException(400, "لا يمكن إلغاء سند مُؤكَّد — أنشئ سند مرتجع للتسوية")
    await pool.execute(
        "UPDATE transfer_vouchers SET status='cancelled', updated_at=NOW() WHERE id=$1::uuid",
        voucher_id
    )
    await _write_audit(pool, "cancel", "transfer_voucher", voucher_id, cancelled_by, {})
    return {"status": "cancelled"}


# ═══════════════════════════════════════════════════════════════════
#  RETURN VOUCHERS  (سندات المرتجع)
# ═══════════════════════════════════════════════════════════════════

@router.get("/return")
async def list_return_vouchers():
    pool = await get_pool()
    rows = await pool.fetch(
        """SELECT rv.*, tv.voucher_number AS original_voucher_number,
                  COUNT(ri.id)::int AS item_count
           FROM return_vouchers rv
           LEFT JOIN transfer_vouchers tv ON tv.id = rv.original_voucher_id
           LEFT JOIN return_voucher_items ri ON ri.voucher_id = rv.id
           GROUP BY rv.id, tv.voucher_number
           ORDER BY rv.created_at DESC"""
    )
    return [_row_to_dict(r) for r in rows]


@router.get("/return/{voucher_id}")
async def get_return_voucher(voucher_id: str):
    pool = await get_pool()
    voucher = await pool.fetchrow("SELECT * FROM return_vouchers WHERE id=$1::uuid", voucher_id)
    if not voucher:
        raise HTTPException(404, "سند المرتجع غير موجود")
    items = await pool.fetch(
        "SELECT * FROM return_voucher_items WHERE voucher_id=$1::uuid ORDER BY created_at",
        voucher_id
    )
    result = _row_to_dict(voucher)
    result["items"] = [_row_to_dict(i) for i in items]
    return result


@router.post("/return")
async def create_return_voucher(body: ReturnVoucherCreate):
    pool = await get_pool()
    # Validate original voucher is confirmed
    orig = await pool.fetchrow(
        "SELECT * FROM transfer_vouchers WHERE id=$1::uuid", body.original_voucher_id
    )
    if not orig:
        raise HTTPException(404, "سند التحويل الأصلي غير موجود")
    if orig["status"] != "confirmed":
        raise HTTPException(400, "يمكن إنشاء مرتجع فقط لسندات مُؤكَّدة")

    voucher_no = f"RET-{DateType.today().strftime('%Y%m%d')}-{await pool.fetchval('SELECT COUNT(*)+1 FROM return_vouchers WHERE created_at::date=CURRENT_DATE')}"

    vid = await pool.fetchval(
        """INSERT INTO return_vouchers
             (voucher_number, original_voucher_id, reason, created_by)
           VALUES ($1, $2::uuid, $3, $4) RETURNING id""",
        voucher_no, body.original_voucher_id, body.reason, body.created_by
    )

    for item in body.items:
        await pool.execute(
            """INSERT INTO return_voucher_items
                 (voucher_id, material_id, material_name, unit, quantity)
               VALUES ($1::uuid, $2, $3, $4, $5)""",
            str(vid), item.material_id, item.material_name, item.unit, item.requested_qty
        )

    await _write_audit(pool, "create", "return_voucher", str(vid), body.created_by or "admin",
                       {"original_voucher": orig["voucher_number"]})
    return {"id": str(vid), "voucher_number": voucher_no, "status": "draft"}


@router.post("/return/{voucher_id}/post")
async def post_return_voucher(voucher_id: str, performed_by: str = "admin"):
    pool = await get_pool()
    v = await pool.fetchrow("SELECT * FROM return_vouchers WHERE id=$1::uuid", voucher_id)
    if not v:
        raise HTTPException(404, "سند المرتجع غير موجود")
    if v["status"] == "posted":
        raise HTTPException(400, "السند مُرحَّل مسبقاً")

    items = await pool.fetch(
        "SELECT * FROM return_voucher_items WHERE voucher_id=$1::uuid", voucher_id
    )
    for item in items:
        mat_id = item["material_id"]
        if not mat_id:
            continue
        qty = float(item["quantity"])

        # Deduct from mixer
        mix_inv = await pool.fetchrow(
            "SELECT id, balance FROM inventory WHERE material_id=$1::uuid AND warehouse_type='mixer'",
            mat_id
        )
        mix_before = float(mix_inv["balance"]) if mix_inv else 0.0
        mix_after = max(0, mix_before - qty)
        if mix_inv:
            await pool.execute(
                "UPDATE inventory SET balance=$1, updated_at=NOW() WHERE id=$2",
                mix_after, mix_inv["id"]
            )
        await pool.execute(
            """INSERT INTO inventory_transactions
                 (material_id, warehouse_type, transaction_type, quantity,
                  balance_before, balance_after, transaction_ref, created_by, notes)
               VALUES ($1::uuid,'mixer','transfer_out',$2,$3,$4,$5,$6,$7)""",
            mat_id, qty, mix_before, mix_after,
            v["voucher_number"], performed_by, f"مرتجع للمخزن الرئيسي — {v['voucher_number']}"
        )

        # Add back to main
        main_inv = await pool.fetchrow(
            "SELECT id, balance FROM inventory WHERE material_id=$1::uuid AND warehouse_type='main'",
            mat_id
        )
        main_before = float(main_inv["balance"]) if main_inv else 0.0
        main_after = main_before + qty
        if main_inv:
            await pool.execute(
                "UPDATE inventory SET balance=$1, updated_at=NOW() WHERE id=$2",
                main_after, main_inv["id"]
            )
        else:
            await pool.execute(
                "INSERT INTO inventory (material_id, warehouse_type, balance) VALUES ($1::uuid,'main',$2)",
                mat_id, main_after
            )
        await pool.execute(
            """INSERT INTO inventory_transactions
                 (material_id, warehouse_type, transaction_type, quantity,
                  balance_before, balance_after, transaction_ref, created_by, notes)
               VALUES ($1::uuid,'main','transfer_in',$2,$3,$4,$5,$6,$7)""",
            mat_id, qty, main_before, main_after,
            v["voucher_number"], performed_by, f"مرتجع من الخلاط — {v['voucher_number']}"
        )

    await pool.execute(
        "UPDATE return_vouchers SET status='posted', updated_at=NOW() WHERE id=$1::uuid",
        voucher_id
    )
    await _write_audit(pool, "post", "return_voucher", voucher_id, performed_by,
                       {"items": len(items)})
    return {"status": "posted", "items_processed": len(items)}
