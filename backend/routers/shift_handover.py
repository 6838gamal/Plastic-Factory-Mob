"""
Shift Handover Router — نظام تسليم الورديات (Plan v3.0)

Flow:
1. GET /current-balance   — احسب الرصيد المتوقع (معادلة مقفلة)
                            Expected = Opening_From_Last_Shift + Received_From_Main - Batch_Inputs
2. POST /close            — مشرف الوردية يغلق ورديته
   • يحسب opening_stock من آخر تسليم مؤكَّد
   • يحسب العجز الكلي + الهدر المجهول
   • يضيف الرايش والتالف والهدر لمستودع السكراب
   • عجز > 0.5 كجم → يجمّد + مديونية عهدة + تنبيه أحمر فوري للمدير
3. POST /{id}/confirm     — مشرف الوردية القادمة يؤكد الاستلام (تُقفل نهائياً)
4. GET /                  — قائمة عمليات التسليم
5. GET /custody-debts     — مديونيات العهدة
6. PUT /custody-debts/{id}/resolve — سداد مديونية
"""
from datetime import date as DateType, datetime
from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import Optional
from database import get_pool

router = APIRouter(prefix="/api/shift-handover", tags=["shift-handover"])

DEFICIT_TOLERANCE_KG = 0.5  # تسامح نصف كيلو


# ─────────────────────────── Models ────────────────────────────

class ShiftHandoverClose(BaseModel):
    shift_name: str
    supervisor_name: str
    handover_date: Optional[DateType] = None
    # المخلفات التي تُضاف لمستودع السكراب
    flashing_kg: float = 0        # الرايش
    rejected_kg: float = 0        # التالف
    waste_kg: float = 0           # الهدر العام
    # الوزن الفعلي على الميزان (يُدخله المشرف)
    actual_stock_kg: float
    # استلام من الرئيسي (اختياري — يُحسب تلقائياً إذا لم يُدخل)
    received_from_main_kg: Optional[float] = None
    notes: Optional[str] = None


class ShiftHandoverConfirm(BaseModel):
    next_supervisor_name: str
    notes: Optional[str] = None


class CustodyDebtResolve(BaseModel):
    resolved_by: str
    notes: Optional[str] = None


# ─────────────────────────── Helpers ───────────────────────────

async def _get_scrap_material_id(pool) -> Optional[str]:
    row = await pool.fetchrow("SELECT value FROM settings WHERE key='scrap_material_id'")
    val = row["value"].strip() if row and row["value"] else ""
    return val if val else None


async def _add_to_scrap_warehouse(pool, material_id: str, qty_kg: float,
                                   ref: str, notes: str = "") -> float:
    """Add qty_kg to the scrap warehouse. Returns new balance."""
    inv = await pool.fetchrow(
        "SELECT balance FROM inventory WHERE material_id=$1 AND warehouse_type='scrap'",
        material_id,
    )
    balance_before = float(inv["balance"]) if inv else 0.0
    balance_after  = balance_before + qty_kg

    await pool.execute(
        """INSERT INTO inventory (id, material_id, warehouse_type, balance, updated_at)
           VALUES (gen_random_uuid(), $1, 'scrap', $2, NOW())
           ON CONFLICT (material_id, warehouse_type)
           DO UPDATE SET balance = inventory.balance + $2, updated_at = NOW()""",
        material_id, qty_kg,
    )
    await pool.execute(
        """INSERT INTO inventory_transactions
           (id, material_id, warehouse_type, transaction_type, quantity,
            transaction_ref, notes, balance_before, balance_after)
           VALUES (gen_random_uuid(), $1, 'scrap', 'in', $2, $3, $4, $5, $6)""",
        material_id, qty_kg, ref, notes, balance_before, balance_after,
    )
    return balance_after


async def _get_opening_stock(pool, before_date: DateType) -> tuple[float, Optional[str]]:
    """
    الرصيد الافتتاحي = الوزن الفعلي لآخر وردية مغلقة/مؤكَّدة/مجمَّدة قبل هذا التاريخ.
    الوردية المجمَّدة: يُفتح بالوزن الفعلي (لا بالمتوقع) لضمان ذمة نظيفة للمشرف الجديد.
    """
    row = await pool.fetchrow(
        """SELECT actual_stock_kg, shift_name, supervisor_name, handover_date
           FROM shift_handovers
           WHERE status IN ('confirmed', 'closed', 'frozen')
             AND handover_date <= $1
           ORDER BY handover_date DESC, created_at DESC
           LIMIT 1""",
        before_date,
    )
    if row and row["actual_stock_kg"] is not None:
        return float(row["actual_stock_kg"]), (
            f"وردية {row['shift_name']} — {row['supervisor_name']} ({row['handover_date']})"
        )
    return 0.0, None


