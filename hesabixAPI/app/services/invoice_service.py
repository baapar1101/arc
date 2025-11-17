from __future__ import annotations

from typing import Any, Dict, List, Optional, Tuple
from datetime import datetime, date, timedelta
from decimal import Decimal, ROUND_HALF_UP
import logging

from sqlalchemy.orm import Session
from sqlalchemy.orm.attributes import flag_modified
from sqlalchemy import and_, or_

from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.account import Account
from adapters.db.models.currency import Currency
from adapters.db.models.bank_account import BankAccount
from adapters.db.models.cash_register import CashRegister
from adapters.db.models.petty_cash import PettyCash
from adapters.db.models.check import Check
from adapters.db.models.user import User
from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.models.person import Person
from adapters.db.models.product import Product
from adapters.db.models.invoice_item_line import InvoiceItemLine
from app.core.responses import ApiError
from app.services.credit_service import get_business_credit_settings
import jdatetime
import io
import csv


logger = logging.getLogger(__name__)


# Supported invoice types (Document.document_type)
INVOICE_SALES = "invoice_sales"
INVOICE_SALES_RETURN = "invoice_sales_return"
INVOICE_PURCHASE = "invoice_purchase"
INVOICE_PURCHASE_RETURN = "invoice_purchase_return"
INVOICE_DIRECT_CONSUMPTION = "invoice_direct_consumption"
INVOICE_PRODUCTION = "invoice_production"
INVOICE_WASTE = "invoice_waste"

SUPPORTED_INVOICE_TYPES = {
    INVOICE_SALES,
    INVOICE_SALES_RETURN,
    INVOICE_PURCHASE,
    INVOICE_PURCHASE_RETURN,
    INVOICE_DIRECT_CONSUMPTION,
    INVOICE_PRODUCTION,
    INVOICE_WASTE,
}


# --- Inventory & Costing helpers ---
def _get_costing_method(data: Dict[str, Any]) -> str:
    try:
        method = ((data.get("extra_info") or {}).get("costing_method") or "average").strip().lower()
        if method not in ("average", "fifo"):
            method = "average"
        return method
    except Exception:
        return "average"


def _is_inventory_posting_enabled(data: Dict[str, Any]) -> bool:
    """خواندن فلگ ثبت اسناد انبار از extra_info. پیش‌فرض: فعال (True)."""
    try:
        extra = data.get("extra_info") or {}
        val = extra.get("post_inventory")
        if val is None:
            return True
        if isinstance(val, bool):
            return val
        if isinstance(val, (int, float)):
            return bool(val)
        s = str(val).strip().lower()
        return s not in ("false", "0", "no", "off")
    except Exception:
        return True


def _iter_product_movements(
    db: Session,
    business_id: int,
    product_ids: List[int],
    warehouse_ids: Optional[List[int]],
    up_to_date: date,
    exclude_document_id: Optional[int] = None,
):
    """
    بازگرداندن حرکات موجودی (ورودی/خروجی) از اسناد قطعی تا تاریخ مشخص برای مجموعه کالا/انبار.
    خروجی به ترتیب زمان/شناسه سند مرتب می‌شود.
    """
    if not product_ids:
        return []
    # فقط کالاهای با کنترل موجودی را لحاظ کن
    tracked_ids: List[int] = [
        int(pid)
        for pid, tracked in db.query(Product.id, Product.track_inventory).filter(
            Product.business_id == business_id,
            Product.id.in_(list({int(pid) for pid in product_ids})),
        ).all()
        if bool(tracked)
    ]
    if not tracked_ids:
        return []

    q = db.query(DocumentLine, Document).join(Document, Document.id == DocumentLine.document_id).filter(
        and_(
            Document.business_id == business_id,
            Document.is_proforma == False,  # noqa: E712
            Document.document_date <= up_to_date,
            DocumentLine.product_id.in_(tracked_ids),
        )
    )
    if exclude_document_id is not None:
        q = q.filter(Document.id != int(exclude_document_id))
    rows = q.order_by(Document.document_date.asc(), Document.id.asc(), DocumentLine.id.asc()).all()
    movements = []
    for line, doc in rows:
        info = line.extra_info or {}
        # اگر خط صراحتاً به عنوان عدم ثبت انبار علامت‌گذاری شده، از حرکت صرف‌نظر کن
        try:
            posted = info.get("inventory_posted")
            if posted is False:
                continue
        except Exception:
            pass
        movement = (info.get("movement") or None)
        wh_id = info.get("warehouse_id")
        if movement is None:
            # fallback از نوع سند اگر صراحتاً مشخص نشده باشد
            inv_move, _ = _movement_from_type(doc.document_type)
            movement = inv_move
        if warehouse_ids and wh_id is not None and int(wh_id) not in warehouse_ids:
            continue
        if movement not in ("in", "out"):
            continue
        qty = Decimal(str(line.quantity or 0))
        if qty <= 0:
            continue
        cost_price = None
        if info.get("cogs_amount") is not None and qty > 0 and movement == "out":
            try:
                cost_price = Decimal(str(info.get("cogs_amount"))) / qty
            except Exception:
                cost_price = None
        if cost_price is None and info.get("cost_price") is not None:
            cost_price = Decimal(str(info.get("cost_price")))
        if cost_price is None and info.get("unit_price") is not None:
            cost_price = Decimal(str(info.get("unit_price")))
        movements.append({
            "document_id": doc.id,
            "document_date": doc.document_date,
            "product_id": line.product_id,
            "warehouse_id": wh_id,
            "movement": movement,
            "quantity": qty,
            "cost_price": cost_price,
        })
    return movements


def _compute_available_stock(
    db: Session,
    business_id: int,
    product_id: int,
    warehouse_id: Optional[int],
    up_to_date: date,
    exclude_document_id: Optional[int] = None,
) -> Decimal:
    movements = _iter_product_movements(
        db,
        business_id,
        [product_id],
        [int(warehouse_id)] if warehouse_id is not None else None,
        up_to_date,
        exclude_document_id,
    )
    bal = Decimal(0)
    for mv in movements:
        if warehouse_id is not None and mv.get("warehouse_id") is not None and int(mv["warehouse_id"]) != int(warehouse_id):
            continue
        if mv["movement"] == "in":
            bal += mv["quantity"]
        elif mv["movement"] == "out":
            bal -= mv["quantity"]
    return bal


def _ensure_stock_sufficient(
    db: Session,
    business_id: int,
    document_date: date,
    outgoing_lines: List[Dict[str, Any]],
    exclude_document_id: Optional[int] = None,
) -> None:
    # تجمیع نیاز خروجی به تفکیک کالا/انبار
    required: Dict[Tuple[int, Optional[int]], Decimal] = {}
    for ln in outgoing_lines:
        pid = int(ln.get("product_id"))
        info = ln.get("extra_info") or {}
        wh_id = info.get("warehouse_id")
        qty = Decimal(str(ln.get("quantity", 0) or 0))
        key = (pid, int(wh_id) if wh_id is not None else None)
        required[key] = required.get(key, Decimal(0)) + qty

    # بررسی موجودی
    for (pid, wh_id), req in required.items():
        avail = _compute_available_stock(db, business_id, pid, wh_id, document_date, exclude_document_id)
        if avail < req:
            raise ApiError(
                "INSUFFICIENT_STOCK",
                f"موجودی کافی برای کالا {pid} در انبار {wh_id or '-'} موجود نیست. موجودی: {float(avail)}, موردنیاز: {float(req)}",
                http_status=409,
            )


def _calculate_fifo_cogs_for_outgoing(
    db: Session,
    business_id: int,
    document_date: date,
    outgoing_lines: List[Dict[str, Any]],
    exclude_document_id: Optional[int] = None,
) -> List[Decimal]:
    """
    محاسبه COGS بر اساس FIFO برای لیست خطوط خروجی؛ خروجی به همان ترتیب ورودی است.
    هر خط باید شامل product_id, quantity و extra_info.warehouse_id باشد.
    """
    # گردآوری حرکات تاریخی همه کالاهای موردنیاز
    product_ids = list({int(ln.get("product_id")) for ln in outgoing_lines})
    movements = _iter_product_movements(db, business_id, product_ids, None, document_date, exclude_document_id)
    # ساخت لایه‌های FIFO به تفکیک کالا/انبار
    from collections import defaultdict, deque
    layers: Dict[Tuple[int, Optional[int]], deque] = defaultdict(deque)
    for mv in movements:
        key = (int(mv["product_id"]), int(mv["warehouse_id"]) if mv.get("warehouse_id") is not None else None)
        if mv["movement"] == "in":
            cost_price = mv.get("cost_price") or Decimal(0)
            layers[key].append({"qty": Decimal(mv["quantity"]), "cost": Decimal(cost_price)})
        elif mv["movement"] == "out":
            remain = Decimal(mv["quantity"])
            while remain > 0 and layers[key]:
                top = layers[key][0]
                take = min(remain, top["qty"])
                top["qty"] -= take
                remain -= take
                if top["qty"] <= 0:
                    layers[key].popleft()
            # اگر خروجی تاریخی بیشتر از ورودی‌هاست، لایه‌ها منفی نشوند (کسری قبلی)
            if remain > 0:
                # اجازه کسری تاریخی: لایه منفی نمی‌سازیم، هزینه صفر می‌ماند
                pass

    # محاسبه هزینه برای خطوط فعلی
    results: List[Decimal] = []
    for ln in outgoing_lines:
        pid = int(ln.get("product_id"))
        qty = Decimal(str(ln.get("quantity", 0) or 0))
        info = ln.get("extra_info") or {}
        wh_id = int(info.get("warehouse_id")) if info.get("warehouse_id") is not None else None
        key = (pid, wh_id)
        cost_total = Decimal(0)
        remain = qty
        temp_stack = []
        # مصرف از لایه‌ها
        while remain > 0 and layers[key]:
            top = layers[key][0]
            take = min(remain, top["qty"])
            cost_total += take * Decimal(top["cost"] or 0)
            top["qty"] -= take
            remain -= take
            temp_stack.append((take, top))
            if top["qty"] <= 0:
                layers[key].popleft()
        if remain > 0:
            # اگر لایه کافی نبود، باقی‌مانده را با آخرین هزینه یا صفر حساب کنیم
            last_cost = Decimal(0)
            if temp_stack:
                last_cost = Decimal(temp_stack[-1][1]["cost"] or 0)
            cost_total += remain * last_cost
        results.append(cost_total)
    return results


def _parse_iso_date(dt: str | datetime | date) -> date:
    if isinstance(dt, date):
        return dt
    if isinstance(dt, datetime):
        return dt.date()

    dt_str = str(dt).strip()

    try:
        dt_str_clean = dt_str.replace('Z', '+00:00')
        parsed = datetime.fromisoformat(dt_str_clean)
        return parsed.date()
    except Exception:
        pass

    try:
        if len(dt_str) == 10 and dt_str.count('-') == 2:
            return datetime.strptime(dt_str, '%Y-%m-%d').date()
    except Exception:
        pass

    try:
        if len(dt_str) == 10 and dt_str.count('/') == 2:
            parts = dt_str.split('/')
            if len(parts) == 3:
                year, month, day = parts
                try:
                    year_int = int(year)
                    month_int = int(month)
                    day_int = int(day)
                    if year_int > 1500:
                        jalali_date = jdatetime.date(year_int, month_int, day_int)
                        gregorian_date = jalali_date.togregorian()
                        return gregorian_date
                    else:
                        return datetime.strptime(dt_str, '%Y/%m/%d').date()
                except (ValueError, jdatetime.JalaliDateError):
                    return datetime.strptime(dt_str, '%Y/%m/%d').date()
    except Exception:
        pass

    raise ApiError("INVALID_DATE", f"Invalid date format: {dt}", http_status=400)


