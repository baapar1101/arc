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
from adapters.db.models.user import User
from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.models.person import Person
from adapters.db.models.product import Product
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


def _get_person_control_account(db: Session) -> Account:
    # عمومی اشخاص (پرداختنی/دریافتنی) پیش‌فرض: 20201
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
        # فقط برای کالاهای دارای کنترل موجودی
        if not bool(info.get("inventory_tracked")):
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

    def code(name: str, default_code: str) -> str:
        return str(overrides.get(name) or default_code)

    return {
        "revenue": _get_fixed_account_by_code(db, code("revenue", "70101")),
        "sales_return": _get_fixed_account_by_code(db, code("sales_return", "70102")),
        "inventory": _get_fixed_account_by_code(db, code("inventory", "10301")),
        "inventory_finished": _get_fixed_account_by_code(db, code("inventory_finished", "10302")),
        "cogs": _get_fixed_account_by_code(db, code("cogs", "60101")),
        "vat_out": _get_fixed_account_by_code(db, code("vat_out", "20801")),
        "vat_in": _get_fixed_account_by_code(db, code("vat_in", "10801")),
        "direct_consumption": _get_fixed_account_by_code(db, code("direct_consumption", "60201")),
        "wip": _get_fixed_account_by_code(db, code("wip", "60301")),
        "waste_expense": _get_fixed_account_by_code(db, code("waste_expense", "60401")),
        "person": _get_person_control_account(db),
    }


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

    # Inventory validation and costing pre-calculation
    # Determine outgoing lines for stock checks
    movement_hint, _ = _movement_from_type(invoice_type)
    outgoing_lines: List[Dict[str, Any]] = []
    for ln in lines_input:
        info = ln.get("extra_info") or {}
        mv = info.get("movement") or movement_hint
        if mv == "out":
            outgoing_lines.append(ln)

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

    # Filter outgoing lines to only inventory-tracked products for stock checks
    tracked_outgoing_lines: List[Dict[str, Any]] = []
    for ln in outgoing_lines:
        pid = ln.get("product_id")
        if pid and track_map.get(int(pid)):
            tracked_outgoing_lines.append(ln)

    # Ensure stock sufficiency for outgoing (only for tracked products)
    if tracked_outgoing_lines:
        _ensure_stock_sufficient(db, business_id, document_date, tracked_outgoing_lines)

    # Costing method (only for tracked products)
    costing_method = _get_costing_method(data)
    if costing_method == "fifo" and tracked_outgoing_lines:
        fifo_costs = _calculate_fifo_cogs_for_outgoing(db, business_id, document_date, tracked_outgoing_lines)
        # annotate lines with cogs_amount in the same order as tracked_outgoing_lines
        i = 0
        for ln in lines_input:
            info = ln.get("extra_info") or {}
            mv = info.get("movement") or movement_hint
            if mv == "out" and info.get("inventory_tracked"):
                amt = fifo_costs[i]
                i += 1
                info = dict(info)
                info["cogs_amount"] = float(amt)
                ln["extra_info"] = info

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

    # Create product lines (no debit/credit)
    for line in lines_input:
        product_id = line.get("product_id")
        qty = Decimal(str(line.get("quantity", 0) or 0))
        if not product_id or qty <= 0:
            raise ApiError("INVALID_LINE", "line.product_id and positive quantity are required", http_status=400)
        extra_info = line.get("extra_info") or {}
        db.add(DocumentLine(
            document_id=document.id,
            product_id=int(product_id),
            quantity=qty,
            debit=Decimal(0),
            credit=Decimal(0),
            description=line.get("description"),
            extra_info=extra_info,
        ))

    # Accounting lines for finalized invoices
    if not document.is_proforma:
        accounts = _resolve_accounts_for_invoice(db, data)

        net = Decimal(str(totals["gross"])) - Decimal(str(totals["discount"]))
        tax = Decimal(str(totals["tax"]))
        total_with_tax = net + tax

        # COGS when applicable
        cogs_total = _extract_cogs_total(lines_input)

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
            if cogs_total > 0:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["cogs"].id,
                    debit=cogs_total,
                    credit=Decimal(0),
                    description="بهای تمام‌شده کالای فروش‌رفته",
                ))
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["inventory"].id,
                    debit=Decimal(0),
                    credit=cogs_total,
                    description="خروج از موجودی بابت فروش",
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
            if cogs_total > 0:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["inventory"].id,
                    debit=cogs_total,
                    credit=Decimal(0),
                    description="ورود به موجودی بابت برگشت",
                ))
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["cogs"].id,
                    debit=Decimal(0),
                    credit=cogs_total,
                    description="تعدیل بهای تمام‌شده برگشت",
                ))

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
                for p in payments:
                    amount = Decimal(str(p.get("amount", 0) or 0))
                    if amount <= 0:
                        continue
                    total_amount += amount
                    account_lines.append({
                        "transaction_type": p.get("transaction_type"),
                        "amount": float(amount),
                        "description": p.get("description"),
                        "transaction_date": p.get("transaction_date"),
                        "commission": p.get("commission"),
                    })

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

    # Recreate lines
    db.query(DocumentLine).filter(DocumentLine.document_id == document.id).delete(synchronize_session=False)

    lines_input: List[Dict[str, Any]] = list(data.get("lines") or [])
    if not lines_input:
        raise ApiError("LINES_REQUIRED", "At least one line is required", http_status=400)

    # Inventory validation and costing before re-adding lines
    inv_type = document.document_type
    movement_hint, _ = _movement_from_type(inv_type)
    outgoing_lines: List[Dict[str, Any]] = []
    for ln in lines_input:
        info = ln.get("extra_info") or {}
        mv = info.get("movement") or movement_hint
        if mv == "out":
            outgoing_lines.append(ln)

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

    tracked_outgoing_lines: List[Dict[str, Any]] = []
    for ln in outgoing_lines:
        pid = ln.get("product_id")
        if pid and track_map.get(int(pid)):
            tracked_outgoing_lines.append(ln)

    if tracked_outgoing_lines:
        _ensure_stock_sufficient(db, document.business_id, document.document_date, tracked_outgoing_lines, exclude_document_id=document.id)

    header_for_costing = data if data else {"extra_info": document.extra_info}
    costing_method = _get_costing_method(header_for_costing)
    if costing_method == "fifo" and tracked_outgoing_lines:
        fifo_costs = _calculate_fifo_cogs_for_outgoing(db, document.business_id, document.document_date, tracked_outgoing_lines, exclude_document_id=document.id)
        i = 0
        for ln in lines_input:
            info = ln.get("extra_info") or {}
            mv = info.get("movement") or movement_hint
            if mv == "out" and info.get("inventory_tracked"):
                amt = fifo_costs[i]
                i += 1
                info = dict(info)
                info["cogs_amount"] = float(amt)
                ln["extra_info"] = info

    for line in lines_input:
        product_id = line.get("product_id")
        qty = Decimal(str(line.get("quantity", 0) or 0))
        if not product_id or qty <= 0:
            raise ApiError("INVALID_LINE", "line.product_id and positive quantity are required", http_status=400)
        extra_info = line.get("extra_info") or {}
        db.add(DocumentLine(
            document_id=document.id,
            product_id=int(product_id),
            quantity=qty,
            debit=Decimal(0),
            credit=Decimal(0),
            description=line.get("description"),
            extra_info=extra_info,
        ))

    # Accounting lines if finalized
    if not document.is_proforma:
        accounts = _resolve_accounts_for_invoice(db, data if data else {"extra_info": document.extra_info})
        header_extra = data.get("extra_info") or document.extra_info or {}
        totals = (header_extra.get("totals") or {})
        if not totals:
            totals = _extract_totals_from_lines(lines_input)
        net = Decimal(str(totals.get("gross", 0))) - Decimal(str(totals.get("discount", 0)))
        tax = Decimal(str(totals.get("tax", 0)))
        total_with_tax = net + tax
        person_id = _person_id_from_header({"extra_info": header_extra})
        cogs_total = _extract_cogs_total(lines_input)

        if inv_type == INVOICE_SALES:
            if person_id:
                db.add(DocumentLine(document_id=document.id, account_id=accounts["person"].id, person_id=person_id, debit=total_with_tax, credit=Decimal(0), description=document.description))
            db.add(DocumentLine(document_id=document.id, account_id=accounts["revenue"].id, debit=Decimal(0), credit=net, description="درآمد فروش"))
            if tax > 0:
                db.add(DocumentLine(document_id=document.id, account_id=accounts["vat_out"].id, debit=Decimal(0), credit=tax, description="مالیات خروجی"))
            if cogs_total > 0:
                db.add(DocumentLine(document_id=document.id, account_id=accounts["cogs"].id, debit=cogs_total, credit=Decimal(0), description="بهای تمام‌شده"))
                db.add(DocumentLine(document_id=document.id, account_id=accounts["inventory"].id, debit=Decimal(0), credit=cogs_total, description="خروج موجودی"))
        elif inv_type == INVOICE_SALES_RETURN:
            if person_id:
                db.add(DocumentLine(document_id=document.id, account_id=accounts["person"].id, person_id=person_id, debit=Decimal(0), credit=total_with_tax, description=document.description))
            db.add(DocumentLine(document_id=document.id, account_id=accounts["sales_return"].id, debit=net, credit=Decimal(0), description="برگشت از فروش"))
            if tax > 0:
                db.add(DocumentLine(document_id=document.id, account_id=accounts["vat_in"].id, debit=tax, credit=Decimal(0), description="تعدیل VAT"))
            if cogs_total > 0:
                db.add(DocumentLine(document_id=document.id, account_id=accounts["inventory"].id, debit=cogs_total, credit=Decimal(0), description="ورود موجودی"))
                db.add(DocumentLine(document_id=document.id, account_id=accounts["cogs"].id, debit=Decimal(0), credit=cogs_total, description="تعدیل بهای تمام‌شده"))
        elif inv_type == INVOICE_PURCHASE:
            db.add(DocumentLine(document_id=document.id, account_id=accounts["inventory"].id, debit=net, credit=Decimal(0), description="ورود موجودی"))
            if tax > 0:
                db.add(DocumentLine(document_id=document.id, account_id=accounts["vat_in"].id, debit=tax, credit=Decimal(0), description="مالیات ورودی"))
            if person_id:
                db.add(DocumentLine(document_id=document.id, account_id=accounts["person"].id, person_id=person_id, debit=Decimal(0), credit=total_with_tax, description=document.description))
        elif inv_type == INVOICE_PURCHASE_RETURN:
            db.add(DocumentLine(document_id=document.id, account_id=accounts["inventory"].id, debit=Decimal(0), credit=net, description="خروج موجودی"))
            if tax > 0:
                db.add(DocumentLine(document_id=document.id, account_id=accounts["vat_in"].id, debit=Decimal(0), credit=tax, description="تعدیل VAT ورودی"))
            if person_id:
                db.add(DocumentLine(document_id=document.id, account_id=accounts["person"].id, person_id=person_id, debit=total_with_tax, credit=Decimal(0), description=document.description))
        elif inv_type == INVOICE_DIRECT_CONSUMPTION:
            if cogs_total > 0:
                db.add(DocumentLine(document_id=document.id, account_id=accounts["direct_consumption"].id, debit=cogs_total, credit=Decimal(0), description="مصرف مستقیم"))
                db.add(DocumentLine(document_id=document.id, account_id=accounts["inventory"].id, debit=Decimal(0), credit=cogs_total, description="خروج موجودی"))
        elif inv_type == INVOICE_WASTE:
            if cogs_total > 0:
                db.add(DocumentLine(document_id=document.id, account_id=accounts["waste_expense"].id, debit=cogs_total, credit=Decimal(0), description="ضایعات"))
                db.add(DocumentLine(document_id=document.id, account_id=accounts["inventory"].id, debit=Decimal(0), credit=cogs_total, description="خروج موجودی"))
        elif inv_type == INVOICE_PRODUCTION:
            materials_cost = _extract_cogs_total([l for l in lines_input if (l.get("extra_info") or {}).get("movement") == "out"])
            if materials_cost > 0:
                db.add(DocumentLine(document_id=document.id, account_id=accounts["wip"].id, debit=materials_cost, credit=Decimal(0), description="انتقال به کاردرجریان"))
                db.add(DocumentLine(document_id=document.id, account_id=accounts["inventory"].id, debit=Decimal(0), credit=materials_cost, description="خروج مواد"))
            finished_cost = _extract_cogs_total([l for l in lines_input if (l.get("extra_info") or {}).get("movement") == "in"])
            if finished_cost > 0:
                db.add(DocumentLine(document_id=document.id, account_id=accounts["inventory_finished"].id, debit=finished_cost, credit=Decimal(0), description="ورود ساخته‌شده"))
                db.add(DocumentLine(document_id=document.id, account_id=accounts["wip"].id, debit=Decimal(0), credit=finished_cost, description="انتقال از کاردرجریان"))

    db.commit()
    db.refresh(document)
    return invoice_document_to_dict(db, document)


def invoice_document_to_dict(db: Session, document: Document) -> Dict[str, Any]:
    lines = db.query(DocumentLine).filter(DocumentLine.document_id == document.id).all()

    product_lines: List[Dict[str, Any]] = []
    account_lines: List[Dict[str, Any]] = []

    for line in lines:
        if line.product_id:
            product = db.query(Product).filter(Product.id == line.product_id).first()
            product_lines.append({
                "id": line.id,
                "product_id": line.product_id,
                "product_name": getattr(product, "name", None),
                "quantity": float(line.quantity) if line.quantity else None,
                "description": line.description,
                "extra_info": line.extra_info,
            })
        elif line.account_id:
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