async def _calculate_expected_balance(pool, handover_date: DateType,
                                       received_override: Optional[float] = None) -> dict:
    """
    المعادلة المقفلة (المستند قسم ثالثاً):
    Expected_Stock = (Opening_From_Last_Shift + Received_From_Main) - (Batch_Inputs)
    """
    day_start = datetime(handover_date.year, handover_date.month, handover_date.day)
    day_end   = datetime(handover_date.year, handover_date.month, handover_date.day, 23, 59, 59)

    # 1. الرصيد الافتتاحي من آخر وردية مغلقة
    opening_stock_kg, opening_ref = await _get_opening_stock(pool, handover_date)

    # 2. ما استُلم من الرئيسي اليوم (transactions in → mixer)
    received_auto = await pool.fetchval(
        """SELECT COALESCE(SUM(quantity), 0) FROM inventory_transactions
           WHERE warehouse_type='mixer' AND transaction_type='in'
             AND created_at BETWEEN $1 AND $2""",
        day_start, day_end,
    )
    received_from_main_kg = (
        received_override if received_override is not None else float(received_auto)
    )

    # 3. مجموع مدخلات الطبخات اليوم (transactions out ← mixer)
    consumed_today = await pool.fetchval(
        """SELECT COALESCE(SUM(quantity), 0) FROM inventory_transactions
           WHERE warehouse_type='mixer' AND transaction_type='out'
             AND created_at BETWEEN $1 AND $2""",
        day_start, day_end,
    )

    # 4. عدد الطبخات
    batch_count = await pool.fetchval(
        "SELECT COUNT(*) FROM batches WHERE date=$1", handover_date,
    )

    expected_stock_kg = round(opening_stock_kg + received_from_main_kg - float(consumed_today), 3)

    return {
        "expected_stock_kg": expected_stock_kg,
        "opening_stock_kg": round(opening_stock_kg, 3),
        "opening_ref": opening_ref,
        "received_from_main_kg": round(received_from_main_kg, 3),
        "total_batch_inputs_kg": round(float(consumed_today), 3),
        "batch_count_today": int(batch_count),
        "handover_date": str(handover_date),
    }


# ─────────────────────────── Routes ────────────────────────────

@router.get("/current-balance")
async def get_current_balance(
    handover_date: Optional[str] = Query(None),
):
    """احسب الرصيد المتوقع في الصالة للتحقق قبل الإغلاق."""
    pool = await get_pool()
    target_date = DateType.fromisoformat(handover_date) if handover_date else DateType.today()
    return await _calculate_expected_balance(pool, target_date)


@router.get("/custody-debts")
async def get_custody_debts(
    status: Optional[str] = Query(None),
    supervisor_name: Optional[str] = Query(None),
):
    pool = await get_pool()
    conditions = ["1=1"]
    params: list = []
    i = 1
    if status:
        conditions.append(f"cd.status=${i}"); params.append(status); i += 1
    if supervisor_name:
        conditions.append(f"cd.supervisor_name ILIKE ${i}"); params.append(f"%{supervisor_name}%"); i += 1

    rows = await pool.fetch(
        f"""SELECT cd.*, sh.shift_name as shift_name_ref,
                   sh.actual_stock_kg, sh.expected_stock_kg, sh.unknown_waste_kg
            FROM custody_debts cd
            JOIN shift_handovers sh ON sh.id = cd.handover_id
            WHERE {' AND '.join(conditions)}
            ORDER BY cd.created_at DESC""",
        *params,
    )
    return [dict(r) for r in rows]


@router.put("/custody-debts/{debt_id}/resolve")
async def resolve_custody_debt(debt_id: str, body: CustodyDebtResolve):
    pool = await get_pool()
    row = await pool.fetchrow(
        "SELECT id FROM custody_debts WHERE id=$1 AND status='pending'", debt_id
    )
    if not row:
        raise HTTPException(status_code=404, detail="المديونية غير موجودة أو مسددة مسبقاً")

    await pool.execute(
        """UPDATE custody_debts
           SET status='resolved', resolved_at=NOW(), resolved_by=$1, notes=COALESCE($2, notes)
           WHERE id=$3""",
        body.resolved_by, body.notes, debt_id,
    )
    return {"success": True, "message": "تم تسوية المديونية"}