def _get_current_fiscal_year(db: Session, business_id: int) -> FiscalYear:
    fiscal_year = db.query(FiscalYear).filter(
        and_(
            FiscalYear.business_id == business_id,
            FiscalYear.is_last == True,
        )
    ).first()
    if not fiscal_year:
        raise ApiError("NO_FISCAL_YEAR", "No active fiscal year found for this business", http_status=400)
    return fiscal_year


def _get_fixed_account_by_code(db: Session, account_code: str) -> Account:
    account = db.query(Account).filter(
        and_(
            Account.business_id == None,  # noqa: E711
            Account.code == str(account_code),
        )
    ).first()
    if not account:
        raise ApiError("ACCOUNT_NOT_FOUND", f"Account with code {account_code} not found", http_status=500)
    return account


def _get_person_control_account(db: Session, invoice_type: str | None = None) -> Account:
    # انتخاب حساب طرف‌شخص بر اساس نوع فاکتور
    # فروش/برگشت از فروش → دریافتنی ها 10401
    # خرید/برگشت از خرید → پرداختنی ها 20201 (پیش‌فرض)
    try:
        inv_type = (invoice_type or "").strip()
        if inv_type in {INVOICE_SALES, INVOICE_SALES_RETURN}:
            return _get_fixed_account_by_code(db, "10401")
        # سایر موارد (شامل خرید/برگشت از خرید)
        return _get_fixed_account_by_code(db, "20201")
    except Exception:
        # fallback امن
        return _get_fixed_account_by_code(db, "20201")


def _build_doc_code(prefix_base: str) -> str:
    today = datetime.now().date()
    prefix = f"{prefix_base}-{today.strftime('%Y%m%d')}"
    return prefix


def _extract_totals_from_lines(lines: List[Dict[str, Any]]) -> Dict[str, Decimal]:
    gross = Decimal(0)
    discount = Decimal(0)
    tax = Decimal(0)
    net = Decimal(0)

    for line in lines:
        info = line.get("extra_info") or {}
        qty = Decimal(str(line.get("quantity", 0) or 0))
        unit_price = Decimal(str(info.get("unit_price", 0) or 0))
        line_discount = Decimal(str(info.get("line_discount", 0) or 0))
        tax_amount = Decimal(str(info.get("tax_amount", 0) or 0))
        line_total = info.get("line_total")
        if line_total is None:
            line_total = (qty * unit_price) - line_discount + tax_amount
        else:
            line_total = Decimal(str(line_total))

        gross += (qty * unit_price)
        discount += line_discount
        tax += tax_amount
        net += line_total

    return {
        "gross": gross,
        "discount": discount,
        "tax": tax,
        "net": net,
    }


def _extract_cogs_total(lines: List[Dict[str, Any]]) -> Decimal:
    total = Decimal(0)
    for line in lines:
        info = line.get("extra_info") or {}
        # اگر خط برای انبار پست نشده، در COGS لحاظ نشود
        if info.get("inventory_posted") is False:
            continue
        qty = Decimal(str(line.get("quantity", 0) or 0))
        if info.get("cogs_amount") is not None:
            total += Decimal(str(info.get("cogs_amount")))
            continue
        cost_price = info.get("cost_price")
        if cost_price is not None:
            total += (qty * Decimal(str(cost_price)))
            continue
        # fallback: use unit_price as cost if nothing provided
        unit_price = info.get("unit_price")
        if unit_price is not None:
            total += (qty * Decimal(str(unit_price)))
    return total


def _resolve_accounts_for_invoice(db: Session, data: Dict[str, Any]) -> Dict[str, Account]:
    # امکان override از extra_info.account_codes
    overrides = ((data.get("extra_info") or {}).get("account_codes") or {})
    invoice_type = str(data.get("invoice_type", "")).strip()

    def code(name: str, default_code: str) -> str:
        return str(overrides.get(name) or default_code)

    return {
        # درآمد و برگشت فروش مطابق چارت سید:
        "revenue": _get_fixed_account_by_code(db, code("revenue", "50001")),
        "sales_return": _get_fixed_account_by_code(db, code("sales_return", "50002")),
        # تخفیفات فروش و خرید (به‌صورت مجزا)
        "sales_discount": _get_fixed_account_by_code(db, code("sales_discount", "50003")),
        "purchase_discount": _get_fixed_account_by_code(db, code("purchase_discount", "40003")),
        # موجودی، GRNI و ساخته‌شده (در نبود حساب مجزا)
        "inventory": _get_fixed_account_by_code(db, code("inventory", "10102")),
        "inventory_finished": _get_fixed_account_by_code(db, code("inventory_finished", "10102")),
        "grni": _get_fixed_account_by_code(db, code("grni", "30101")),
        # بهای تمام شده و VAT ها مطابق سید
        "cogs": _get_fixed_account_by_code(db, code("cogs", "40001")),
        "vat_out": _get_fixed_account_by_code(db, code("vat_out", "20101")),
        "vat_in": _get_fixed_account_by_code(db, code("vat_in", "10104")),
        # مصرف مستقیم و ضایعات
        "direct_consumption": _get_fixed_account_by_code(db, code("direct_consumption", "70406")),
        "wip": _get_fixed_account_by_code(db, code("wip", "10106")),
        "waste_expense": _get_fixed_account_by_code(db, code("waste_expense", "70407")),
        # حساب‌های فروش اقساطی
        "unearned_installment_profit": _get_fixed_account_by_code(db, code("unearned_installment_profit", "10405")),
        "installment_profit": _get_fixed_account_by_code(db, code("installment_profit", "60205")),
        # طرف‌شخص بر اساس نوع فاکتور
        "person": _get_person_control_account(db, invoice_type),
    }


def _calculate_seller_commission(
    db: Session,
    invoice_type: str,
    header_extra: Dict[str, Any],
    totals: Dict[str, Any],
) -> Tuple[int | None, Decimal]:
    """محاسبه پورسانت فروشنده/بازاریاب بر اساس تنظیمات شخص یا override در فاکتور.

    Returns: (seller_id, commission_amount)
    """
    try:
        ei = header_extra or {}
        seller_id_raw = ei.get("seller_id")
        seller_id: int | None = int(seller_id_raw) if seller_id_raw is not None else None
    except Exception:
        seller_id = None
    if not seller_id:
        return (None, Decimal(0))

    # مبنای محاسبه
    gross = Decimal(str((totals or {}).get("gross", 0)))
    discount = Decimal(str((totals or {}).get("discount", 0)))
    net = gross - discount

    # اگر در فاکتور override شده باشد، همان اعمال شود
    commission_cfg = ei.get("commission") if isinstance(ei.get("commission"), dict) else None
    if commission_cfg:
        value = Decimal(str(commission_cfg.get("value", 0))) if commission_cfg.get("value") is not None else Decimal(0)
        ctype = (commission_cfg.get("type") or "").strip().lower()
        if value <= 0:
            return (seller_id, Decimal(0))
        if ctype == "percentage":
            amount = (net * value) / Decimal(100)
            return (seller_id, amount)
        if ctype == "amount":
            return (seller_id, value)
        return (seller_id, Decimal(0))

    # در غیر اینصورت، از تنظیمات شخص استفاده می‌کنیم
    person = db.query(Person).filter(Person.id == seller_id).first()
    if not person:
        return (seller_id, Decimal(0))

    # اگر شخص اجازه‌ی ثبت پورسانت در سند فاکتور را نداده است، صفر برگردان
    try:
        if not bool(getattr(person, "commission_post_in_invoice_document", False)):
            return (seller_id, Decimal(0))
    except Exception:
        pass

    exclude_discounts = bool(getattr(person, "commission_exclude_discounts", False))
    base_amount = gross if exclude_discounts else net

    amount = Decimal(0)
    if invoice_type == INVOICE_SALES:
        percent = getattr(person, "commission_sale_percent", None)
        fixed = getattr(person, "commission_sales_amount", None)
    elif invoice_type == INVOICE_SALES_RETURN:
        percent = getattr(person, "commission_sales_return_percent", None)
        fixed = getattr(person, "commission_sales_return_amount", None)
    else:
        percent = None
        fixed = None

    if percent is not None:
        try:
            p = Decimal(str(percent))
            if p > 0:
                amount = (base_amount * p) / Decimal(100)
        except Exception:
            pass
    elif fixed is not None:
        try:
            f = Decimal(str(fixed))
            if f > 0:
                amount = f
        except Exception:
            pass

    return (seller_id, amount)


def _person_id_from_header(data: Dict[str, Any]) -> Optional[int]:
    try:
        ei = data.get("extra_info") or {}
        pid = ei.get("person_id")
        return int(pid) if pid is not None else None
    except Exception:
        return None


def _movement_from_type(invoice_type: str) -> Tuple[Optional[str], Optional[str]]:
    # Returns (movement_for_goods, reverse_movement) hints. Not strictly used for accounting.
    if invoice_type == INVOICE_SALES:
        return ("out", None)
    if invoice_type == INVOICE_SALES_RETURN:
        return ("in", None)
    if invoice_type == INVOICE_PURCHASE:
        return ("in", None)
    if invoice_type == INVOICE_PURCHASE_RETURN:
        return ("out", None)
    if invoice_type in (INVOICE_DIRECT_CONSUMPTION, INVOICE_WASTE):
        return ("out", None)
    if invoice_type == INVOICE_PRODUCTION:
        # production has both out (materials) and in (finished)
        return (None, None)
    return (None, None)


