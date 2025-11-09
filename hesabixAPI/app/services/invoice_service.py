from __future__ import annotations

from typing import Any, Dict, List, Optional, Tuple
from datetime import datetime, date
from decimal import Decimal
import logging

from sqlalchemy.orm import Session
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
import jdatetime


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
        # موجودی و ساخته‌شده (در نبود حساب مجزا) هر دو 10102
        "inventory": _get_fixed_account_by_code(db, code("inventory", "10102")),
        "inventory_finished": _get_fixed_account_by_code(db, code("inventory_finished", "10102")),
        # بهای تمام شده و VAT ها مطابق سید
        "cogs": _get_fixed_account_by_code(db, code("cogs", "40001")),
        "vat_out": _get_fixed_account_by_code(db, code("vat_out", "20101")),
        "vat_in": _get_fixed_account_by_code(db, code("vat_in", "10104")),
        # مصرف مستقیم و ضایعات
        "direct_consumption": _get_fixed_account_by_code(db, code("direct_consumption", "70406")),
        "wip": _get_fixed_account_by_code(db, code("wip", "10106")),
        "waste_expense": _get_fixed_account_by_code(db, code("waste_expense", "70407")),
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

        net = Decimal(str(totals["gross"])) - Decimal(str(totals["discount"]))
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
            db.add(DocumentLine(
                document_id=document.id,
                account_id=accounts["revenue"].id,
                debit=Decimal(0),
                credit=net,
                description="درآمد فروش",
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
            db.add(DocumentLine(
                document_id=document.id,
                account_id=accounts["sales_return"].id,
                debit=net,
                credit=Decimal(0),
                description="برگشت از فروش",
            ))
            if tax > 0:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["vat_in"].id,
                    debit=tax,
                    credit=Decimal(0),
                    description="تعدیل VAT برگشت از فروش",
                ))
            # ورود موجودی/تعدیل COGS در پست حواله انجام می‌شود

        # Purchase
        elif invoice_type == INVOICE_PURCHASE:
            db.add(DocumentLine(
                document_id=document.id,
                account_id=accounts["inventory"].id,
                debit=net,
                credit=Decimal(0),
                description="ورود به موجودی بابت خرید",
            ))
            if tax > 0:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["vat_in"].id,
                    debit=tax,
                    credit=Decimal(0),
                    description="مالیات بر ارزش افزوده ورودی",
                ))
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
            db.add(DocumentLine(
                document_id=document.id,
                account_id=accounts["inventory"].id,
                debit=Decimal(0),
                credit=net,
                description="خروج از موجودی بابت برگشت خرید",
            ))
            if tax > 0:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["vat_in"].id,
                    debit=Decimal(0),
                    credit=tax,
                    description="تعدیل VAT ورودی برگشت خرید",
                ))
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

        # Direct consumption
        elif invoice_type == INVOICE_DIRECT_CONSUMPTION:
            cogs_lines = [l for l in lines_input if ((l.get("extra_info") or {}).get("movement") or movement_hint) == "out"]
            cogs_total = _extract_cogs_total(cogs_lines if cogs_lines else lines_input)
            if cogs_total > 0:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["direct_consumption"].id,
                    debit=cogs_total,
                    credit=Decimal(0),
                    description="مصرف مستقیم",
                ))
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["inventory"].id,
                    debit=Decimal(0),
                    credit=cogs_total,
                    description="خروج از موجودی بابت مصرف",
                ))

        # Waste
        elif invoice_type == INVOICE_WASTE:
            cogs_lines = [l for l in lines_input if ((l.get("extra_info") or {}).get("movement") or movement_hint) == "out"]
            cogs_total = _extract_cogs_total(cogs_lines if cogs_lines else lines_input)
            if cogs_total > 0:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["waste_expense"].id,
                    debit=cogs_total,
                    credit=Decimal(0),
                    description="ضایعات",
                ))
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["inventory"].id,
                    debit=Decimal(0),
                    credit=cogs_total,
                    description="خروج از موجودی بابت ضایعات",
                ))

        # Production (WIP)
        elif invoice_type == INVOICE_PRODUCTION:
            # materials (out) → Debit WIP, Credit Inventory
            materials_cost = _extract_cogs_total([l for l in lines_input if (l.get("extra_info") or {}).get("movement") == "out"])
            if materials_cost > 0:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["wip"].id,
                    debit=materials_cost,
                    credit=Decimal(0),
                    description="انتقال مواد به کاردرجریان",
                ))
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["inventory"].id,
                    debit=Decimal(0),
                    credit=materials_cost,
                    description="خروج مواد اولیه",
                ))
            # finished goods (in) → Debit Finished Inventory, Credit WIP
            finished_cost = _extract_cogs_total([l for l in lines_input if (l.get("extra_info") or {}).get("movement") == "in"])
            if finished_cost > 0:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["inventory_finished"].id,
                    debit=finished_cost,
                    credit=Decimal(0),
                    description="ورود کالای ساخته‌شده",
                ))
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["wip"].id,
                    debit=Decimal(0),
                    credit=finished_cost,
                    description="انتقال از کاردرجریان",
                ))

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
                    ttype = str(p.get("transaction_type") or "").strip().lower()
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
                    account_line: Dict[str, Any] = {
                        "transaction_type": p.get("transaction_type"),
                        "amount": float(amount),
                        "description": p.get("description"),
                        "transaction_date": p.get("transaction_date"),
                        "commission": p.get("commission"),
                    }
                    # pass through reference ids/names if provided
                    for key in ("bank_id", "bank_name", "cash_register_id", "cash_register_name", "petty_cash_id", "petty_cash_name", "check_id", "check_number", "person_id", "account_id"):
                        if p.get(key) is not None:
                            account_line[key] = p.get(key)
                    account_lines.append(account_line)

                if total_amount > 0 and account_lines:
                    is_receipt = invoice_type in {INVOICE_SALES, INVOICE_PURCHASE_RETURN}
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
                        "extra_info": {"source": "invoice", "invoice_id": document.id},
                    }
                    rp_doc = create_receipt_payment(db=db, business_id=business_id, user_id=user_id, data=rp_data)
                    if isinstance(rp_doc, dict) and rp_doc.get("id"):
                        payment_docs.append(int(rp_doc["id"]))
        except Exception as ex:
            logger.exception("could not create receipt/payment for invoice: %s", ex)

    # Save links back to invoice
    if payment_docs:
        extra = document.extra_info or {}
        links = dict((extra.get("links") or {}))
        links["receipt_payment_document_ids"] = payment_docs
        extra["links"] = links
        document.extra_info = extra
        db.commit()
        db.refresh(document)

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
        net = Decimal(str(totals.get("gross", 0))) - Decimal(str(totals.get("discount", 0)))
        tax = Decimal(str(totals.get("tax", 0)))
        total_with_tax = net + tax
        person_id = _person_id_from_header({"extra_info": header_extra})
        # inventory/COGS handled in warehouse posting

        if inv_type == INVOICE_SALES:
            if person_id:
                db.add(DocumentLine(document_id=document.id, account_id=accounts["person"].id, person_id=person_id, debit=total_with_tax, credit=Decimal(0), description=document.description))
            db.add(DocumentLine(document_id=document.id, account_id=accounts["revenue"].id, debit=Decimal(0), credit=net, description="درآمد فروش"))
            if tax > 0:
                db.add(DocumentLine(document_id=document.id, account_id=accounts["vat_out"].id, debit=Decimal(0), credit=tax, description="مالیات خروجی"))
            # COGS/Inventory by warehouse posting
        elif inv_type == INVOICE_SALES_RETURN:
            if person_id:
                db.add(DocumentLine(document_id=document.id, account_id=accounts["person"].id, person_id=person_id, debit=Decimal(0), credit=total_with_tax, description=document.description))
            db.add(DocumentLine(document_id=document.id, account_id=accounts["sales_return"].id, debit=net, credit=Decimal(0), description="برگشت از فروش"))
            if tax > 0:
                db.add(DocumentLine(document_id=document.id, account_id=accounts["vat_in"].id, debit=tax, credit=Decimal(0), description="تعدیل VAT"))
            # Inventory/COGS handled in warehouse posting
        elif inv_type == INVOICE_PURCHASE:
            # Inventory via warehouse posting; invoice handles VAT/AP only (or GRNI if فعال)
            if tax > 0:
                db.add(DocumentLine(document_id=document.id, account_id=accounts["vat_in"].id, debit=tax, credit=Decimal(0), description="مالیات ورودی"))
            if person_id:
                db.add(DocumentLine(document_id=document.id, account_id=accounts["person"].id, person_id=person_id, debit=Decimal(0), credit=total_with_tax, description=document.description))
        elif inv_type == INVOICE_PURCHASE_RETURN:
            # Inventory via warehouse posting
            if tax > 0:
                db.add(DocumentLine(document_id=document.id, account_id=accounts["vat_in"].id, debit=Decimal(0), credit=tax, description="تعدیل VAT ورودی"))
            if person_id:
                db.add(DocumentLine(document_id=document.id, account_id=accounts["person"].id, person_id=person_id, debit=total_with_tax, credit=Decimal(0), description=document.description))
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

    db.commit()
    db.refresh(document)
    return invoice_document_to_dict(db, document)


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