@router.get("")
async def list_handovers(
    from_date: Optional[str] = Query(None, alias="from"),
    to_date: Optional[str] = Query(None, alias="to"),
    status: Optional[str] = Query(None),
    limit: int = Query(50),
):
    pool = await get_pool()
    conditions = ["1=1"]
    params: list = []
    i = 1
    if from_date:
        conditions.append(f"handover_date>=${i}"); params.append(from_date[:10]); i += 1
    if to_date:
        conditions.append(f"handover_date<=${i}"); params.append(to_date[:10]); i += 1
    if status:
        conditions.append(f"status=${i}"); params.append(status); i += 1

    rows = await pool.fetch(
        f"""SELECT * FROM shift_handovers
            WHERE {' AND '.join(conditions)}
            ORDER BY created_at DESC LIMIT {min(int(limit), 200)}""",
        *params,
    )
    return [dict(r) for r in rows]


@router.post("/close")
async def close_shift(body: ShiftHandoverClose):
    """
    إغلاق الوردية بالمعادلة المقفلة من المستند:

    Expected = Opening_From_Last_Shift + Received_From_Main - Batch_Inputs

    - الوردية المجمَّدة تُفتح للمشرف الجديد بالوزن الفعلي (لا بالمتوقع).
    - العجز > 0.5 كجم → تجميد + مديونية + تنبيه أحمر.
    - المخلفات (رايش + تالف + هدر) تُضاف فوراً لمستودع السكراب.
    - الهدر المجهول = عجز لا يُفسّره المخلفات المُعلَنة.
    """
    pool = await get_pool()
    target_date = body.handover_date or DateType.today()

    # ── 1. احسب الرصيد المتوقع بالمعادلة المقفلة ──────────────
    balance_info = await _calculate_expected_balance(
        pool, target_date,
        received_override=body.received_from_main_kg,
    )
    expected_kg     = balance_info["expected_stock_kg"]
    opening_kg      = balance_info["opening_stock_kg"]
    received_kg     = balance_info["received_from_main_kg"]
    consumed_kg     = balance_info["total_batch_inputs_kg"]
    actual_kg       = round(body.actual_stock_kg, 3)

    # ── 2. احسب العجز والمخلفات ────────────────────────────────
    scrap_total     = round(body.flashing_kg + body.rejected_kg + body.waste_kg, 3)
    deficit_kg      = round(max(expected_kg - actual_kg, 0.0), 3)
    # الهدر المجهول: العجز الذي لا يُفسّره المخلفات المُعلَنة
    unknown_waste_kg = round(max(deficit_kg - scrap_total, 0.0), 3)

    has_deficit = deficit_kg > DEFICIT_TOLERANCE_KG
    status      = "frozen" if has_deficit else "closed"

    # ── 3. أنشئ سجل تسليم الوردية ─────────────────────────────
    row = await pool.fetchrow(
        """INSERT INTO shift_handovers
           (id, shift_name, supervisor_name, handover_date,
            opening_stock_kg, received_from_main_kg, total_batch_inputs_kg,
            expected_stock_kg, actual_stock_kg,
            flashing_kg, rejected_kg, waste_kg, scrap_added_kg,
            deficit_kg, unknown_waste_kg, status, notes, frozen_at)
           VALUES (gen_random_uuid(), $1, $2, $3,
                   $4, $5, $6, $7, $8,
                   $9, $10, $11, $12,
                   $13, $14, $15, $16,
                   CASE WHEN $15='frozen' THEN NOW() ELSE NULL END)
           RETURNING *""",
        body.shift_name, body.supervisor_name, target_date,
        opening_kg, received_kg, consumed_kg, expected_kg, actual_kg,
        body.flashing_kg, body.rejected_kg, body.waste_kg, scrap_total,
        deficit_kg, unknown_waste_kg, status, body.notes,
    )
    handover_id = str(row["id"])

    # ── 4. أضف المخلفات لمستودع السكراب ──────────────────────
    scrap_material_id = await _get_scrap_material_id(pool)
    scrap_balance_after = 0.0
    if scrap_material_id and scrap_total > 0:
        scrap_balance_after = await _add_to_scrap_warehouse(
            pool, scrap_material_id, scrap_total,
            ref=f"handover_{handover_id}",
            notes=(
                f"مخلفات وردية {body.shift_name} — {body.supervisor_name}: "
                f"رايش {body.flashing_kg}، تالف {body.rejected_kg}، هدر {body.waste_kg} كجم"
            ),
        )

    # ── 5. إذا عجز → أنشئ مديونية + تنبيه فوري ─────────────
    if has_deficit:
        await pool.execute(
            """INSERT INTO custody_debts
               (id, handover_id, supervisor_name, shift_name,
                deficit_kg, handover_date, status, notes)
               VALUES (gen_random_uuid(), $1, $2, $3, $4, $5, 'pending', $6)""",
            handover_id, body.supervisor_name, body.shift_name,
            deficit_kg, target_date,
            f"عجز عهدة وردية {body.shift_name} بتاريخ {target_date}",
        )

        # تنبيه أحمر فوري للمدير
        await pool.execute(
            """INSERT INTO alerts
               (id, alert_type, severity, description, status)
               VALUES (gen_random_uuid(), 'custody_deficit', 'critical', $1, 'pending')""",
            (
                f"⚠️ عجز عهدة: المشرف {body.supervisor_name} — وردية {body.shift_name} "
                f"— العجز {deficit_kg:.3f} كجم"
                f" (متوقع {expected_kg:.3f}، فعلي {actual_kg:.3f})"
                + (f" — هدر مجهول {unknown_waste_kg:.3f} كجم" if unknown_waste_kg > 0 else "")
            ),
        )

    return {
        "id": handover_id,
        "status": status,
        "opening_stock_kg": opening_kg,
        "received_from_main_kg": received_kg,
        "total_batch_inputs_kg": consumed_kg,
        "expected_stock_kg": expected_kg,
        "actual_stock_kg": actual_kg,
        "scrap_added_kg": scrap_total,
        "deficit_kg": deficit_kg,
        "unknown_waste_kg": unknown_waste_kg,
        "scrap_balance_after_kg": round(scrap_balance_after, 3),
        "has_deficit": has_deficit,
        "message": (
            f"تم تجميد الوردية — عجز {deficit_kg:.3f} كجم مسجل بذمة {body.supervisor_name}"
            + (f" (هدر مجهول {unknown_waste_kg:.3f} كجم)" if unknown_waste_kg > 0 else "")
            if has_deficit else
            "تم إغلاق الوردية بنجاح — لا يوجد عجز"
        ),
    }