def _compute_installment_plan(
    total_with_tax: Decimal,
    header_extra: Dict[str, Any],
    document_date: date,
) -> Tuple[Optional[Dict[str, Any]], Decimal]:
    """
    ساخت طرح اقساط ساده (MVP) بر اساس ورودی فاکتور.
    ورودی مورد انتظار در extra_info.installment_plan:
      {
        "down_payment": number,
        "num_installments": int,
        "first_due_date": "YYYY-MM-DD",
        "period_days": int,              // اختیاری؛ پیش‌فرض 30
        "period": "monthly" | "days",    // اختیاری؛ اگر monthly باشد 30 روزه در نظر می‌گیرد
        "interest_total": number,        // اختیاری؛ اگر نبود از interest_rate محاسبه می‌شود
        "interest_rate": number,         // درصد کل دوره (نه سالانه) - اختیاری
        "method": "flat"                 // اختیاری
      }
    خروجی: (plan_dict | None, total_interest)
    """
    try:
        plan_input = (header_extra or {}).get("installment_plan")
        if not isinstance(plan_input, dict):
            return (None, Decimal(0))
        # اگر برنامه دستی ارسال شده باشد، همان را مبنا قرار بده
        provided_schedule = plan_input.get("schedule")
        if isinstance(provided_schedule, list) and len(provided_schedule) > 0:
            # نرمال‌سازی مقادیر و محاسبه جمع‌ها
            schedule: List[Dict[str, Any]] = []
            total_interest = Decimal(0)
            principal_total = Decimal(0)
            for idx, it in enumerate(provided_schedule):
                try:
                    due = _parse_iso_date(it.get("due_date") or document_date.isoformat())
                except Exception:
                    due = document_date
                principal = Decimal(str(it.get("principal", 0) or 0))
                interest = Decimal(str(it.get("interest", 0) or 0))
                total = Decimal(str(it.get("total", 0) or (principal + interest)))
                principal_total += principal
                total_interest += interest
                schedule.append({
                    "seq": int(it.get("seq") or (idx + 1)),
                    "due_date": due.isoformat(),
                    "principal": float(principal),
                    "interest": float(interest),
                    "total": float(total),
                    "status": it.get("status") or "pending",
                    "paid_amount": float(Decimal(str(it.get("paid_amount", 0) or 0))),
                })
            down_payment = Decimal(str(plan_input.get("down_payment", 0) or 0))
            # ولیدیشن پایه: جمع اصل اقساط + پیش‌پرداخت با مبلغ فاکتور (با مالیات) هم‌خوان باشد
            tolerance = Decimal("1")
            target = (total_with_tax - down_payment).max(Decimal(0))
            if (principal_total - target).copy_abs() > tolerance:
                raise ApiError(
                    "INVALID_INSTALLMENT_PLAN",
                    f"installment principal total ({float(principal_total)}) does not match invoice amount ({float(target)})",
                    http_status=422,
                )
            plan_dict: Dict[str, Any] = {
                "method": plan_input.get("method") or "flat",
                "down_payment": float(down_payment),
                "num_installments": len(schedule),
                "first_due_date": schedule[0]["due_date"],
                "period_days": int(plan_input.get("period_days") or 30),
                "principal_total": float(principal_total),
                "interest_total": float(total_interest),
                "schedule": schedule,
            }
            return (plan_dict, total_interest)
        num_installments = int(plan_input.get("num_installments") or 0)
        if num_installments <= 0:
            return (None, Decimal(0))
        down_payment = Decimal(str(plan_input.get("down_payment", 0) or 0))
        if down_payment < 0:
            down_payment = Decimal(0)
        principal_total = total_with_tax - down_payment
        if principal_total < 0:
            principal_total = Decimal(0)
        # محاسبه سود کل
        total_interest = plan_input.get("interest_total")
        if total_interest is not None:
            total_interest = Decimal(str(total_interest))
            if total_interest < 0:
                total_interest = Decimal(0)
        else:
            rate = Decimal(str(plan_input.get("interest_rate", 0) or 0))
            total_interest = (principal_total * rate) / Decimal(100) if rate > 0 else Decimal(0)
        # زمان‌بندی
        fd_raw = plan_input.get("first_due_date") or document_date.isoformat()
        first_due_date = _parse_iso_date(fd_raw)
        period_days = plan_input.get("period_days")
        if period_days is None:
            period = str(plan_input.get("period", "monthly")).strip().lower()
            period_days = 30 if period == "monthly" else 30
        try:
            period_days = int(period_days)
            if period_days <= 0:
                period_days = 30
        except Exception:
            period_days = 30
        # اقلام برنامه
        per_principal = (principal_total / num_installments) if num_installments > 0 else Decimal(0)
        per_interest = (total_interest / num_installments) if num_installments > 0 else Decimal(0)
        schedule: List[Dict[str, Any]] = []
        for i in range(num_installments):
            due = first_due_date + timedelta(days=period_days * i)
            item = {
                "seq": i + 1,
                "due_date": due.isoformat(),
                "principal": float(per_principal),
                "interest": float(per_interest),
                "total": float(per_principal + per_interest),
                "status": "pending",
                "paid_amount": 0.0,
            }
            schedule.append(item)
        plan_dict: Dict[str, Any] = {
            "method": plan_input.get("method") or "flat",
            "down_payment": float(down_payment),
            "num_installments": num_installments,
            "first_due_date": first_due_date.isoformat(),
            "period_days": period_days,
            "principal_total": float(principal_total),
            "interest_total": float(total_interest),
            "schedule": schedule,
        }
        return (plan_dict, total_interest)
    except Exception:
        # در صورت خطا، طرح نادیده گرفته می‌شود تا فاکتور قابل ثبت باشد
        return (None, Decimal(0))


def _build_invoice_code(db: Session, business_id: int, invoice_type: str) -> str:
    # INV-YYYYMMDD-NNNN (type agnostic); can be extended per-type later
    prefix = _build_doc_code("INV")
    last_doc = db.query(Document).filter(
        and_(
            Document.business_id == business_id,
            Document.code.like(f"{prefix}-%"),
        )
    ).order_by(Document.code.desc()).first()

    if last_doc:
        try:
            last_num = int(last_doc.code.split("-")[-1])
            next_num = last_num + 1
        except Exception:
            next_num = 1
    else:
        next_num = 1
    return f"{prefix}-{next_num:04d}"


def create_invoice(
    db: Session,
    business_id: int,
    user_id: int,
    data: Dict[str, Any],
) -> Dict[str, Any]:
    logger.info("=== شروع ایجاد فاکتور ===")

    invoice_type = str(data.get("invoice_type", "")).strip()
    if invoice_type not in SUPPORTED_INVOICE_TYPES:
        raise ApiError("INVALID_INVOICE_TYPE", "Unsupported invoice_type", http_status=400)

    document_date = _parse_iso_date(data.get("document_date", datetime.now()))
    currency_id = data.get("currency_id")
    if not currency_id:
        raise ApiError("CURRENCY_REQUIRED", "currency_id is required", http_status=400)
    currency = db.query(Currency).filter(Currency.id == int(currency_id)).first()
    if not currency:
        raise ApiError("CURRENCY_NOT_FOUND", "Currency not found", http_status=404)

    fiscal_year = _get_current_fiscal_year(db, business_id)

    lines_input: List[Dict[str, Any]] = list(data.get("lines") or [])
    if not isinstance(lines_input, list) or len(lines_input) == 0:
        raise ApiError("LINES_REQUIRED", "At least one line is required", http_status=400)

    # Basic person requirement for AR/AP invoices
    person_id = _person_id_from_header(data)
    if invoice_type in {INVOICE_SALES, INVOICE_SALES_RETURN, INVOICE_PURCHASE, INVOICE_PURCHASE_RETURN} and not person_id:
        raise ApiError("PERSON_REQUIRED", "person_id is required for this invoice type", http_status=400)

    # Compute totals from lines if not provided
    header_extra = data.get("extra_info") or {}
    totals = (header_extra.get("totals") or {}) if isinstance(header_extra, dict) else {}
    totals_missing = not all(k in totals for k in ("gross", "discount", "tax", "net"))
    if totals_missing:
        totals = _extract_totals_from_lines(lines_input)

    # Inventory posting is decoupled; no stock validation here
    post_inventory: bool = _is_inventory_posting_enabled(data)
    movement_hint, _ = _movement_from_type(invoice_type)

    # --- اعتبارسنجی اعتبار مشتری (قبل از ایجاد سند) ---
    is_proforma_req = bool(data.get("is_proforma", False))
    # فقط برای فروش (افزایش دریافتنی) و غیر پروفرما
    if not is_proforma_req and invoice_type == INVOICE_SALES and person_id:
        # تنظیمات شخص و کسب‌وکار
        from adapters.db.models.person import Person as _PersonModel
        from adapters.db.models.business import Business as _BusinessModel
        person_obj = db.query(_PersonModel).filter(_PersonModel.id == int(person_id)).first()
        business_obj = db.query(_BusinessModel).filter(_BusinessModel.id == int(business_id)).first()
        # تعیین محدودیت و فعال بودن بررسی
        check_enabled = None
        credit_limit_val = None
        if person_obj:
            check_enabled = getattr(person_obj, "credit_check_enabled", None)
            credit_limit_val = getattr(person_obj, "credit_limit", None)
        if (check_enabled is None) and business_obj:
            check_enabled = bool(getattr(business_obj, "check_credit_enabled_by_default", False))
        if (credit_limit_val is None) and business_obj:
            credit_limit_val = getattr(business_obj, "default_credit_limit", None)
        # اگر بررسی غیرفعال است یا سقف تعریف نشده، رد شو
        if check_enabled and (credit_limit_val is not None):
            # محاسبه بدهی فعلی
            from app.services.person_service import calculate_person_balance
            bal, _status = calculate_person_balance(db, int(person_id), fiscal_year_id=fiscal_year.id if fiscal_year else None)
            # اگر balance منفی باشد یعنی بدهکار
            current_debt = Decimal(str(0))
            try:
                if bal is not None:
                    bdec = Decimal(str(bal))
                    current_debt = (-bdec) if bdec < 0 else Decimal(0)
            except Exception:
                current_debt = Decimal(0)
            # مبلغ کل فاکتور (با مالیات) که AR را افزایش می‌دهد
            net_wo_tax = Decimal(str(totals.get("gross", 0))) - Decimal(str(totals.get("discount", 0)))
            tax_amt = Decimal(str(totals.get("tax", 0)))
            total_with_tax = net_wo_tax + tax_amt
            # پرداخت‌های همزمان ارسالی با فاکتور
            planned_paid = Decimal(0)
            try:
                for p in (data.get("payments") or []):
                    amt = Decimal(str(p.get("amount", 0) or 0))
                    if amt > 0:
                        planned_paid += amt
            except Exception:
                planned_paid = Decimal(0)
            invoice_effect = total_with_tax - planned_paid
            if invoice_effect < 0:
                invoice_effect = Decimal(0)
            new_debt = current_debt + invoice_effect
            limit_dec = Decimal(str(credit_limit_val))
            ignore_flag = bool((data.get("extra_info") or {}).get("ignore_credit_check", False))
            # --- کنترل سقف اعتبار ---
            if new_debt > limit_dec:
                if not ignore_flag:
                    # توقف با خطا
                    raise ApiError(
                        "CREDIT_LIMIT_EXCEEDED",
                        f"اعتبار مشتری کافی نیست. مانده فعلی: {float(current_debt):.2f}، اثر فاکتور: {float(invoice_effect):.2f}، سقف: {float(limit_dec):.2f}",
                        http_status=400
                    )
                else:
                    # اجازه ادامه؛ هشدار را در extra_info ذخیره خواهیم کرد (پس از ساخت سند)
                    header_extra = dict(header_extra or {})
                    warns = list((header_extra.get("warnings") or []))
                    warns.append({
                        "code": "CREDIT_LIMIT_EXCEEDED",
                        "message": "اعتبار مشتری از سقف عبور کرده است اما نادیده گرفته شد",
                        "current_debt": float(current_debt),
                        "invoice_effect": float(invoice_effect),
                        "new_debt": float(new_debt),
                        "limit": float(limit_dec),
                    })
                    header_extra["warnings"] = warns
                    data["extra_info"] = header_extra

            # --- کنترل بلاک خودکار بر اساس اقساط معوق ---
            auto_block_days = None
            credit_cfg = get_business_credit_settings(db, business_id)
            auto_block_days_raw = credit_cfg.get("auto_block_after_days")
            if auto_block_days_raw is not None:
                auto_block_days = int(auto_block_days_raw)
            if auto_block_days and auto_block_days > 0:
                inst_data = search_installments(
                    db=db,
                    business_id=business_id,
                    query={"person_id": int(person_id), "status": "overdue"},
                )
                max_overdue = 0
                for it in inst_data.get("items", []):
                    od = int(it.get("overdue_days") or 0)
                    if od > max_overdue:
                        max_overdue = od
                if max_overdue > auto_block_days:
                    if not ignore_flag:
                        raise ApiError(
                            "CREDIT_AUTO_BLOCKED",
                            f"به دلیل اقساط معوق بیش از {auto_block_days} روز، ثبت فاکتور جدید مجاز نیست.",
                            http_status=400,
                        )
                    else:
                        header_extra = dict(header_extra or {})
                        warns = list((header_extra.get("warnings") or []))
                        warns.append({
                            "code": "CREDIT_AUTO_BLOCKED_OVERRIDDEN",
                            "message": "به دلیل اقساط معوق، حساب به صورت خودکار باید مسدود می‌شد اما نادیده گرفته شد",
                            "auto_block_after_days": auto_block_days,
                            "max_overdue_days": max_overdue,
                        })
                        header_extra["warnings"] = warns
                        data["extra_info"] = header_extra

    # Resolve inventory tracking per product and annotate lines
    all_product_ids = [int(ln.get("product_id")) for ln in lines_input if ln.get("product_id")]
    track_map: Dict[int, bool] = {}
    if all_product_ids:
        for pid, tracked in db.query(Product.id, Product.track_inventory).filter(
            Product.business_id == business_id,
            Product.id.in_(all_product_ids),
        ).all():
            track_map[int(pid)] = bool(tracked)

    for ln in lines_input:
        pid = ln.get("product_id")
        if not pid:
            continue
        info = dict(ln.get("extra_info") or {})
        info["inventory_tracked"] = bool(track_map.get(int(pid), False))
        ln["extra_info"] = info
    # انبار از فاکتور جدا شده است؛ انتخاب انبار در فاکتور اجباری نیست


    # بدون کنترل کسری در مرحله فاکتور؛ کنترل در پست حواله انجام می‌شود

    # Costing method (only for tracked products)
    costing_method = _get_costing_method(data)
    # محاسبه COGS به پست حواله منتقل می‌شود

    # Create document
    doc_code = _build_invoice_code(db, business_id, invoice_type)

    # Enrich extra_info
    new_extra_info = dict(header_extra)
    new_extra_info["totals"] = {
        "gross": float(Decimal(str(totals["gross"]))),
        "discount": float(Decimal(str(totals["discount"]))),
        "tax": float(Decimal(str(totals["tax"]))),
        "net": float(Decimal(str(totals["net"]))),
    }

    document = Document(
        business_id=business_id,
        fiscal_year_id=fiscal_year.id,
        code=doc_code,
        document_type=invoice_type,
        document_date=document_date,
        currency_id=int(currency_id),
        created_by_user_id=user_id,
        registered_at=datetime.utcnow(),
        is_proforma=bool(data.get("is_proforma", False)),
        description=data.get("description"),
        extra_info=new_extra_info,
    )
    db.add(document)
    db.flush()

    # ذخیره اقلام فاکتور در جدول مجزا (invoice_item_lines)
    for line in lines_input:
        product_id = line.get("product_id")
        qty = Decimal(str(line.get("quantity", 0) or 0))
        if not product_id or qty <= 0:
            raise ApiError("INVALID_LINE", "line.product_id and positive quantity are required", http_status=400)
        extra_info = dict(line.get("extra_info") or {})
        extra_info.pop("inventory_posted", None)
        db.add(InvoiceItemLine(
            document_id=document.id,
            product_id=int(product_id),
            quantity=qty,
            description=line.get("description"),
            extra_info=extra_info,
        ))

    # Accounting lines for finalized invoices (بدون خطوط COGS/Inventory؛ به حواله موکول شد)
    if not document.is_proforma:
        accounts = _resolve_accounts_for_invoice(db, data)

        gross = Decimal(str(totals["gross"]))
        discount = Decimal(str(totals["discount"]))
        net = gross - discount
        tax = Decimal(str(totals["tax"]))
        total_with_tax = net + tax

        # COGS به پست حواله منتقل شد

        # Sales
        if invoice_type == INVOICE_SALES:
            # AR (person) Dr, Revenue Cr, VAT out Cr, COGS Dr, Inventory Cr (optional)
            if person_id:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["person"].id,
                    person_id=person_id,
                    debit=total_with_tax,
                    credit=Decimal(0),
                    description=data.get("description"),
                    extra_info={"side": "person", "person_id": person_id},
                ))
            # فروش قبل از تخفیف
            if gross > 0:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["revenue"].id,
                    debit=Decimal(0),
                    credit=gross,
                    description="فروش کالا (قبل از تخفیف)",
                ))
            # تخفیفات فروش به‌صورت مستقل
            if discount > 0:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["sales_discount"].id,
                    debit=discount,
                    credit=Decimal(0),
                    description="تخفیفات فروش",
                ))
            if tax > 0:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["vat_out"].id,
                    debit=Decimal(0),
                    credit=tax,
                    description="مالیات بر ارزش افزوده خروجی",
                ))
            # COGS/Inventory در پست حواله ثبت خواهد شد
            # --- فروش اقساطی (ثبت سود تحقق‌نیافته و افزایش AR) ---
            plan_dict, total_interest = _compute_installment_plan(total_with_tax, header_extra, document_date)
            if plan_dict:
                # در همه حالات طرح روی سند ذخیره می‌شود
                extra = document.extra_info or {}
                extra["installment_plan"] = plan_dict
                document.extra_info = extra
                # اگر سود اقساط مثبت باشد، ثبت‌های حسابداری سود اعمال می‌شود
                if total_interest > 0:
                    # افزایش بدهکار دریافتنی به میزان سود کل اقساط
                    if person_id:
                        db.add(DocumentLine(
                            document_id=document.id,
                            account_id=accounts["person"].id,
                            person_id=person_id,
                            debit=total_interest,
                            credit=Decimal(0),
                            description="سود کل اقساط افزوده به دریافتنی",
                            extra_info={"installment": True, "side": "person", "person_id": person_id},
                        ))
                    # بستانکار سود تحقق‌نیافته
                    db.add(DocumentLine(
                        document_id=document.id,
                        account_id=accounts["unearned_installment_profit"].id,
                        debit=Decimal(0),
                        credit=total_interest,
                        description="سود تحقق‌نیافته فروش اقساطی",
                        extra_info={"installment": True},
                    ))


        # Sales Return
        elif invoice_type == INVOICE_SALES_RETURN:
            if person_id:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["person"].id,
                    person_id=person_id,
                    debit=Decimal(0),
                    credit=total_with_tax,
                    description=data.get("description"),
                    extra_info={"side": "person", "person_id": person_id},
                ))
            # برگشت از فروش قبل از تخفیف
            if gross > 0:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["sales_return"].id,
                    debit=gross,
                    credit=Decimal(0),
                    description="برگشت از فروش (قبل از تخفیف)",
                ))
            # برگشت تخفیفات فروش
            if discount > 0:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["sales_discount"].id,
                    debit=Decimal(0),
                    credit=discount,
                    description="برگشت تخفیفات فروش",
                ))
            if tax > 0:
                # تعدیل VAT خروجی فاکتور فروش
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["vat_out"].id,
                    debit=tax,
                    credit=Decimal(0),
                    description="تعدیل VAT برگشت از فروش",
                ))
            # ورود موجودی/تعدیل COGS در پست حواله انجام می‌شود

        # Purchase
        elif invoice_type == INVOICE_PURCHASE:
            # ثبت GRNI بابت خرید به مبلغ ناخالص (قبل از تخفیف)
            if gross > 0:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["grni"].id,
                    debit=gross,
                    credit=Decimal(0),
                    description="ثبت GRNI خرید (مبلغ ناخالص)",
                ))
            # تخفیفات خرید به صورت جداگانه
            if discount > 0:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["purchase_discount"].id,
                    debit=Decimal(0),
                    credit=discount,
                    description="تخفیفات خرید",
                ))
            # VAT ورودی
            if tax > 0:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["vat_in"].id,
                    debit=tax,
                    credit=Decimal(0),
                    description="مالیات بر ارزش افزوده ورودی",
                ))
            # طرف‌شخص (حساب‌های پرداختنی) به مبلغ خالص با مالیات
            if person_id:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["person"].id,
                    person_id=person_id,
                    debit=Decimal(0),
                    credit=total_with_tax,
                    description=data.get("description"),
                    extra_info={"side": "person", "person_id": person_id},
                ))

        # Purchase Return
        elif invoice_type == INVOICE_PURCHASE_RETURN:
            # ثبت برگشت GRNI به مبلغ ناخالص (قبل از تخفیف)
            if gross > 0:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["grni"].id,
                    debit=Decimal(0),
                    credit=gross,
                    description="برگشت GRNI بابت برگشت خرید (مبلغ ناخالص)",
                ))
            # برگشت تخفیفات خرید
            if discount > 0:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["purchase_discount"].id,
                    debit=discount,
                    credit=Decimal(0),
                    description="برگشت تخفیفات خرید",
                ))
            # تعدیل VAT ورودی
            if tax > 0:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["vat_in"].id,
                    debit=Decimal(0),
                    credit=tax,
                    description="تعدیل VAT ورودی برگشت خرید",
                ))
            # طرف‌شخص (کاهش بدهی)
            if person_id:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["person"].id,
                    person_id=person_id,
                    debit=total_with_tax,
                    credit=Decimal(0),
                    description=data.get("description"),
                    extra_info={"side": "person", "person_id": person_id},
                ))

        # Direct consumption / Waste / Production
        elif invoice_type in (INVOICE_DIRECT_CONSUMPTION, INVOICE_WASTE, INVOICE_PRODUCTION):
            # برای این انواع، ثبت‌های موجودی و بهای تمام‌شده فقط در پست حواله انبار انجام می‌شود
            pass

        # --- پورسانت فروشنده/بازاریاب (تکمیلی پس از ثبت خطوط انواع فاکتور) ---
        if invoice_type in (INVOICE_SALES, INVOICE_SALES_RETURN):
            seller_id, commission_amount = _calculate_seller_commission(db, invoice_type, header_extra, totals)
            if seller_id and commission_amount > 0:
                commission_expense = _get_fixed_account_by_code(db, "70702")
                seller_payable = _get_fixed_account_by_code(db, "20201")
                if invoice_type == INVOICE_SALES:
                    db.add(DocumentLine(
                        document_id=document.id,
                        account_id=commission_expense.id,
                        debit=commission_amount,
                        credit=Decimal(0),
                        description="هزینه پورسانت فروش",
                    ))
                    db.add(DocumentLine(
                        document_id=document.id,
                        account_id=seller_payable.id,
                        person_id=int(seller_id),
                        debit=Decimal(0),
                        credit=commission_amount,
                        description="بابت پورسانت فروشنده/بازاریاب",
                        extra_info={"seller_id": int(seller_id)},
                    ))
                else:
                    db.add(DocumentLine(
                        document_id=document.id,
                        account_id=seller_payable.id,
                        person_id=int(seller_id),
                        debit=commission_amount,
                        credit=Decimal(0),
                        description="تعدیل پورسانت فروشنده بابت برگشت از فروش",
                        extra_info={"seller_id": int(seller_id)},
                    ))
                    db.add(DocumentLine(
                        document_id=document.id,
                        account_id=commission_expense.id,
                        debit=Decimal(0),
                        credit=commission_amount,
                        description="تعدیل هزینه پورسانت",
                    ))

    # Persist invoice first
    db.commit()
    db.refresh(document)

    # Optional: create receipt/payment document(s)
    payment_docs: List[int] = []
    payments = data.get("payments") or []
    if payments and isinstance(payments, list):
        try:
            # Only when person is present
            if person_id:
                from app.services.receipt_payment_service import create_receipt_payment

                # Aggregate amounts into one receipt/payment with multiple account_lines
                account_lines: List[Dict[str, Any]] = []
                total_amount = Decimal(0)
                # Validate currency of payment accounts vs invoice currency
                invoice_currency_id = int(currency_id)
                for p in payments:
                    amount = Decimal(str(p.get("amount", 0) or 0))
                    if amount <= 0:
                        continue
                    total_amount += amount
                    # پشتیبانی از هر دو فیلد 'type' و 'transaction_type'
                    ttype = (p.get("transaction_type") or p.get("type") or "").strip().lower()
                    # Currency match checks for money accounts
                    if ttype in ("bank", "cash_register", "petty_cash", "check"):
                        if ttype == "bank":
                            ref_id = p.get("bank_id")
                            if ref_id:
                                acct = db.query(BankAccount).filter(BankAccount.id == int(ref_id)).first()
                                if not acct:
                                    raise ApiError("PAYMENT_ACCOUNT_NOT_FOUND", "Bank account not found", http_status=404)
                                if int(acct.currency_id) != invoice_currency_id:
                                    raise ApiError("PAYMENT_CURRENCY_MISMATCH", "Currency of bank account does not match invoice currency", http_status=400)
                        elif ttype == "cash_register":
                            ref_id = p.get("cash_register_id")
                            if ref_id:
                                acct = db.query(CashRegister).filter(CashRegister.id == int(ref_id)).first()
                                if not acct:
                                    raise ApiError("PAYMENT_ACCOUNT_NOT_FOUND", "Cash register not found", http_status=404)
                                if int(acct.currency_id) != invoice_currency_id:
                                    raise ApiError("PAYMENT_CURRENCY_MISMATCH", "Currency of cash register does not match invoice currency", http_status=400)
                        elif ttype == "petty_cash":
                            ref_id = p.get("petty_cash_id")
                            if ref_id:
                                acct = db.query(PettyCash).filter(PettyCash.id == int(ref_id)).first()
                                if not acct:
                                    raise ApiError("PAYMENT_ACCOUNT_NOT_FOUND", "Petty cash not found", http_status=404)
                                if int(acct.currency_id) != invoice_currency_id:
                                    raise ApiError("PAYMENT_CURRENCY_MISMATCH", "Currency of petty cash does not match invoice currency", http_status=400)
                        elif ttype == "check":
                            ref_id = p.get("check_id")
                            if ref_id:
                                chk = db.query(Check).filter(Check.id == int(ref_id)).first()
                                if not chk:
                                    raise ApiError("PAYMENT_ACCOUNT_NOT_FOUND", "Check not found", http_status=404)
                                if int(chk.currency_id) != invoice_currency_id:
                                    raise ApiError("PAYMENT_CURRENCY_MISMATCH", "Currency of check does not match invoice currency", http_status=400)

                    # Build account line entry including ids/names for linking
                    # استفاده از 'type' یا 'transaction_type' (فرانت‌اند 'type' می‌فرستد)
                    transaction_type_value = p.get("transaction_type") or p.get("type")
                    logger.info(f"Payment item: type={p.get('type')}, transaction_type={p.get('transaction_type')}, resolved={transaction_type_value}")
                    account_line: Dict[str, Any] = {
                        "transaction_type": transaction_type_value,
                        "amount": float(amount),
                        "description": p.get("description"),
                        "transaction_date": p.get("transaction_date"),
                        "commission": p.get("commission"),
                    }
                    logger.info(f"Created account_line: {account_line}")
                    # pass through reference ids/names if provided
                    for key in ("bank_id", "bank_name", "cash_register_id", "cash_register_name", "petty_cash_id", "petty_cash_name", "check_id", "check_number", "person_id", "account_id"):
                        if p.get(key) is not None:
                            account_line[key] = p.get(key)
                    account_lines.append(account_line)

                if total_amount > 0 and account_lines:
                    is_receipt = invoice_type in {INVOICE_SALES, INVOICE_PURCHASE_RETURN}
                    # نوع حساب طرف‌شخص برای سند دریافت/پرداخت متناسب با نوع فاکتور:
                    # فروش و برگشت از فروش → دریافتنی‌ها (10401)
                    # خرید و برگشت از خرید → پرداختنی‌ها (20201)
                    person_is_receivable = invoice_type in {INVOICE_SALES, INVOICE_SALES_RETURN}
                    rp_data = {
                        "document_type": "receipt" if is_receipt else "payment",
                        "document_date": document.document_date.isoformat(),
                        "currency_id": document.currency_id,
                        "description": f"تسویه مرتبط با فاکتور {document.code}",
                        "person_lines": [{
                            "person_id": person_id,
                            "amount": float(total_amount),
                            "description": f"طرف حساب فاکتور {document.code}",
                        }],
                        "account_lines": account_lines,
                        "extra_info": {
                            "source": "invoice",
                            "invoice_id": document.id,
                            # هدایت نوع حساب طرف‌شخص در سند دریافت/پرداخت
                            "person_is_receivable": person_is_receivable,
                        },
                    }
                    rp_doc = create_receipt_payment(db=db, business_id=business_id, user_id=user_id, data=rp_data)
                    logger.info(f"create_receipt_payment returned: type={type(rp_doc)}, value={rp_doc}")
                    if isinstance(rp_doc, dict) and rp_doc.get("id"):
                        rp_id = int(rp_doc["id"])
                        payment_docs.append(rp_id)
                        logger.info(f"Added receipt/payment document ID {rp_id} to payment_docs. Current list: {payment_docs}")
                    else:
                        logger.warning(f"create_receipt_payment did not return valid document with id. Returned: {rp_doc}")
        except Exception as ex:
            logger.exception("could not create receipt/payment for invoice: %s", ex)
            # حتی در صورت خطا، اگر payment_docs پر شده باشد، لینک را ذخیره کن
            if payment_docs:
                logger.info(f"Exception occurred but payment_docs has {len(payment_docs)} items. Will still save links.")

    # Save links back to invoice
    if payment_docs:
        logger.info(f"Saving links to invoice {document.id}. payment_docs: {payment_docs}")
        # اطمینان از اینکه document در session است
        db.add(document)
        # دریافت extra_info فعلی (ممکن است dict یا None باشد)
        extra = dict(document.extra_info) if document.extra_info else {}
        # ایجاد یا به‌روزرسانی links
        links = dict(extra.get("links", {}))
        links["receipt_payment_document_ids"] = payment_docs
        extra["links"] = links
        # به‌روزرسانی extra_info
        document.extra_info = extra
        # علامت‌گذاری برای به‌روزرسانی (برای JSON fields در SQLAlchemy)
        flag_modified(document, "extra_info")
        try:
            db.commit()
            db.refresh(document)
            logger.info(f"Successfully saved links to invoice {document.id}. Updated extra_info: {document.extra_info}")
        except Exception as ex:
            logger.exception(f"Failed to save links to invoice {document.id}: {ex}")
            db.rollback()
            raise
    else:
        logger.warning(f"No payment_docs to save for invoice {document.id}. payments data: {payments}")

    # ایجاد حواله انبار draft در صورت نیاز و جدا از فاکتور
    try:
        if bool(data.get("extra_info", {}).get("post_inventory", True)):
            from app.services.warehouse_service import create_from_invoice
            created_wh_ids: List[int] = []
            if invoice_type == INVOICE_PRODUCTION:
                out_lines = [ln for ln in lines_input if (ln.get("extra_info") or {}).get("movement") == "out"]
                in_lines = [ln for ln in lines_input if (ln.get("extra_info") or {}).get("movement") == "in"]
                if out_lines:
                    wh_issue = create_from_invoice(db, business_id, document, out_lines, "issue", user_id)
                    created_wh_ids.append(int(wh_issue.id))
                if in_lines:
                    wh_receipt = create_from_invoice(db, business_id, document, in_lines, "receipt", user_id)
                    created_wh_ids.append(int(wh_receipt.id))
            else:
                if invoice_type in {INVOICE_SALES, INVOICE_PURCHASE_RETURN, INVOICE_WASTE, INVOICE_DIRECT_CONSUMPTION}:
                    wh_type = "issue"
                elif invoice_type in {INVOICE_PURCHASE, INVOICE_SALES_RETURN}:
                    wh_type = "receipt"
                else:
                    wh_type = "issue"
                wh = create_from_invoice(db, business_id, document, lines_input, wh_type, user_id)
                created_wh_ids.append(int(wh.id))

            if created_wh_ids:
                # ذخیره لینک حواله‌ها در extra_info.links
                extra = document.extra_info or {}
                links = dict((extra.get("links") or {}))
                links["warehouse_document_ids"] = created_wh_ids
                extra["links"] = links
                document.extra_info = extra
                db.commit()
    except Exception:
        # عدم موفقیت در ساخت حواله نباید مانع بازگشت فاکتور شود
        db.rollback()

    return invoice_document_to_dict(db, document)