@router.post("/{handover_id}/confirm")
async def confirm_handover(handover_id: str, body: ShiftHandoverConfirm):
    """
    مشرف الوردية القادمة يؤكد الاستلام.
    - تُقفل الوردية السابقة نهائياً (confirmed) ولا يمكن تعديلها.
    - تبدأ ذمة المشرف الجديد من الوزن الفعلي (بما في حالة العجز).
    """
    pool = await get_pool()
    row = await pool.fetchrow("SELECT * FROM shift_handovers WHERE id=$1", handover_id)
    if not row:
        raise HTTPException(status_code=404, detail="عملية التسليم غير موجودة")
    if row["status"] == "confirmed":
        raise HTTPException(status_code=400, detail="تم تأكيد الاستلام مسبقاً")
    if row["status"] not in ("closed", "frozen"):
        raise HTTPException(status_code=400, detail="يجب إغلاق الوردية أولاً قبل التأكيد")

    await pool.execute(
        """UPDATE shift_handovers
           SET status='confirmed', next_supervisor_name=$1, confirmed_at=NOW(),
               notes=COALESCE($2, notes), updated_at=NOW()
           WHERE id=$3""",
        body.next_supervisor_name, body.notes, handover_id,
    )

    await pool.execute(
        """INSERT INTO audit_log
           (id, action, table_name, record_id, user_id, description)
           VALUES (gen_random_uuid(), 'confirm', 'shift_handovers', $1, $2, $3)""",
        handover_id, body.next_supervisor_name,
        f"تأكيد استلام عهدة وردية {row['shift_name']} من {row['supervisor_name']}",
    )

    return {
        "success": True,
        "message": (
            f"تم تأكيد استلام العهدة من {row['supervisor_name']} "
            f"إلى {body.next_supervisor_name}"
        ),
        "next_opening_stock_kg": float(row["actual_stock_kg"]) if row["actual_stock_kg"] else 0,
        "deficit_kg": float(row["deficit_kg"]),
    }


@router.get("/{handover_id}")
async def get_handover(handover_id: str):
    pool = await get_pool()
    row = await pool.fetchrow("SELECT * FROM shift_handovers WHERE id=$1", handover_id)
    if not row:
        raise HTTPException(status_code=404, detail="عملية التسليم غير موجودة")
    return dict(row)