def update_invoice(
    db: Session,
    document_id: int,
    user_id: int,
    data: Dict[str, Any],
) -> Dict[str, Any]:
    document = db.query(Document).filter(Document.id == document_id).first()
    if not document or document.document_type not in SUPPORTED_INVOICE_TYPES:
        raise ApiError("DOCUMENT_NOT_FOUND", "Invoice document not found", http_status=404)

    # Only editable in current fiscal year
    try:
        fiscal_year = db.query(FiscalYear).filter(FiscalYear.id == document.fiscal_year_id).first()
        if fiscal_year is not None and getattr(fiscal_year, "is_last", False) is not True:
            raise ApiError("FISCAL_YEAR_LOCKED", "سند متعلق به سال مالی جاری نیست و قابل ویرایش نمی‌باشد", http_status=409)
    except ApiError:
        raise
    except Exception:
        pass

    # Update header
    document_date = _parse_iso_date(data.get("document_date", document.document_date))
    currency_id = data.get("currency_id", document.currency_id)
    if not currency_id:
        raise ApiError("CURRENCY_REQUIRED", "currency_id is required", http_status=400)
    currency = db.query(Currency).filter(Currency.id == int(currency_id)).first()
    if not currency:
        raise ApiError("CURRENCY_NOT_FOUND", "Currency not found", http_status=404)

    document.document_date = document_date
    document.currency_id = int(currency_id)
    # به‌روزرسانی وضعیت پیش‌فاکتور
    if "is_proforma" in data:
        document.is_proforma = bool(data.get("is_proforma", False))
    if isinstance(data.get("extra_info"), dict) or data.get("extra_info") is None:
        # preserve links if present
        new_extra = data.get("extra_info") or {}
        old_extra = document.extra_info or {}
        links = old_extra.get("links")
        if links and "links" not in new_extra:
            new_extra["links"] = links
        document.extra_info = new_extra
    if isinstance(data.get("description"), str) or data.get("description") is None:
        if data.get("description") is not None:
            document.description = data.get("description")

    # Recreate lines: حذف سطرهای حسابداری و اقلام فاکتور و بازایجاد
    db.query(DocumentLine).filter(DocumentLine.document_id == document.id).delete(synchronize_session=False)
    db.query(InvoiceItemLine).filter(InvoiceItemLine.document_id == document.id).delete(synchronize_session=False)

    lines_input: List[Dict[str, Any]] = list(data.get("lines") or [])
    if not lines_input:
        raise ApiError("LINES_REQUIRED", "At least one line is required", http_status=400)

    # Inventory decoupled from invoices
    inv_type = document.document_type
    movement_hint, _ = _movement_from_type(inv_type)

    # Resolve and annotate inventory tracking for all lines
    all_product_ids = [int(ln.get("product_id")) for ln in lines_input if ln.get("product_id")]
    track_map: Dict[int, bool] = {}
    if all_product_ids:
        for pid, tracked in db.query(Product.id, Product.track_inventory).filter(
            Product.business_id == document.business_id,
            Product.id.in_(all_product_ids),
        ).all():
            track_map[int(pid)] = bool(tracked)
    for ln in lines_input:
        pid = ln.get("product_id")
        if not pid:
            continue
        info = dict(ln.get("extra_info") or {})
        info["inventory_tracked"] = bool(track_map.get(int(pid), False))
        ln["extra_info"] = info
    # انتخاب انبار در مرحله فاکتور الزامی نیست

    header_for_costing = data if data else {"extra_info": document.extra_info}
    post_inventory_update: bool = _is_inventory_posting_enabled(header_for_costing)

    for line in lines_input:
        product_id = line.get("product_id")
        qty = Decimal(str(line.get("quantity", 0) or 0))
        if not product_id or qty <= 0:
            raise ApiError("INVALID_LINE", "line.product_id and positive quantity are required", http_status=400)
        extra_info = dict(line.get("extra_info") or {})
        db.add(InvoiceItemLine(
            document_id=document.id,
            product_id=int(product_id),
            quantity=qty,
            description=line.get("description"),
            extra_info=extra_info,
        ))

    # Accounting lines if finalized
    if not document.is_proforma:
        header_for_accounts: Dict[str, Any] = {"invoice_type": inv_type, **(data or {"extra_info": document.extra_info})}
        accounts = _resolve_accounts_for_invoice(db, header_for_accounts)
        header_extra = data.get("extra_info") or document.extra_info or {}
        totals = (header_extra.get("totals") or {})
        if not totals:
            totals = _extract_totals_from_lines(lines_input)
        gross = Decimal(str(totals.get("gross", 0)))
        discount = Decimal(str(totals.get("discount", 0)))
        net = gross - discount
        tax = Decimal(str(totals.get("tax", 0)))
        total_with_tax = net + tax
        person_id = _person_id_from_header({"extra_info": header_extra})
        # inventory/COGS handled in warehouse posting

        if inv_type == INVOICE_SALES:
            if person_id:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["person"].id,
                    person_id=person_id,
                    debit=total_with_tax,
                    credit=Decimal(0),
                    description=document.description,
                ))
            # فروش قبل از تخفیف
            if gross > 0:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["revenue"].id,
                    debit=Decimal(0),
                    credit=gross,
                    description="فروش کالا (قبل از تخفیف)",
                ))
            # تخفیفات فروش
            if discount > 0:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["sales_discount"].id,
                    debit=discount,
                    credit=Decimal(0),
                    description="تخفیفات فروش",
                ))
            if tax > 0:
                db.add(DocumentLine(document_id=document.id, account_id=accounts["vat_out"].id, debit=Decimal(0), credit=tax, description="مالیات خروجی"))
            # COGS/Inventory by warehouse posting
            # فروش اقساطی (ثبت سود تحقق‌نیافته و افزایش AR)
            plan_dict, total_interest = _compute_installment_plan(total_with_tax, header_extra, document.document_date)
            if plan_dict:
                # merge extra_info to include plan (preserve links)
                ex_old = document.extra_info or {}
                ex_new = dict(ex_old)
                ex_new["installment_plan"] = plan_dict
                document.extra_info = ex_new
                if total_interest > 0:
                    if person_id:
                        db.add(DocumentLine(
                            document_id=document.id,
                            account_id=accounts["person"].id,
                            person_id=person_id,
                            debit=total_interest,
                            credit=Decimal(0),
                            description="سود کل اقساط افزوده به دریافتنی",
                            extra_info={"installment": True, "side": "person", "person_id": person_id},
                        ))
                    db.add(DocumentLine(
                        document_id=document.id,
                        account_id=accounts["unearned_installment_profit"].id,
                        debit=Decimal(0),
                        credit=total_interest,
                        description="سود تحقق‌نیافته فروش اقساطی",
                        extra_info={"installment": True},
                    ))
        elif inv_type == INVOICE_SALES_RETURN:
            if person_id:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["person"].id,
                    person_id=person_id,
                    debit=Decimal(0),
                    credit=total_with_tax,
                    description=document.description,
                ))
            # برگشت از فروش قبل از تخفیف
            if gross > 0:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["sales_return"].id,
                    debit=gross,
                    credit=Decimal(0),
                    description="برگشت از فروش (قبل از تخفیف)",
                ))
            # برگشت تخفیفات فروش
            if discount > 0:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["sales_discount"].id,
                    debit=Decimal(0),
                    credit=discount,
                    description="برگشت تخفیفات فروش",
                ))
            if tax > 0:
                # تعدیل VAT خروجی فاکتور فروش
                db.add(DocumentLine(document_id=document.id, account_id=accounts["vat_out"].id, debit=tax, credit=Decimal(0), description="تعدیل VAT برگشت از فروش"))
            # Inventory/COGS handled in warehouse posting
        elif inv_type == INVOICE_PURCHASE:
            # ثبت GRNI به مبلغ ناخالص
            if gross > 0:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["grni"].id,
                    debit=gross,
                    credit=Decimal(0),
                    description="ثبت GRNI خرید (مبلغ ناخالص)",
                ))
            # تخفیفات خرید
            if discount > 0:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["purchase_discount"].id,
                    debit=Decimal(0),
                    credit=discount,
                    description="تخفیفات خرید",
                ))
            # VAT ورودی
            if tax > 0:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["vat_in"].id,
                    debit=tax,
                    credit=Decimal(0),
                    description="مالیات ورودی",
                ))
            # طرف‌شخص
            if person_id:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["person"].id,
                    person_id=person_id,
                    debit=Decimal(0),
                    credit=total_with_tax,
                    description=document.description,
                ))
        elif inv_type == INVOICE_PURCHASE_RETURN:
            # برگشت GRNI به مبلغ ناخالص
            if gross > 0:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["grni"].id,
                    debit=Decimal(0),
                    credit=gross,
                    description="برگشت GRNI بابت برگشت خرید (مبلغ ناخالص)",
                ))
            # برگشت تخفیفات خرید
            if discount > 0:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["purchase_discount"].id,
                    debit=discount,
                    credit=Decimal(0),
                    description="برگشت تخفیفات خرید",
                ))
            # تعدیل VAT ورودی
            if tax > 0:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["vat_in"].id,
                    debit=Decimal(0),
                    credit=tax,
                    description="تعدیل VAT ورودی",
                ))
            # طرف‌شخص (کاهش بدهی)
            if person_id:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["person"].id,
                    person_id=person_id,
                    debit=total_with_tax,
                    credit=Decimal(0),
                    description=document.description,
                ))
        elif inv_type == INVOICE_DIRECT_CONSUMPTION:
            # Expense/Inventory in warehouse posting
            pass
        elif inv_type == INVOICE_WASTE:
            # Expense/Inventory in warehouse posting
            pass
        elif inv_type == INVOICE_PRODUCTION:
            # WIP/Inventory in warehouse posting
            pass

        # --- پورسانت فروشنده/بازاریاب (به‌صورت تکمیلی) ---
        if inv_type in (INVOICE_SALES, INVOICE_SALES_RETURN):
            seller_id, commission_amount = _calculate_seller_commission(db, inv_type, header_extra, totals)
            if seller_id and commission_amount > 0:
                commission_expense = _get_fixed_account_by_code(db, "70702")
                seller_payable = _get_fixed_account_by_code(db, "20201")
                if inv_type == INVOICE_SALES:
                    db.add(DocumentLine(
                        document_id=document.id,
                        account_id=commission_expense.id,
                        debit=commission_amount,
                        credit=Decimal(0),
                        description="هزینه پورسانت فروش",
                    ))
                    db.add(DocumentLine(
                        document_id=document.id,
                        account_id=seller_payable.id,
                        person_id=int(seller_id),
                        debit=Decimal(0),
                        credit=commission_amount,
                        description="بابت پورسانت فروشنده/بازاریاب",
                        extra_info={"seller_id": int(seller_id)},
                    ))
                else:
                    db.add(DocumentLine(
                        document_id=document.id,
                        account_id=seller_payable.id,
                        person_id=int(seller_id),
                        debit=commission_amount,
                        credit=Decimal(0),
                        description="تعدیل پورسانت فروشنده بابت برگشت از فروش",
                        extra_info={"seller_id": int(seller_id)},
                    ))
                    db.add(DocumentLine(
                        document_id=document.id,
                        account_id=commission_expense.id,
                        debit=Decimal(0),
                        credit=commission_amount,
                        description="تعدیل هزینه پورسانت",
                    ))

    # پردازش تراکنش‌های پرداخت (مشابه create_invoice)
    payment_docs: List[int] = []
    payments = data.get("payments")
    if payments and isinstance(payments, list) and not document.is_proforma:
        try:
            # دریافت person_id از extra_info
            header_extra = data.get("extra_info") or document.extra_info or {}
            person_id = _person_id_from_header({"extra_info": header_extra})
            
            # Only when person is present
            if person_id:
                from app.services.receipt_payment_service import create_receipt_payment, delete_receipt_payment
                
                # حذف سندهای دریافت/پرداخت قدیمی مرتبط با این فاکتور
                old_links = (document.extra_info or {}).get("links", {})
                old_receipt_payment_ids = old_links.get("receipt_payment_document_ids") or []
                for old_rp_id in old_receipt_payment_ids:
                    try:
                        delete_receipt_payment(db, old_rp_id)
                        logger.info(f"Deleted old receipt/payment document {old_rp_id} for invoice {document.id}")
                    except Exception as ex:
                        logger.warning(f"Could not delete old receipt/payment document {old_rp_id}: {ex}")
                
                # ایجاد سندهای جدید (مشابه create_invoice)
                account_lines: List[Dict[str, Any]] = []
                total_amount = Decimal(0)
                invoice_currency_id = int(document.currency_id)
                
                for p in payments:
                    amount = Decimal(str(p.get("amount", 0) or 0))
                    if amount <= 0:
                        continue
                    total_amount += amount
                    ttype = (p.get("transaction_type") or p.get("type") or "").strip().lower()
                    
                    # Currency match checks
                    if ttype in ("bank", "cash_register", "petty_cash", "check"):
                        if ttype == "bank":
                            ref_id = p.get("bank_id")
                            if ref_id:
                                acct = db.query(BankAccount).filter(BankAccount.id == int(ref_id)).first()
                                if not acct:
                                    raise ApiError("PAYMENT_ACCOUNT_NOT_FOUND", "Bank account not found", http_status=404)
                                if int(acct.currency_id) != invoice_currency_id:
                                    raise ApiError("PAYMENT_CURRENCY_MISMATCH", "Currency of bank account does not match invoice currency", http_status=400)
                        elif ttype == "cash_register":
                            ref_id = p.get("cash_register_id")
                            if ref_id:
                                acct = db.query(CashRegister).filter(CashRegister.id == int(ref_id)).first()
                                if not acct:
                                    raise ApiError("PAYMENT_ACCOUNT_NOT_FOUND", "Cash register not found", http_status=404)
                                if int(acct.currency_id) != invoice_currency_id:
                                    raise ApiError("PAYMENT_CURRENCY_MISMATCH", "Currency of cash register does not match invoice currency", http_status=400)
                        elif ttype == "petty_cash":
                            ref_id = p.get("petty_cash_id")
                            if ref_id:
                                acct = db.query(PettyCash).filter(PettyCash.id == int(ref_id)).first()
                                if not acct:
                                    raise ApiError("PAYMENT_ACCOUNT_NOT_FOUND", "Petty cash not found", http_status=404)
                                if int(acct.currency_id) != invoice_currency_id:
                                    raise ApiError("PAYMENT_CURRENCY_MISMATCH", "Currency of petty cash does not match invoice currency", http_status=400)
                        elif ttype == "check":
                            ref_id = p.get("check_id")
                            if ref_id:
                                chk = db.query(Check).filter(Check.id == int(ref_id)).first()
                                if not chk:
                                    raise ApiError("PAYMENT_ACCOUNT_NOT_FOUND", "Check not found", http_status=404)
                                if int(chk.currency_id) != invoice_currency_id:
                                    raise ApiError("PAYMENT_CURRENCY_MISMATCH", "Currency of check does not match invoice currency", http_status=400)
                    
                    transaction_type_value = p.get("transaction_type") or p.get("type")
                    account_line: Dict[str, Any] = {
                        "transaction_type": transaction_type_value,
                        "amount": float(amount),
                        "description": p.get("description"),
                        "transaction_date": p.get("transaction_date"),
                        "commission": p.get("commission"),
                    }
                    for key in ("bank_id", "bank_name", "cash_register_id", "cash_register_name", "petty_cash_id", "petty_cash_name", "check_id", "check_number", "person_id", "account_id"):
                        if p.get(key) is not None:
                            account_line[key] = p.get(key)
                    account_lines.append(account_line)
                
                if total_amount > 0 and account_lines:
                    is_receipt = inv_type in {INVOICE_SALES, INVOICE_PURCHASE_RETURN}
                    person_is_receivable = inv_type in {INVOICE_SALES, INVOICE_SALES_RETURN}
                    rp_data = {
                        "document_type": "receipt" if is_receipt else "payment",
                        "document_date": document.document_date.isoformat(),
                        "currency_id": document.currency_id,
                        "description": f"تسویه مرتبط با فاکتور {document.code}",
                        "person_lines": [{
                            "person_id": person_id,
                            "amount": float(total_amount),
                            "description": f"طرف حساب فاکتور {document.code}",
                        }],
                        "account_lines": account_lines,
                        "extra_info": {
                            "source": "invoice",
                            "invoice_id": document.id,
                            "person_is_receivable": person_is_receivable,
                        },
                    }
                    rp_doc = create_receipt_payment(db=db, business_id=document.business_id, user_id=user_id, data=rp_data)
                    if isinstance(rp_doc, dict) and rp_doc.get("id"):
                        rp_id = int(rp_doc["id"])
                        payment_docs.append(rp_id)
                        logger.info(f"Created receipt/payment document {rp_id} for invoice {document.id}")
                
                # به‌روزرسانی لینک‌ها در extra_info
                if payment_docs:
                    extra = dict(document.extra_info) if document.extra_info else {}
                    links = dict(extra.get("links", {}))
                    links["receipt_payment_document_ids"] = payment_docs
                    extra["links"] = links
                    document.extra_info = extra
                    from sqlalchemy.orm.attributes import flag_modified
                    flag_modified(document, "extra_info")
        except Exception as ex:
            logger.exception("could not update receipt/payment for invoice: %s", ex)
            # حتی در صورت خطا، ادامه بده

    db.commit()
    db.refresh(document)
    return invoice_document_to_dict(db, document)


def delete_invoice(db: Session, document_id: int) -> bool:
    """
    حذف یک فاکتور
    
    Args:
        db: جلسه دیتابیس
        document_id: شناسه سند فاکتور
    
    Returns:
        True در صورت موفقیت، False در غیر این صورت
    
    Raises:
        ApiError: در صورت عدم وجود سند، عدم امکان حذف، یا خطاهای دیگر
    """
    try:
        document = db.query(Document).filter(Document.id == document_id).first()
        if not document:
            raise ApiError("DOCUMENT_NOT_FOUND", "Invoice document not found", http_status=404)
        
        # بررسی نوع سند
        if document.document_type not in SUPPORTED_INVOICE_TYPES:
            raise ApiError("INVALID_DOCUMENT_TYPE", "Document is not an invoice", http_status=400)
        
        # 1) جلوگیری از حذف در سال مالی غیر جاری
        try:
            fiscal_year = db.query(FiscalYear).filter(FiscalYear.id == document.fiscal_year_id).first()
            if fiscal_year is not None and getattr(fiscal_year, "is_last", False) is not True:
                raise ApiError(
                    "FISCAL_YEAR_LOCKED",
                    "سند متعلق به سال مالی جاری نیست و قابل حذف نمی‌باشد",
                    http_status=409,
                )
        except ApiError:
            raise
        except Exception:
            pass
        
        # 2) جلوگیری از حذف در صورت قفل بودن سند
        try:
            locked_flags = []
            if isinstance(document.extra_info, dict):
                locked_flags.append(bool(document.extra_info.get("locked")))
                locked_flags.append(bool(document.extra_info.get("is_locked")))
            if isinstance(document.developer_settings, dict):
                locked_flags.append(bool(document.developer_settings.get("locked")))
                locked_flags.append(bool(document.developer_settings.get("is_locked")))
            if any(locked_flags):
                raise ApiError(
                    "DOCUMENT_LOCKED",
                    "این سند قفل است و قابل حذف نمی‌باشد",
                    http_status=409,
                )
        except ApiError:
            raise
        except Exception:
            pass
        
        # 3) بررسی حواله‌های انبار مرتبط و اسناد دریافت/پرداخت
        try:
            extra_info = document.extra_info or {}
            links = extra_info.get("links") or {}
            
            # بررسی حواله‌های انبار
            warehouse_document_ids = links.get("warehouse_document_ids") or []
            if warehouse_document_ids:
                # بررسی اینکه آیا حواله‌ها قطعی شده‌اند یا نه
                try:
                    from adapters.db.models.warehouse_document import WarehouseDocument
                    warehouse_docs = db.query(WarehouseDocument).filter(
                        WarehouseDocument.id.in_(warehouse_document_ids)
                    ).all()
                    finalized_warehouses = [wd for wd in warehouse_docs if getattr(wd, "status", None) == "finalized"]
                    if finalized_warehouses:
                        raise ApiError(
                            "WAREHOUSE_DOCUMENTS_EXIST",
                            "این فاکتور دارای حواله‌های قطعی شده است و قابل حذف نمی‌باشد",
                            http_status=409,
                        )
                except ImportError:
                    # اگر مدل WarehouseDocument وجود نداشت، از بررسی صرف‌نظر می‌کنیم
                    pass
            
            # 4) بررسی اسناد دریافت/پرداخت مرتبط
            receipt_payment_document_ids = links.get("receipt_payment_document_ids") or []
            if receipt_payment_document_ids:
                related_docs = db.query(Document).filter(
                    Document.id.in_(receipt_payment_document_ids)
                ).all()
                if related_docs:
                    # اگر اسناد دریافت/پرداخت وجود دارند، نمی‌توان فاکتور را حذف کرد
                    raise ApiError(
                        "RECEIPT_PAYMENT_DOCUMENTS_EXIST",
                        "این فاکتور دارای اسناد دریافت/پرداخت مرتبط است و قابل حذف نمی‌باشد",
                        http_status=409,
                    )
        except ApiError:
            raise
        except Exception:
            pass
        
        # حذف خطوط سند حسابداری
        db.query(DocumentLine).filter(DocumentLine.document_id == document_id).delete(synchronize_session=False)
        
        # حذف اقلام فاکتور
        db.query(InvoiceItemLine).filter(InvoiceItemLine.document_id == document_id).delete(synchronize_session=False)
        
        # حذف سند
        db.delete(document)
        db.commit()
        
        return True
    except ApiError:
        db.rollback()
        raise
    except Exception as e:
        logger.error(f"Error deleting invoice document {document_id}: {e}")
        db.rollback()
        raise ApiError("DELETE_FAILED", f"Failed to delete invoice: {str(e)}", http_status=500)


def invoice_document_to_dict(db: Session, document: Document) -> Dict[str, Any]:
    # اقلام فاکتور از جدول مجزا خوانده می‌شوند
    item_rows = db.query(InvoiceItemLine).filter(InvoiceItemLine.document_id == document.id).all()
    product_lines: List[Dict[str, Any]] = []
    for it in item_rows:
        product = db.query(Product).filter(Product.id == it.product_id).first()
        product_lines.append({
            "id": it.id,
            "product_id": it.product_id,
            "product_name": getattr(product, "name", None),
            "quantity": float(it.quantity) if it.quantity else None,
            "description": it.description,
            "extra_info": it.extra_info,
        })

    # سطرهای حسابداری از document_lines خوانده می‌شوند
    acc_rows = db.query(DocumentLine).filter(DocumentLine.document_id == document.id, DocumentLine.account_id != None).all()  # noqa: E711
    account_lines: List[Dict[str, Any]] = []
    for line in acc_rows:
        account = db.query(Account).filter(Account.id == line.account_id).first()
        account_lines.append({
            "id": line.id,
            "account_id": line.account_id,
            "account_name": getattr(account, "name", None),
            "account_code": getattr(account, "code", None),
            "debit": float(line.debit),
            "credit": float(line.credit),
            "person_id": line.person_id,
            "description": line.description,
            "extra_info": line.extra_info,
        })

    created_by = db.query(User).filter(User.id == document.created_by_user_id).first()
    created_by_name = f"{getattr(created_by, 'first_name', '')} {getattr(created_by, 'last_name', '')}".strip() if created_by else None
    currency = db.query(Currency).filter(Currency.id == document.currency_id).first()

    return {
        "id": document.id,
        "code": document.code,
        "business_id": document.business_id,
        "document_type": document.document_type,
        "document_date": document.document_date.isoformat(),
        "registered_at": document.registered_at.isoformat(),
        "currency_id": document.currency_id,
        "currency_code": getattr(currency, "code", None),
        "created_by_user_id": document.created_by_user_id,
        "created_by_name": created_by_name,
        "is_proforma": document.is_proforma,
        "description": document.description,
        "extra_info": document.extra_info,
        "product_lines": product_lines,
        "account_lines": account_lines,
        "created_at": document.created_at.isoformat(),
        "updated_at": document.updated_at.isoformat(),
    }


def get_invoice_installment_plan(
    db: Session,
    business_id: int,
    invoice_id: int,
) -> Dict[str, Any]:
    """
    بازگرداندن طرح اقساط ذخیره شده برای فاکتور فروش به‌همراه محاسبات مانده هر قسط.
    """
    document = db.query(Document).filter(
        and_(
            Document.id == int(invoice_id),
            Document.business_id == int(business_id),
        )
    ).first()
    if not document:
        raise ApiError("DOCUMENT_NOT_FOUND", "Invoice document not found", http_status=404)
    if document.document_type not in {INVOICE_SALES, INVOICE_SALES_RETURN, INVOICE_PURCHASE, INVOICE_PURCHASE_RETURN}:
        # فقط برای فاکتورهای طرف شخص معنی‌دار است؛ ولی اگر طرح موجود باشد، برمی‌گردانیم
        pass
    extra = document.extra_info or {}
    plan = extra.get("installment_plan")
    if not isinstance(plan, dict):
        raise ApiError("INSTALLMENT_PLAN_NOT_FOUND", "Installment plan not found on document", http_status=404)
    schedule = plan.get("schedule") or []
    # محاسبات مانده هر قسط
    enriched_schedule: List[Dict[str, Any]] = []
    total_principal = Decimal(str(plan.get("principal_total", 0) or 0))
    total_interest = Decimal(str(plan.get("interest_total", 0) or 0))
    sum_remaining = Decimal(0)
    for item in schedule:
        try:
            total = Decimal(str(item.get("total", 0) or 0))
            paid = Decimal(str(item.get("paid_amount", 0) or 0))
        except Exception:
            total, paid = Decimal(0), Decimal(0)
        remaining = max(total - paid, Decimal(0))
        sum_remaining += remaining
        new_item = dict(item)
        new_item["remaining"] = float(remaining)
        # اطمینان از وجود status - اگر موجود نباشد، محاسبه کن
        if "status" not in new_item or not new_item.get("status"):
            if total > 0 and paid >= total:
                new_item["status"] = "paid"
            elif paid > 0:
                new_item["status"] = "partial"
            else:
                new_item["status"] = "pending"
        enriched_schedule.append(new_item)
    return {
        "invoice_id": int(document.id),
        "invoice_code": document.code,
        "document_date": document.document_date.isoformat(),
        "currency_id": int(document.currency_id),
        "currency_code": getattr(document.currency, "code", None),
        "person_id": (extra or {}).get("person_id"),
        "plan": {
            **plan,
            "schedule": enriched_schedule,
            "principal_total": float(total_principal),
            "interest_total": float(total_interest),
            "remaining_total": float(sum_remaining),
        },
    }


def search_installments(
    db: Session,
    business_id: int,
    query: Dict[str, Any],
) -> Dict[str, Any]:
    """
    جستجوی اقساط به تفکیک ردیف‌های برنامه اقساط در فاکتورهای فروش.
    فیلترها:
      - fiscal_year_id (اختیاری): بازه سررسید در سال مالی انتخابی
      - due_from, due_to (اختیاری): بازه تاریخ سررسید
      - status: pending|partial|paid|overdue
      - person_id: فیلتر بر اساس شخص
      - invoice_id: فاکتور خاص
      - take/skip: صفحه‌بندی ساده
    """
    # تاریخ امروز برای تشخیص overdue
    today = datetime.utcnow().date()

    # ورودی‌ها
    fiscal_year_id = query.get("fiscal_year_id")
    due_from = query.get("due_from")
    due_to = query.get("due_to")
    status_filter = (query.get("status") or "").strip().lower()
    person_id_filter = query.get("person_id")
    invoice_id_filter = query.get("invoice_id")
    try:
        take = int(query.get("take", 200))
    except Exception:
        take = 200
    try:
        skip = int(query.get("skip", 0))
    except Exception:
        skip = 0

    fy_start: date | None = None
    fy_end: date | None = None
    if fiscal_year_id:
        fy = db.query(FiscalYear).filter(
            and_(
                FiscalYear.id == int(fiscal_year_id),
                FiscalYear.business_id == int(business_id),
            )
        ).first()
        if fy:
            fy_start = getattr(fy, "start_date", None)
            fy_end = getattr(fy, "end_date", None)

    def _parse_date(v: Any) -> date | None:
        if not v:
            return None
        try:
            return _parse_iso_date(v)
        except Exception:
            return None

    due_from_dt = _parse_date(due_from)
    due_to_dt = _parse_date(due_to)

    # تنظیمات اعتبار برای محاسبه جریمه دیرکرد
    late_fee_rate_dec: Decimal | None = None
    grace_days_val: int | None = None
    try:
        credit_cfg = get_business_credit_settings(db, business_id)
        if credit_cfg.get("late_fee_rate") is not None:
            late_fee_rate_dec = Decimal(str(credit_cfg.get("late_fee_rate")))
        gd = credit_cfg.get("grace_days")
        if gd is not None:
            try:
                grace_days_val = int(gd)
            except Exception:
                grace_days_val = None
    except Exception:
        late_fee_rate_dec = None
        grace_days_val = None

    # اسناد فروش دارای طرح اقساط
    docs_q = db.query(Document).filter(
        and_(
            Document.business_id == business_id,
            Document.document_type == INVOICE_SALES,
            Document.is_proforma == False,  # noqa: E712
        )
    )
    if invoice_id_filter:
        try:
            docs_q = docs_q.filter(Document.id == int(invoice_id_filter))
        except Exception:
            pass

    docs = docs_q.order_by(Document.id.desc()).all()

    items: List[Dict[str, Any]] = []
    for doc in docs:
        extra = doc.extra_info or {}
        plan = extra.get("installment_plan") if isinstance(extra, dict) else None
        if not isinstance(plan, dict):
            continue
        if person_id_filter is not None:
            try:
                if int(extra.get("person_id")) != int(person_id_filter):
                    continue
            except Exception:
                continue
        # تلاش برای استخراج نام شخص برای نمایش در گزارش
        person_name = None
        try:
            if extra.get("person_id") is not None:
                pid = int(extra.get("person_id"))
                person = db.query(Person).filter(
                    and_(Person.id == pid, Person.business_id == int(business_id))
                ).first()
                if person is not None:
                    person_name = getattr(person, "name", None)
        except Exception:
            person_name = None
        schedule = plan.get("schedule") or []
        for it in schedule:
            # استخراج تاریخ سررسید
            try:
                due = _parse_iso_date(it.get("due_date"))
            except Exception:
                continue
            # فیلتر سال مالی (بر اساس تاریخ سررسید)
            if fy_start and due < fy_start:
                continue
            if fy_end and due > fy_end:
                continue
            # فیلترهای تاریخ
            if due_from_dt and due < due_from_dt:
                continue
            if due_to_dt and due > due_to_dt:
                continue
            # محاسبات
            principal = Decimal(str(it.get("principal", 0) or 0))
            interest = Decimal(str(it.get("interest", 0) or 0))
            total = Decimal(str(it.get("total", 0) or 0))
            paid = Decimal(str(it.get("paid_amount", 0) or 0))
            remaining = max(total - paid, Decimal(0))
            # وضعیت
            if remaining <= Decimal("0.01"):
                st = "paid"
            elif paid > 0:
                st = "partial"
            else:
                st = "pending"
            if due < today and st != "paid":
                st = "overdue"
            # فیلتر وضعیت
            if status_filter and st != status_filter:
                continue
            overdue_days = 0
            if st == "overdue":
                try:
                    overdue_days = max((today - due).days, 0)
                except Exception:
                    overdue_days = 0
            # جریمه دیرکرد ساده بر اساس تنظیمات کسب‌وکار (بدون اعشار)
            late_fee_amount = Decimal(0)
            if (
                st == "overdue"
                and late_fee_rate_dec is not None
                and late_fee_rate_dec > Decimal(0)
                and remaining > Decimal(0)
            ):
                apply_fee = True
                if grace_days_val is not None and grace_days_val > 0:
                    if overdue_days <= grace_days_val:
                        apply_fee = False
                if apply_fee:
                    try:
                        late_fee_amount = (remaining * late_fee_rate_dec / Decimal("100")).quantize(
                            Decimal("1"), rounding=ROUND_HALF_UP
                        )
                    except Exception:
                        late_fee_amount = Decimal(0)
            items.append({
                "invoice_id": int(doc.id),
                "invoice_code": doc.code,
                "person_id": extra.get("person_id"),
                "person_name": person_name,
                "document_date": doc.document_date.isoformat(),
                "seq": int(it.get("seq") or 0),
                "due_date": due.isoformat(),
                "principal": float(principal),
                "interest": float(interest),
                "total": float(total),
                "paid_amount": float(paid),
                "remaining": float(remaining),
                "status": st,
                "overdue_days": overdue_days,
                "late_fee_amount": float(late_fee_amount),
            })

    total_count = len(items)
    # صفحه‌بندی
    page_items = items[skip: skip + take]
    return {
        "items": page_items,
        "pagination": {
            "total": total_count,
            "take": take,
            "skip": skip,
            "page": (skip // take) + 1,
            "has_next": skip + take < total_count,
        },
        "filters": {
            "fiscal_year_id": fiscal_year_id,
            "due_from": due_from,
            "due_to": due_to,
            "status": status_filter,
            "person_id": person_id_filter,
            "invoice_id": invoice_id_filter,
        },
    }


def export_installments_csv(
    db: Session,
    business_id: int,
    query: Dict[str, Any],
) -> bytes:
    """
    خروجی CSV اقساط بر اساس همان فیلترهای search_installments.
    """
    data = search_installments(db, business_id, query)
    items = data.get("items") or []
    output = io.StringIO()
    writer = csv.writer(output)
    # header
    writer.writerow([
        "invoice_id",
        "invoice_code",
        "person_id",
        "person_name",
        "document_date",
        "seq",
        "due_date",
        "status",
        "principal",
        "interest",
        "total",
        "paid_amount",
        "remaining",
        "overdue_days",
        "late_fee_amount",
    ])
    for it in items:
        writer.writerow([
            it.get("invoice_id"),
            it.get("invoice_code"),
            it.get("person_id"),
            it.get("person_name"),
            it.get("document_date"),
            it.get("seq"),
            it.get("due_date"),
            it.get("status"),
            it.get("principal"),
            it.get("interest"),
            it.get("total"),
            it.get("paid_amount"),
            it.get("remaining"),
            it.get("overdue_days"),
            it.get("late_fee_amount"),
        ])
    return output.getvalue().encode("utf-8-sig")


def export_installments_xlsx(
    db: Session,
    business_id: int,
    query: Dict[str, Any],
) -> tuple[bytes, str, str]:
    """
    تلاش برای ساخت فایل XLSX؛ اگر کتابخانه موجود نبود، به CSV برمی‌گردیم.
    Returns: (content_bytes, mime_type, file_ext)
    """
    try:
        from openpyxl import Workbook  # type: ignore
        wb = Workbook()
        ws = wb.active
        ws.title = "Installments"
        headers = [
            "invoice_id",
            "invoice_code",
            "person_id",
            "person_name",
            "document_date",
            "seq",
            "due_date",
            "status",
            "principal",
            "interest",
            "total",
            "paid_amount",
            "remaining",
            "overdue_days",
            "late_fee_amount",
        ]
        ws.append(headers)
        data = search_installments(db, business_id, query)
        for it in data.get("items", []):
            ws.append([
                it.get("invoice_id"),
                it.get("invoice_code"),
                it.get("person_id"),
                it.get("person_name"),
                it.get("document_date"),
                it.get("seq"),
                it.get("due_date"),
                it.get("status"),
                it.get("principal"),
                it.get("interest"),
                it.get("total"),
                it.get("paid_amount"),
                it.get("remaining"),
                it.get("overdue_days"),
                it.get("late_fee_amount"),
            ])
        bio = io.BytesIO()
        wb.save(bio)
        return bio.getvalue(), "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "xlsx"
    except Exception:
        # Fallback: CSV
        content = export_installments_csv(db, business_id, query)
        return content, "text/csv; charset=utf-8", "csv"


