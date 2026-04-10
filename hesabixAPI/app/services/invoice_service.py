from __future__ import annotations

from typing import Any, Dict, List, Optional, Tuple
from datetime import datetime, date, timedelta
from decimal import Decimal, ROUND_HALF_UP
import logging

from sqlalchemy.orm import Session
from sqlalchemy.orm.attributes import flag_modified
from sqlalchemy import and_, or_, func
from sqlalchemy.exc import IntegrityError

from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.account import Account
from adapters.db.models.currency import Currency
from adapters.db.models.bank_account import BankAccount
from adapters.db.models.cash_register import CashRegister
from adapters.db.models.petty_cash import PettyCash
from adapters.db.models.check import Check, CheckType
from adapters.db.models.user import User
from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.models.person import Person
from adapters.db.models.product import Product
from adapters.db.models.invoice_item_line import InvoiceItemLine
from adapters.db.models.tax_unit import TaxUnit
from adapters.db.models.product_bom import ProductBOM, ProductBOMOutput
from adapters.db.models.business import Business
from app.core.calendar import CalendarConverter, CalendarType
from app.core.responses import ApiError
from app.services.document_monetization_service import ensure_document_policy_allows_creation
from app.services.credit_service import get_business_credit_settings
import jdatetime
import io
import csv


logger = logging.getLogger(__name__)


def invalidate_invoices_cache(business_id: int, fiscal_year_id: Optional[int] = None, invoice_id: Optional[int] = None, document_type: Optional[str] = None, project_id: Optional[int] = None):
	"""
	حذف تمام کش‌های مربوط به لیست فاکتورها یک کسب‌وکار
	
	این تابع از چند روش استفاده می‌کند:
	1. Tag-based invalidation با set ردیس: حذف انتخابی بر اساس business_id, fiscal_year_id, document_type و project_id (بهینه‌تر)
	2. Pattern-based invalidation: حذف تمام کلیدهای invoices_search:* (fallback برای اطمینان)
	3. Redis Pub/Sub: انتشار پیام invalidation برای تمام instanceها
	
	Args:
		business_id: شناسه کسب‌وکار
		fiscal_year_id: شناسه سال مالی (اختیاری - بسیار مهم)
			- اگر None باشد، تمام کش‌های مربوط به business_id حذف می‌شوند
			- اگر مشخص باشد، فقط کش‌های مربوط به آن fiscal_year_id حذف می‌شوند
		invoice_id: شناسه فاکتور خاص (اختیاری)
		document_type: نوع فاکتور (invoice_sales, invoice_purchase, ...) (اختیاری)
		project_id: شناسه پروژه (اختیاری)
	"""
	from app.core.cache import get_cache
	cache = get_cache()
	if not cache.enabled:
		return
	
	try:
		# روش 1: استفاده از invalidate_invoices_by_business (بهینه‌ترین روش)
		deleted_count = cache.invalidate_invoices_by_business(business_id, fiscal_year_id, invoice_id, document_type, project_id)
		if deleted_count > 0:
			logger.info(f"Invalidated {deleted_count} cache keys for business_id {business_id}, fiscal_year_id {fiscal_year_id}, invoice_id {invoice_id}, document_type {document_type}, project_id {project_id}")
		
		# روش 2: حذف تمام کلیدهای invoices_search:* (fallback برای اطمینان کامل)
		pattern = f"invoices_search:{business_id}:*"
		deleted_pattern = cache.delete_pattern(pattern)
		if deleted_pattern > 0:
			logger.info(f"Invalidated {deleted_pattern} cache keys using pattern: {pattern}")
		
		# حذف کش فاکتور خاص اگر مشخص شده باشد
		if invoice_id:
			invoice_pattern = f"invoice:{business_id}:{invoice_id}*"
			deleted_invoice = cache.delete_pattern(invoice_pattern)
			if deleted_invoice > 0:
				logger.info(f"Invalidated {deleted_invoice} cache keys for invoice_id {invoice_id} using pattern: {invoice_pattern}")
		
		# روش 3: انتشار پیام invalidation از طریق Redis Pub/Sub
		invalidation_message = {
			"type": "invoices_cache_invalidation",
			"business_id": business_id,
			"fiscal_year_id": fiscal_year_id,
			"invoice_id": invoice_id,
			"document_type": document_type,
			"project_id": project_id,
			"timestamp": None
		}
		try:
			import time
			invalidation_message["timestamp"] = time.time()
			cache.publish_invalidation("cache_invalidation", invalidation_message)
			logger.info(f"Published invalidation message for business_id {business_id}, fiscal_year_id {fiscal_year_id}, invoice_id {invoice_id}")
		except Exception as pub_error:
			logger.warning(f"Error publishing invalidation message: {pub_error}")
	
	except Exception as e:
		# خطا در invalidate نباید مانع عملیات اصلی شود
		logger.warning(f"Error invalidating invoices cache for business_id {business_id}: {e}")


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


def _build_product_tax_snapshot_map(
    db: Session,
    business_id: int,
    product_ids: List[int],
) -> Dict[int, Dict[str, Any]]:
    """
    تهیه اطلاعات مالیاتی کالا برای ذخیره در snapshot خطوط فاکتور.
    """
    if not product_ids:
        return {}
    unique_ids = list({int(pid) for pid in product_ids if pid})
    if not unique_ids:
        return {}
    rows = db.query(
        Product.id,
        Product.tax_code,
        Product.tax_unit_id,
        Product.main_unit,
    ).filter(
        Product.business_id == business_id,
        Product.id.in_(unique_ids),
    ).all()
    unit_ids = {row.tax_unit_id for row in rows if row.tax_unit_id}
    unit_map: Dict[int, Dict[str, Any]] = {}
    if unit_ids:
        units = db.query(TaxUnit.id, TaxUnit.code, TaxUnit.name).filter(TaxUnit.id.in_(unit_ids)).all()
        for unit in units:
            unit_map[int(unit.id)] = {"code": unit.code, "name": unit.name}
    result: Dict[int, Dict[str, Any]] = {}
    for row in rows:
        unit_info = unit_map.get(int(row.tax_unit_id)) if row.tax_unit_id else None
        result[int(row.id)] = {
            "tax_code": row.tax_code,
            "tax_unit_id": int(row.tax_unit_id) if row.tax_unit_id else None,
            "tax_unit_code": unit_info["code"] if unit_info else None,
            "tax_unit_name": unit_info["name"] if unit_info else None,
            "product_main_unit": row.main_unit,
        }
    return result


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
    
    # اضافه کردن حرکات از حواله‌های انبار (WarehouseDocumentLine)
    from adapters.db.models.warehouse_document import WarehouseDocument
    from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
    
    wh_movements_query = db.query(WarehouseDocumentLine).join(
        WarehouseDocument,
        WarehouseDocument.id == WarehouseDocumentLine.warehouse_document_id
    ).filter(
        and_(
            WarehouseDocument.business_id == business_id,
            WarehouseDocument.status == "posted",
            WarehouseDocument.document_date <= up_to_date,
            WarehouseDocumentLine.product_id == product_id,
        )
    )
    
    if warehouse_id is not None:
        wh_movements_query = wh_movements_query.filter(
            WarehouseDocumentLine.warehouse_id == warehouse_id
        )
    
    wh_movements = wh_movements_query.all()
    for wh_mv in wh_movements:
        if wh_mv.movement == "in":
            bal += Decimal(str(wh_mv.quantity))
        elif wh_mv.movement == "out":
            bal -= Decimal(str(wh_mv.quantity))
    
    return bal


def get_financial_stock_bulk(
    db: Session,
    business_id: int,
    product_ids: List[int],
    as_of_date: Optional[date] = None,
    warehouse_id: Optional[int] = None,
) -> Dict[int, Decimal]:
    """
    محاسبه موجودی مالی برای لیستی از کالاها.
    بر اساس حرکات موجودی از اسناد مالی (DocumentLine).
    بازگشت: Dict[product_id, quantity]
    """
    if not product_ids:
        return {}
    
    if as_of_date is None:
        as_of_date = datetime.now().date()
    
    # دریافت حرکات از اسناد مالی
    movements = _iter_product_movements(
        db,
        business_id,
        product_ids,
        [warehouse_id] if warehouse_id is not None else None,
        as_of_date,
        exclude_document_id=None,
    )
    
    # محاسبه موجودی
    stock_dict: Dict[int, Decimal] = {}
    for mv in movements:
        pid = int(mv["product_id"])
        qty = Decimal(str(mv["quantity"] or 0))
        if qty <= 0:
            continue
        
        # اگر انبار مشخص شده، فقط حرکات همان انبار را لحاظ کن
        if warehouse_id is not None and mv.get("warehouse_id") is not None:
            if int(mv["warehouse_id"]) != int(warehouse_id):
                continue
        
        if pid not in stock_dict:
            stock_dict[pid] = Decimal(0)
        
        if mv["movement"] == "in":
            stock_dict[pid] += qty
        elif mv["movement"] == "out":
            stock_dict[pid] -= qty
    
    # برای کالاهایی که حرکتی نداشتند، مقدار 0 برگردان
    for pid in product_ids:
        if pid not in stock_dict:
            stock_dict[pid] = Decimal(0)
    
    return stock_dict


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


def _extract_cogs_total_for_invoice(lines: List[Dict[str, Any]]) -> Decimal:
    """
    محاسبه COGS برای فاکتورها (بدون بررسی inventory_posted).
    برای مصرف مستقیم، ضایعات و تولید استفاده می‌شود.
    """
    total = Decimal(0)
    for line in lines:
        info = line.get("extra_info") or {}
        qty = Decimal(str(line.get("quantity", 0) or 0))
        if qty <= 0:
            continue
        
        # اولویت: cogs_amount > cost_price > unit_price
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
        # هزینه عملیات/سربار تولید (برای انتقال به WIP در فاکتور تولید)
        "production_overhead": _get_fixed_account_by_code(db, code("production_overhead", "70408")),
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


def _resolve_and_validate_person_id(db: Session, business_id: int, person_id: Optional[int]) -> Optional[int]:
    """
    اگر person_id مقدار داشته باشد، وجود شخص در جدول persons و تعلق به همان business_id را بررسی می‌کند.
    در صورت نامعتبر بودن (حذف شده یا متعلق به کسب‌وکار دیگر) ApiError با کد 400 پرتاب می‌شود
    تا از خطای ForeignKeyViolation در document_lines جلوگیری شود.
    """
    if person_id is None or person_id <= 0:
        return None
    person = db.query(Person).filter(
        and_(Person.id == person_id, Person.business_id == business_id)
    ).first()
    if not person:
        raise ApiError(
            "PERSON_NOT_FOUND_OR_WRONG_BUSINESS",
            "شخص انتخاب‌شده وجود ندارد یا به این کسب‌وکار تعلق ندارد؛ امکان ذخیره فاکتور با این شخص وجود ندارد.",
            http_status=400,
        )
    return int(person_id)


def _normalize_document_extra_info_for_storage(extra_info: Optional[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    """نرمال‌سازی extra_info قبل از ذخیره در دیتابیس تا فیلدهای عددی (مثل person_id) به صورت int ذخیره شوند."""
    if not extra_info or not isinstance(extra_info, dict):
        return extra_info
    from copy import deepcopy
    out = deepcopy(extra_info)
    for key in ("person_id", "seller_id"):
        val = out.get(key)
        if val is not None:
            try:
                out[key] = int(val)
            except (TypeError, ValueError):
                pass
    links = out.get("links")
    if isinstance(links, dict):
        links = dict(links)
        for key in ("warehouse_document_ids", "receipt_payment_document_ids"):
            arr = links.get(key)
            if isinstance(arr, list):
                try:
                    links[key] = [int(x) for x in arr if x is not None]
                except (TypeError, ValueError):
                    pass
        out["links"] = links
    return out


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


def _validate_selected_instances(
    db: Session,
    business_id: int,
    product_id: int,
    selected_instance_ids: List[Any],
    quantity: int,
    invoice_type: str,
) -> None:
    """
    اعتبارسنجی selected_instance_ids برای کالاهای یونیک در فاکتور.
    
    این تابع فقط برای فاکتورهای فروش و برگشت از خرید معنا دارد (چون حواله خارج دارند).
    """
    from adapters.db.models.product_instance import ProductInstance
    
    # فقط برای فاکتورهای فروش و برگشت از خرید
    if invoice_type not in (INVOICE_SALES, INVOICE_PURCHASE_RETURN):
        return
    
    if not selected_instance_ids or not isinstance(selected_instance_ids, list):
        return
    
    # بررسی محصول
    product = db.query(Product).filter(
        and_(Product.id == product_id, Product.business_id == business_id)
    ).first()
    if not product:
        raise ApiError("PRODUCT_NOT_FOUND", f"Product {product_id} not found", http_status=404)
    
    # بررسی اینکه کالا یونیک است
    if product.inventory_mode != "unique":
        raise ApiError(
            "NOT_UNIQUE_PRODUCT",
            f"کالای {product.name} در حالت یونیک نیست. انتخاب instance فقط برای کالاهای یونیک امکان‌پذیر است.",
            http_status=400
        )
    
    # بررسی تعداد - باید دقیقاً برابر quantity باشد
    instance_count = len(selected_instance_ids)
    if instance_count != quantity:
        raise ApiError(
            "INSTANCE_COUNT_MISMATCH",
            f"تعداد instance های انتخاب شده ({instance_count}) باید دقیقاً برابر با تعداد کالا ({quantity}) باشد",
            http_status=400
        )
    
    # بررسی تکرار در لیست
    unique_ids = set()
    for inst_id in selected_instance_ids:
        try:
            inst_id_int = int(inst_id)
            if inst_id_int in unique_ids:
                raise ApiError(
                    "DUPLICATE_INSTANCE",
                    f"instance با ID {inst_id_int} به صورت تکراری انتخاب شده است",
                    http_status=400
                )
            unique_ids.add(inst_id_int)
        except (ValueError, TypeError):
            raise ApiError(
                "INVALID_INSTANCE_ID",
                f"شناسه instance معتبر نیست: {inst_id}",
                http_status=400
            )
    
    # بررسی دسترس بودن همه instance ها
    for inst_id_int in unique_ids:
        instance = db.query(ProductInstance).filter(
            and_(
                ProductInstance.id == inst_id_int,
                ProductInstance.business_id == business_id,
                ProductInstance.product_id == product_id,
                ProductInstance.status == "available",
            )
        ).first()
        
        if not instance:
            raise ApiError(
                "INSTANCE_NOT_AVAILABLE",
                f"کالای یونیک با ID {inst_id_int} یافت نشد یا در دسترس نیست (status != available)",
                http_status=404
            )


# ==================== توابع محاسبه سود فاکتور ====================

def _empty_profit_response() -> Dict[str, Any]:
    """پاسخ خالی برای سود"""
    return {
        "gross_profit": 0.0,
        "net_profit": 0.0,
        "gross_profit_percent": 0.0,
        "net_profit_percent": 0.0,
        "total_profit": 0.0,
        "total_profit_percent": 0.0,
        "total_overhead": 0.0,
        "line_profits": []
    }


def _calculate_average_purchase_cost(
    db: Session,
    business_id: int,
    product_id: int,
    as_of_date: date
) -> Decimal:
    """
    محاسبه میانگین قیمت خرید محصول از تاریخچه
    """
    # دریافت تمام فاکتورهای خرید تا تاریخ مشخص
    purchase_docs = db.query(Document).join(DocumentLine).filter(
        and_(
            Document.business_id == business_id,
            Document.document_type == INVOICE_PURCHASE,
            Document.document_date <= as_of_date,
            DocumentLine.product_id == product_id
        )
    ).all()
    
    total_cost = Decimal(0)
    total_qty = Decimal(0)
    
    for doc in purchase_docs:
        lines = db.query(DocumentLine).filter(
            and_(
                DocumentLine.document_id == doc.id,
                DocumentLine.product_id == product_id
            )
        ).all()
        
        for line in lines:
            qty = Decimal(str(line.quantity or 0))
            if qty <= 0:
                continue
            
            # استفاده از cost_price از extra_info یا unit_price
            extra_info = line.extra_info or {}
            cost_per_unit = Decimal(0)
            if extra_info.get("cost_price") is not None:
                cost_per_unit = Decimal(str(extra_info.get("cost_price")))
            elif line.unit_price is not None:
                cost_per_unit = Decimal(str(line.unit_price))
            
            total_cost += qty * cost_per_unit
            total_qty += qty
    
    if total_qty > 0:
        return total_cost / total_qty
    return Decimal(0)


def _calculate_fifo_cost(
    db: Session,
    business_id: int,
    product_id: int,
    quantity: Decimal,
    as_of_date: date,
    warehouse_id: Optional[int] = None
) -> Decimal:
    """
    محاسبه هزینه با روش FIFO (اول ورود، اول خروج)
    """
    movements = _iter_product_movements(
        db, business_id, [product_id],
        [warehouse_id] if warehouse_id else None,
        as_of_date, None
    )
    
    # مرتب‌سازی بر اساس تاریخ (قدیمی‌ترین اول)
    movements.sort(key=lambda x: (x["document_date"], x["document_id"]))
    
    remaining_qty = quantity
    total_cost = Decimal(0)
    
    for mv in movements:
        if mv["movement"] == "in" and remaining_qty > 0:
            qty_available = mv["quantity"]
            cost_per_unit = mv.get("cost_price") or Decimal(0)
            
            if qty_available > remaining_qty:
                total_cost += remaining_qty * cost_per_unit
                remaining_qty = Decimal(0)
                break
            else:
                total_cost += qty_available * cost_per_unit
                remaining_qty -= qty_available
    
    if quantity > 0:
        return total_cost / quantity
    return Decimal(0)


def _calculate_lifo_cost(
    db: Session,
    business_id: int,
    product_id: int,
    quantity: Decimal,
    as_of_date: date,
    warehouse_id: Optional[int] = None
) -> Decimal:
    """
    محاسبه هزینه با روش LIFO (آخر ورود، اول خروج)
    """
    movements = _iter_product_movements(
        db, business_id, [product_id],
        [warehouse_id] if warehouse_id else None,
        as_of_date, None
    )
    
    # مرتب‌سازی بر اساس تاریخ (جدیدترین اول)
    movements.sort(key=lambda x: (x["document_date"], x["document_id"]), reverse=True)
    
    remaining_qty = quantity
    total_cost = Decimal(0)
    
    for mv in movements:
        if mv["movement"] == "in" and remaining_qty > 0:
            qty_available = mv["quantity"]
            cost_per_unit = mv.get("cost_price") or Decimal(0)
            
            if qty_available > remaining_qty:
                total_cost += remaining_qty * cost_per_unit
                remaining_qty = Decimal(0)
                break
            else:
                total_cost += qty_available * cost_per_unit
                remaining_qty -= qty_available
    
    if quantity > 0:
        return total_cost / quantity
    return Decimal(0)


def _calculate_weighted_average_cost(
    db: Session,
    business_id: int,
    product_id: int,
    as_of_date: date
) -> Decimal:
    """
    محاسبه میانگین وزنی قیمت خرید
    (همان _calculate_average_purchase_cost)
    """
    return _calculate_average_purchase_cost(db, business_id, product_id, as_of_date)


def _get_cost_per_unit_by_basis(
    db: Session,
    business_id: int,
    product: Product,
    line: DocumentLine,
    calculation_basis: str,
    document_date: date,
    warehouse_id: Optional[int] = None
) -> Decimal:
    """
    محاسبه هزینه هر واحد بر اساس مبنای انتخاب شده
    """
    extra_info = line.extra_info or {}
    
    if calculation_basis == "purchase_price":
        return Decimal(str(product.base_purchase_price or 0))
    
    elif calculation_basis == "cost_price":
        if extra_info.get("cost_price") is not None:
            return Decimal(str(extra_info.get("cost_price")))
        return Decimal(str(product.base_purchase_price or 0))
    
    elif calculation_basis == "actual_cost":
        if extra_info.get("cost_price") is not None:
            return Decimal(str(extra_info.get("cost_price")))
        if extra_info.get("cogs_amount") is not None and line.quantity > 0:
            return Decimal(str(extra_info.get("cogs_amount"))) / Decimal(str(line.quantity))
        return Decimal(str(product.base_purchase_price or 0))
    
    elif calculation_basis == "average_cost":
        return _calculate_average_purchase_cost(db, business_id, product.id, document_date)
    
    elif calculation_basis == "fifo":
        return _calculate_fifo_cost(db, business_id, product.id, Decimal(str(line.quantity)), document_date, warehouse_id)
    
    elif calculation_basis == "lifo":
        return _calculate_lifo_cost(db, business_id, product.id, Decimal(str(line.quantity)), document_date, warehouse_id)
    
    elif calculation_basis == "weighted_average":
        return _calculate_weighted_average_cost(db, business_id, product.id, document_date)
    
    elif calculation_basis == "standard_cost":
        if extra_info.get("standard_cost") is not None:
            return Decimal(str(extra_info.get("standard_cost")))
        return Decimal(str(product.base_purchase_price or 0))
    
    else:
        return Decimal(str(product.base_purchase_price or 0))


def _calculate_overhead_cost(
    db: Session,
    business_id: int,
    document_id: int,
    total_cost: Decimal,
    overhead_type: str,
    overhead_percent: Optional[Decimal] = None
) -> Decimal:
    """
    محاسبه هزینه‌های سربار
    """
    if overhead_type == "none":
        return Decimal(0)
    
    elif overhead_type == "custom_percent":
        if overhead_percent is None or overhead_percent <= 0:
            return Decimal(0)
        return total_cost * (overhead_percent / 100)
    
    elif overhead_type == "production_overhead":
        document = db.query(Document).filter(Document.id == document_id).first()
        if document and document.document_type == "invoice_production":
            extra_info = document.extra_info or {}
            operations_total = Decimal(str(extra_info.get("production_operations_total", 0) or 0))
            return operations_total
        return Decimal(0)
    
    elif overhead_type == "all_overhead":
        # TODO: پیاده‌سازی کامل بر اساس نیاز کسب و کار
        return Decimal(0)
    
    return Decimal(0)


def _calculate_invoice_profit(
    db: Session,
    business_id: int,
    document_id: int,
    calculation_method: str = "automatic",
    calculation_basis: str = "purchase_price",
    include_overhead: bool = False,
    overhead_type: str = "none",
    overhead_percent: Optional[Decimal] = None,
    calculation_type: str = "gross"
) -> Dict[str, Any]:
    """
    محاسبه سود فاکتور با پشتیبانی از روش‌های مختلف و هزینه‌های سربار
    """
    # اگر محاسبه سود غیرفعال است
    if calculation_method == "disabled":
        return _empty_profit_response()
    
    # دریافت فاکتور
    document = db.query(Document).filter(Document.id == document_id).first()
    if not document or not document.document_type.startswith("invoice"):
        return _empty_profit_response()
    
    # فقط برای فاکتورهای فروش و تولید محاسبه می‌شود
    if document.document_type not in ["invoice_sales", "invoice_sales_return", "invoice_production"]:
        return _empty_profit_response()
    
    total_gross_profit = Decimal(0)
    total_net_profit = Decimal(0)
    total_sales = Decimal(0)
    total_cost = Decimal(0)
    line_profits = []
    
    # برای فاکتور تولید
    if document.document_type == "invoice_production":
        # دریافت ردیف‌های فاکتور از DocumentLine (برای فاکتور تولید)
        lines = db.query(DocumentLine).filter(DocumentLine.document_id == document_id).all()
        # جداسازی خطوط ورودی و خروجی
        out_lines = [ln for ln in lines if (ln.extra_info or {}).get("movement") == "out"]
        in_lines = [ln for ln in lines if (ln.extra_info or {}).get("movement") == "in"]
        
        # محاسبه هزینه مواد اولیه
        total_materials_cost = Decimal(0)
        for line in out_lines:
            if not line.product_id:
                continue
            product = db.query(Product).filter(Product.id == line.product_id).first()
            if not product:
                continue
            
            qty = Decimal(str(line.quantity or 0))
            cost_per_unit = _get_cost_per_unit_by_basis(
                db, business_id, product, line, calculation_basis,
                document.document_date, line.warehouse_id
            )
            total_materials_cost += qty * cost_per_unit
        
        # دریافت هزینه عملیات
        extra_info = document.extra_info or {}
        operations_total = Decimal(str(extra_info.get("production_operations_total", 0) or 0))
        
        # هزینه کل تولید
        total_production_cost = total_materials_cost + operations_total
        
        # محاسبه سود برای محصولات نهایی
        for line in in_lines:
            if not line.product_id:
                continue
            
            product = db.query(Product).filter(Product.id == line.product_id).first()
            if not product:
                continue
            
            qty = Decimal(str(line.quantity or 0))
            unit_price = Decimal(str(product.base_sales_price or 0))
            sales_amount = qty * unit_price
            
            # توزیع هزینه تولید
            if len(in_lines) > 0:
                line_cost = total_production_cost / len(in_lines)
            else:
                line_cost = Decimal(0)
            
            line_gross_profit = sales_amount - line_cost
            line_gross_profit_percent = (line_gross_profit / sales_amount * 100) if sales_amount > 0 else Decimal(0)
            
            total_gross_profit += line_gross_profit
            total_sales += sales_amount
            
            line_profits.append({
                "line_id": line.id,
                "product_id": product.id,
                "product_code": product.code,
                "product_name": product.name,
                "quantity": float(qty),
                "unit_price": float(unit_price),
                "cost_per_unit": float(line_cost / qty) if qty > 0 else 0,
                "sales_amount": float(sales_amount),
                "total_cost": float(line_cost),
                "gross_profit": float(line_gross_profit),
                "gross_profit_percent": float(line_gross_profit_percent),
                "net_profit": float(line_gross_profit),
                "net_profit_percent": float(line_gross_profit_percent),
                "overhead": 0.0
            })
        
        total_overhead = Decimal(0)
        if include_overhead and overhead_type != "production_overhead":
            total_overhead = _calculate_overhead_cost(
                db, business_id, document.id, total_production_cost,
                overhead_type, overhead_percent
            )
        
        total_net_profit = total_gross_profit - total_overhead
    
    # برای فاکتورهای فروش
    elif document.document_type in ["invoice_sales", "invoice_sales_return"]:
        # دریافت ردیف‌های فاکتور از InvoiceItemLine (برای فاکتورهای فروش)
        item_lines = db.query(InvoiceItemLine).filter(InvoiceItemLine.document_id == document_id).all()
        
        for item_line in item_lines:
            if not item_line.product_id:
                continue
            
            product = db.query(Product).filter(Product.id == item_line.product_id).first()
            if not product:
                continue
            
            # خواندن اطلاعات از extra_info
            extra_info = item_line.extra_info or {}
            qty = Decimal(str(item_line.quantity or 0))
            unit_price = Decimal(str(extra_info.get("unit_price", 0) or 0))
            line_discount = Decimal(str(extra_info.get("line_discount", 0) or 0))
            warehouse_id = extra_info.get("warehouse_id")
            
            # محاسبه مبلغ فروش (بعد از تخفیف، بدون مالیات)
            # توجه: برای محاسبه سود، از مبلغ بدون مالیات استفاده می‌کنیم
            # چون مالیات جزء درآمد نیست و باید جداگانه محاسبه شود
            sales_amount = (qty * unit_price) - line_discount
            
            # محاسبه هزینه هر واحد - استفاده مستقیم از extra_info
            cost_per_unit = Decimal(0)
            if calculation_basis == "purchase_price":
                # اگر قیمت خرید صفر یا None باشد، باید از cost_price در extra_info استفاده کنیم
                base_cost = product.base_purchase_price or 0
                if base_cost == 0 and extra_info.get("cost_price") is not None:
                    base_cost = extra_info.get("cost_price")
                cost_per_unit = Decimal(str(base_cost))
            elif calculation_basis == "cost_price":
                if extra_info.get("cost_price") is not None:
                    cost_per_unit = Decimal(str(extra_info.get("cost_price")))
                else:
                    cost_per_unit = Decimal(str(product.base_purchase_price or 0))
            elif calculation_basis == "actual_cost":
                if extra_info.get("cost_price") is not None:
                    cost_per_unit = Decimal(str(extra_info.get("cost_price")))
                elif extra_info.get("cogs_amount") is not None and qty > 0:
                    cost_per_unit = Decimal(str(extra_info.get("cogs_amount"))) / qty
                else:
                    cost_per_unit = Decimal(str(product.base_purchase_price or 0))
            elif calculation_basis == "average_cost":
                cost_per_unit = _calculate_average_purchase_cost(db, business_id, product.id, document.document_date)
            elif calculation_basis == "fifo":
                cost_per_unit = _calculate_fifo_cost(db, business_id, product.id, qty, document.document_date, warehouse_id)
            elif calculation_basis == "lifo":
                cost_per_unit = _calculate_lifo_cost(db, business_id, product.id, qty, document.document_date, warehouse_id)
            elif calculation_basis == "weighted_average":
                cost_per_unit = _calculate_weighted_average_cost(db, business_id, product.id, document.document_date)
            elif calculation_basis == "standard_cost":
                if extra_info.get("standard_cost") is not None:
                    cost_per_unit = Decimal(str(extra_info.get("standard_cost")))
                else:
                    cost_per_unit = Decimal(str(product.base_purchase_price or 0))
            else:
                cost_per_unit = Decimal(str(product.base_purchase_price or 0))
            
            total_line_cost = qty * cost_per_unit
            
            # محاسبه سود ناخالص ردیف
            line_gross_profit = sales_amount - total_line_cost
            line_gross_profit_percent = (line_gross_profit / sales_amount * 100) if sales_amount > 0 else Decimal(0)
            
            # محاسبه هزینه سربار برای این ردیف
            line_overhead = Decimal(0)
            if include_overhead:
                line_overhead = _calculate_overhead_cost(
                    db, business_id, document_id, total_line_cost,
                    overhead_type, overhead_percent
                ) / len(item_lines) if len(item_lines) > 0 else Decimal(0)
            
            # محاسبه سود خالص ردیف
            line_net_profit = line_gross_profit - line_overhead
            line_net_profit_percent = (line_net_profit / sales_amount * 100) if sales_amount > 0 else Decimal(0)
            
            total_gross_profit += line_gross_profit
            total_net_profit += line_net_profit
            total_sales += sales_amount
            total_cost += total_line_cost
            
            line_profits.append({
                "line_id": item_line.id,
                "product_id": product.id,
                "product_code": product.code,
                "product_name": product.name,
                "quantity": float(qty),
                "unit_price": float(unit_price),
                "cost_per_unit": float(cost_per_unit),
                "sales_amount": float(sales_amount),
                "total_cost": float(total_line_cost),
                "gross_profit": float(line_gross_profit),
                "net_profit": float(line_net_profit),
                "gross_profit_percent": float(line_gross_profit_percent),
                "net_profit_percent": float(line_net_profit_percent),
                "overhead": float(line_overhead)
            })
        
        # محاسبه هزینه سربار کل
        total_overhead = Decimal(0)
        if include_overhead:
            total_overhead = _calculate_overhead_cost(
                db, business_id, document_id, total_cost,
                overhead_type, overhead_percent
            )
            total_net_profit = total_gross_profit - total_overhead
    
    # محاسبه درصد سود
    gross_profit_percent = (total_gross_profit / total_sales * 100) if total_sales > 0 else Decimal(0)
    net_profit_percent = (total_net_profit / total_sales * 100) if total_sales > 0 else Decimal(0)
    
    # ساخت response
    result = {
        "total_overhead": float(total_overhead),
        "line_profits": line_profits
    }
    
    if calculation_type in ["gross", "both"]:
        result["gross_profit"] = float(total_gross_profit)
        result["gross_profit_percent"] = float(gross_profit_percent)
    
    if calculation_type in ["net", "both"]:
        result["net_profit"] = float(total_net_profit)
        result["net_profit_percent"] = float(net_profit_percent)
    
    # برای سازگاری با کد قدیم
    if calculation_type == "gross":
        result["total_profit"] = result["gross_profit"]
        result["total_profit_percent"] = result["gross_profit_percent"]
    elif calculation_type == "net":
        result["total_profit"] = result["net_profit"]
        result["total_profit_percent"] = result["net_profit_percent"]
    
    return result


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

    # اعتبارسنجی ویژه برای فاکتور تولید
    if invoice_type == INVOICE_PRODUCTION:
        has_out = False
        has_in = False
        
        for i, line in enumerate(lines_input, start=1):
            extra_info = line.get("extra_info") or {}
            movement = extra_info.get("movement")
            
            if movement is None or (movement != "in" and movement != "out"):
                raise ApiError(
                    "INVALID_PRODUCTION_LINE",
                    f"ردیف {i} باید movement مشخص داشته باشد ('in' یا 'out'). برای فاکتور تولید، باید از فرمول تولید استفاده کنید.",
                    http_status=400
                )
            
            if movement == "out":
                has_out = True
            elif movement == "in":
                has_in = True
        
        if not has_out:
            raise ApiError(
                "INVALID_PRODUCTION_INVOICE",
                "فاکتور تولید باید حداقل یک ردیف با movement: 'out' داشته باشد (مواد اولیه). برای فاکتور تولید، باید از فرمول تولید استفاده کنید.",
                http_status=400
            )
        
        if not has_in:
            raise ApiError(
                "INVALID_PRODUCTION_INVOICE",
                "فاکتور تولید باید حداقل یک ردیف با movement: 'in' داشته باشد (محصول نهایی). برای فاکتور تولید، باید از فرمول تولید استفاده کنید.",
                http_status=400
            )
        
        # بررسی وجود bom_ids در extra_info فاکتور (برای ردیابی)
        header_extra_check = data.get("extra_info") or {}
        bom_ids = header_extra_check.get("bom_ids")
        if not bom_ids or not isinstance(bom_ids, list) or len(bom_ids) == 0:
            raise ApiError(
                "BOM_REQUIRED",
                "برای فاکتور تولید، باید حداقل یک فرمول تولید را منفجر کنید. فاکتور تولید بدون فرمول تولید قابل ثبت نیست.",
                http_status=400
            )
        
        # اعتبارسنجی خروجی‌های فرمول تولید
        # جمع‌آوری product_id های موجود در ردیف‌های فاکتور با movement='in'
        output_product_ids_in_invoice = set()
        for line in lines_input:
            extra_info = line.get("extra_info") or {}
            movement = extra_info.get("movement")
            if movement == "in":
                product_id = line.get("product_id")
                if product_id:
                    output_product_ids_in_invoice.add(int(product_id))
        
        # بررسی برای هر فرمول تولید
        for bom_id in bom_ids:
            try:
                bom_id_int = int(bom_id)
            except (ValueError, TypeError):
                continue
            
            # دریافت فرمول تولید
            bom = db.get(ProductBOM, bom_id_int)
            if not bom or bom.business_id != business_id:
                continue
            
            # دریافت خروجی‌های فرمول
            bom_outputs = db.query(ProductBOMOutput).filter(
                ProductBOMOutput.bom_id == bom_id_int
            ).all()
            
            if not bom_outputs:
                # اگر فرمول خروجی ندارد، هشدار می‌دهیم اما خطا نمی‌دهیم
                logger.warning(f"فرمول تولید {bom_id_int} (کالا: {bom.product_id}) هیچ خروجی تعریف نشده است")
                continue
            
            # بررسی اینکه product_id فرمول در خروجی‌ها باشد
            bom_product_in_outputs = any(
                output.output_product_id == bom.product_id 
                for output in bom_outputs
            )
            if not bom_product_in_outputs:
                logger.warning(
                    f"کالای فرمول تولید {bom_id_int} (product_id: {bom.product_id}) "
                    f"در خروجی‌های فرمول تعریف نشده است. این ممکن است باعث سردرگمی شود."
                )
            
            # بررسی اینکه همه خروجی‌های فرمول در فاکتور وجود داشته باشند
            missing_outputs = []
            for output in bom_outputs:
                if output.output_product_id not in output_product_ids_in_invoice:
                    # دریافت نام کالا برای پیام خطا
                    output_product = db.get(Product, output.output_product_id)
                    product_name = output_product.name if output_product else f"کالا #{output.output_product_id}"
                    missing_outputs.append(product_name)
            
            if missing_outputs:
                missing_names = "، ".join(missing_outputs)
                raise ApiError(
                    "MISSING_BOM_OUTPUTS",
                    f"خروجی‌های فرمول تولید '{bom.name}' (نسخه: {bom.version}) که در فاکتور وجود ندارند: {missing_names}. "
                    f"لطفاً همه خروجی‌های فرمول تولید را در فاکتور شامل کنید.",
                    http_status=400
                )

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
                    disable_pagination=True,
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

    product_tax_map = _build_product_tax_snapshot_map(db, business_id, all_product_ids)

    for ln in lines_input:
        pid = ln.get("product_id")
        if not pid:
            continue
        info = dict(ln.get("extra_info") or {})
        info["inventory_tracked"] = bool(track_map.get(int(pid), False))
        tax_meta = product_tax_map.get(int(pid))
        if tax_meta:
            snapshot = {k: v for k, v in tax_meta.items() if v is not None}
            snapshot["captured_at"] = datetime.utcnow().isoformat()
            info["tax_snapshot"] = snapshot
        ln["extra_info"] = info
    # انبار از فاکتور جدا شده است؛ انتخاب انبار در فاکتور اجباری نیست


    # بدون کنترل کسری در مرحله فاکتور؛ کنترل در پست حواله انجام می‌شود

    # Costing method (only for tracked products)
    costing_method = _get_costing_method(data)
    # محاسبه COGS به پست حواله منتقل می‌شود

    gross = Decimal(str(totals["gross"]))
    discount = Decimal(str(totals["discount"]))
    net = gross - discount
    tax = Decimal(str(totals["tax"]))
    total_with_tax = net + tax

    ensure_document_policy_allows_creation(
        db,
        business_id,
        document_type=invoice_type,
        document_date=document_date,
        amount=abs(total_with_tax),
    )

    # Enrich extra_info (نرمال‌سازی person_id و سایر فیلدهای عددی برای ذخیره یکسان در دیتابیس)
    new_extra_info = _normalize_document_extra_info_for_storage(dict(header_extra)) or {}
    new_extra_info["totals"] = {
        "gross": float(Decimal(str(totals["gross"]))),
        "discount": float(Decimal(str(totals["discount"]))),
        "tax": float(Decimal(str(totals["tax"]))),
        "net": float(Decimal(str(totals["net"]))),
    }

    # Create document با کنترل رقابت در شماره‌گذاری
    from app.services.document_numbering_service import generate_document_code

    document: Optional[Document] = None
    max_code_attempts = 5
    
    # دریافت project_id (اختیاری)
    project_id = data.get("project_id")
    if project_id:
        # اعتبارسنجی پروژه
        from adapters.db.models.project import Project
        project = db.query(Project).filter(
            and_(Project.id == project_id, Project.business_id == business_id, Project.is_active == True)
        ).first()
        if not project:
            raise ApiError("PROJECT_NOT_FOUND", "پروژه یافت نشد یا غیرفعال است", http_status=404)
    
    for attempt in range(max_code_attempts):
        doc_code = generate_document_code(db, business_id, invoice_type, document_date)
        candidate = Document(
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
            project_id=project_id,
        )
        try:
            with db.begin_nested():
                db.add(candidate)
                db.flush()
        except IntegrityError as exc:
            # اگر به دلیل تکرار کد شکست خورد، دوباره تلاش کن
            msg = str(getattr(exc.orig, "args", exc))
            if "uq_documents_business_code" in msg or "Duplicate entry" in msg:
                continue
            raise
        else:
            document = candidate
            break

    if not document:
        raise ApiError(
            "DOCUMENT_CODE_RACE",
            "تولید شماره سند پس از چند تلاش ناموفق بود. لطفاً دوباره تلاش کنید.",
            http_status=409,
        )

    # ذخیره اقلام فاکتور در جدول مجزا (invoice_item_lines)
    for line in lines_input:
        product_id = line.get("product_id")
        qty = Decimal(str(line.get("quantity", 0) or 0))
        if not product_id or qty <= 0:
            raise ApiError("INVALID_LINE", "line.product_id and positive quantity are required", http_status=400)
        extra_info = dict(line.get("extra_info") or {})
        extra_info.pop("inventory_posted", None)
        
        # اعتبارسنجی selected_instance_ids برای کالاهای یونیک
        selected_instance_ids = extra_info.get("selected_instance_ids")
        if selected_instance_ids:
            _validate_selected_instances(
                db, business_id, int(product_id), selected_instance_ids, int(qty), invoice_type
            )
        
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
                document.extra_info = _normalize_document_extra_info_for_storage(extra)
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
            # برای این انواع، ثبت‌های موجودی و بهای تمام‌شده در فاکتور انجام می‌شود
            # (نه فقط در پست حواله)
            
            if invoice_type == INVOICE_DIRECT_CONSUMPTION:
                # محاسبه COGS برای مصرف مستقیم
                total_cogs = _extract_cogs_total_for_invoice(lines_input)
                
                if total_cogs > 0:
                    # بدهکار: هزینه مصرف مستقیم
                    db.add(DocumentLine(
                        document_id=document.id,
                        account_id=accounts["direct_consumption"].id,
                        debit=total_cogs,
                        credit=Decimal(0),
                        description="هزینه مصرف مستقیم کالا",
                    ))
                    
                    # بستانکار: موجودی کالا
                    db.add(DocumentLine(
                        document_id=document.id,
                        account_id=accounts["inventory"].id,
                        debit=Decimal(0),
                        credit=total_cogs,
                        description="خروج کالا از موجودی (مصرف مستقیم)",
                    ))
            
            elif invoice_type == INVOICE_WASTE:
                # محاسبه COGS برای ضایعات
                total_cogs = _extract_cogs_total_for_invoice(lines_input)
                
                if total_cogs > 0:
                    # بدهکار: هزینه ضایعات
                    db.add(DocumentLine(
                        document_id=document.id,
                        account_id=accounts["waste_expense"].id,
                        debit=total_cogs,
                        credit=Decimal(0),
                        description="هزینه کسری و ضایعات کالا",
                    ))
                    
                    # بستانکار: موجودی کالا
                    db.add(DocumentLine(
                        document_id=document.id,
                        account_id=accounts["inventory"].id,
                        debit=Decimal(0),
                        credit=total_cogs,
                        description="خروج کالا از موجودی (ضایعات)",
                    ))
            
            elif invoice_type == INVOICE_PRODUCTION:
                # جداسازی خطوط ورودی و خروجی
                out_lines = [ln for ln in lines_input if (ln.get("extra_info") or {}).get("movement") == "out"]
                in_lines = [ln for ln in lines_input if (ln.get("extra_info") or {}).get("movement") == "in"]
                
                # محاسبه COGS برای مواد اولیه (خروج)
                total_materials_cost = _extract_cogs_total_for_invoice(out_lines)

                # هزینه عملیات/سربار تولید (در صورت ارسال از UI)
                try:
                    operations_total = Decimal(str((header_extra or {}).get("production_operations_total", 0) or 0))
                except Exception:
                    operations_total = Decimal(0)
                
                # محاسبه مجموع هزینه تمام‌شده (مواد اولیه + هزینه عملیات)
                total_production_cost = total_materials_cost + operations_total
                
                # محاسبه مجموع تعداد محصولات نهایی برای توزیع هزینه
                total_output_quantity = Decimal(0)
                for line in in_lines:
                    qty = Decimal(str(line.get("quantity", 0) or 0))
                    if qty > 0:
                        total_output_quantity += qty
                
                # محاسبه هزینه محصول نهایی (ورود)
                # ابتدا بررسی می‌کنیم که آیا cost_price دستی ارسال شده است یا نه
                total_finished_cost = Decimal(0)
                total_manual_cost = Decimal(0)  # مجموع هزینه‌های دستی
                remaining_quantity = Decimal(0)  # مجموع تعداد محصولاتی که cost_price دستی ندارند
                
                # مرحله 1: محاسبه هزینه‌های دستی (cost_price از extra_info)
                for line in in_lines:
                    extra_info = line.get("extra_info") or {}
                    qty = Decimal(str(line.get("quantity", 0) or 0))
                    if qty <= 0:
                        continue
                    
                    if extra_info.get("cost_price") is not None:
                        # استفاده از cost_price دستی
                        cost_line = qty * Decimal(str(extra_info.get("cost_price")))
                        total_manual_cost += cost_line
                        total_finished_cost += cost_line
                    else:
                        # این خط نیاز به محاسبه خودکار دارد
                        remaining_quantity += qty
                
                # مرحله 2: محاسبه خودکار برای خطوطی که cost_price ندارند
                if remaining_quantity > 0:
                    remaining_cost = total_production_cost - total_manual_cost
                    if remaining_cost < 0:
                        remaining_cost = Decimal(0)
                    cost_per_unit = remaining_cost / remaining_quantity if remaining_quantity > 0 else Decimal(0)
                    
                    for line in in_lines:
                        extra_info = line.get("extra_info") or {}
                        qty = Decimal(str(line.get("quantity", 0) or 0))
                        if qty > 0 and extra_info.get("cost_price") is None:
                            cost_line = qty * cost_per_unit
                            total_finished_cost += cost_line
                
                # مرحله 3: اعتبارسنجی توازن WIP
                # اگر همه خطوط cost_price دستی دارند، باید بررسی کنیم که توازن برقرار است
                if remaining_quantity == 0 and total_output_quantity > 0:
                    # همه خطوط cost_price دستی دارند
                    total_wip_debit = total_materials_cost + operations_total
                    total_wip_credit = total_finished_cost
                    balance_diff = abs(total_wip_debit - total_wip_credit)
                    tolerance = Decimal("0.01")
                    
                    if balance_diff > tolerance:
                        # توازن برقرار نیست، باید cost_price را اصلاح کنیم
                        # محاسبه خودکار بر اساس کل هزینه و تعداد کل
                        cost_per_unit = total_production_cost / total_output_quantity if total_output_quantity > 0 else Decimal(0)
                        total_finished_cost = Decimal(0)
                        for line in in_lines:
                            qty = Decimal(str(line.get("quantity", 0) or 0))
                            if qty > 0:
                                total_finished_cost += qty * cost_per_unit
                
                # اعتبارسنجی نهایی توازن WIP
                total_wip_debit = total_materials_cost + operations_total
                total_wip_credit = total_finished_cost
                balance_diff = abs(total_wip_debit - total_wip_credit)
                tolerance = Decimal("0.01")
                
                if balance_diff > tolerance:
                    # اگر هنوز توازن برقرار نیست، خطا می‌دهیم
                    raise ApiError(
                        "PRODUCTION_COST_MISMATCH",
                        f"عدم توازن در حساب WIP. بدهکار: {total_wip_debit:,.0f}, بستانکار: {total_wip_credit:,.0f}, اختلاف: {balance_diff:,.0f}",
                        http_status=400
                    )
                
                # ثبت حسابداری برای مواد اولیه (خروج)
                if total_materials_cost > 0:
                    # بدهکار: WIP
                    db.add(DocumentLine(
                        document_id=document.id,
                        account_id=accounts["wip"].id,
                        debit=total_materials_cost,
                        credit=Decimal(0),
                        description="انتقال مواد اولیه به WIP",
                    ))
                    
                    # بستانکار: موجودی کالا
                    db.add(DocumentLine(
                        document_id=document.id,
                        account_id=accounts["inventory"].id,
                        debit=Decimal(0),
                        credit=total_materials_cost,
                        description="خروج مواد اولیه از موجودی",
                    ))

                # ثبت حسابداری هزینه عملیات/سربار تولید: بدهکار WIP / بستانکار حساب سربار
                if operations_total > 0:
                    db.add(DocumentLine(
                        document_id=document.id,
                        account_id=accounts["wip"].id,
                        debit=operations_total,
                        credit=Decimal(0),
                        description="هزینه عملیات تولید (انتقال به WIP)",
                        extra_info={"source": "production_operations"},
                    ))
                    db.add(DocumentLine(
                        document_id=document.id,
                        account_id=accounts["production_overhead"].id,
                        debit=Decimal(0),
                        credit=operations_total,
                        description="هزینه عملیات/سربار تولید",
                        extra_info={"source": "production_operations"},
                    ))
                
                # ثبت حسابداری برای محصول نهایی (ورود)
                if total_finished_cost > 0:
                    # بدهکار: موجودی کالا
                    db.add(DocumentLine(
                        document_id=document.id,
                        account_id=accounts["inventory"].id,
                        debit=total_finished_cost,
                        credit=Decimal(0),
                        description="ورود محصول نهایی به موجودی",
                    ))
                    
                    # بستانکار: WIP
                    db.add(DocumentLine(
                        document_id=document.id,
                        account_id=accounts["wip"].id,
                        debit=Decimal(0),
                        credit=total_finished_cost,
                        description="انتقال محصول نهایی از WIP",
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

    # همگام‌سازی قیمت پایه کالا (ارز پیش‌فرض کسب‌وکار) از فاکتور قطعی
    # Session با autoflush=False است؛ بدون flush، کوئری invoice_item_lines خالی می‌ماند.
    if not document.is_proforma:
        db.flush()
        from adapters.db.models.business import Business as _BizForPriceSync
        _biz_ps = db.query(_BizForPriceSync).filter(_BizForPriceSync.id == business_id).first()
        if _biz_ps:
            from app.services.invoice_product_price_sync_service import apply_invoice_product_price_sync
            apply_invoice_product_price_sync(db, _biz_ps, document, invoice_type)

    # Persist invoice first
    db.commit()
    db.refresh(document)

    # Optional: create receipt/payment document(s)
    payment_docs: List[int] = []
    payments = data.get("payments") or []
    
    # بررسی تنظیمات auto_create_payment_document برای فروش سریع
    extra_info_all = data.get("extra_info") or {}
    auto_create_payment_doc = extra_info_all.get("auto_create_payment_document", True)
    is_quick_sale = extra_info_all.get("quick_sale", False)
    
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
                                
                                # بررسی تطابق نوع چک با نوع فاکتور
                                # چک دریافتی فقط در فاکتور فروش/برگشت از فروش استفاده می‌شود
                                # چک پرداختی فقط در فاکتور خرید/برگشت از خرید استفاده می‌شود
                                is_receipt_invoice = invoice_type in {INVOICE_SALES, INVOICE_PURCHASE_RETURN}
                                expected_check_type = CheckType.RECEIVED if is_receipt_invoice else CheckType.TRANSFERRED
                                
                                if chk.type != expected_check_type:
                                    check_type_name = "دریافتی" if chk.type == CheckType.RECEIVED else "پرداختی"
                                    expected_type_name = "دریافتی" if expected_check_type == CheckType.RECEIVED else "پرداختی"
                                    invoice_type_name = "فروش/برگشت از فروش" if is_receipt_invoice else "خرید/برگشت از خرید"
                                    raise ApiError(
                                        "CHECK_TYPE_MISMATCH_WITH_INVOICE",
                                        f"نوع چک با نوع فاکتور هم‌خوانی ندارد. چک {check_type_name} نمی‌تواند در فاکتور {invoice_type_name} استفاده شود. باید چک {expected_type_name} استفاده شود.",
                                        http_status=400
                                    )

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
                    # اگر auto_create_payment_document غیرفعال باشد و فروش سریع باشد، سند پرداخت جداگانه ایجاد نکن
                    if is_quick_sale and not auto_create_payment_doc:
                        logger.info(f"Skipping auto-create payment document for quick sale invoice {document.id} (auto_create_payment_document is False)")
                    else:
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
        # به‌روزرسانی extra_info (نرمال‌سازی برای ذخیره یکسان)
        document.extra_info = _normalize_document_extra_info_for_storage(extra)
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

    # ایجاد حواله انبار در صورت نیاز (بر اساس تنظیمات enable_warehouse_document)
    # post_inventory: تعیین می‌کند که آیا اصلاً حواله ایجاد شود یا نه
    # auto_post_warehouse: تعیین می‌کند که آیا حواله بلافاصله قطعی شود (posted) یا به صورت پیش‌نویس (draft) بماند
    try:
        if bool(data.get("extra_info", {}).get("post_inventory", True)):
            from app.services.warehouse_service import create_from_invoice, post_warehouse_document
            from adapters.db.models.product_instance import ProductInstance
            from adapters.db.models.warehouse_document import WarehouseDocument
            
            created_wh_ids: List[int] = []
            auto_post_warehouse = bool(data.get("extra_info", {}).get("auto_post_warehouse", False))
            
            if invoice_type == INVOICE_PRODUCTION:
                out_lines = [ln for ln in lines_input if (ln.get("extra_info") or {}).get("movement") == "out"]
                in_lines = [ln for ln in lines_input if (ln.get("extra_info") or {}).get("movement") == "in"]
                if out_lines:
                    wh_issue = create_from_invoice(db, business_id, document, out_lines, "issue", user_id)
                    created_wh_ids.append(int(wh_issue.id))
                    if auto_post_warehouse:
                        post_warehouse_document(db, int(wh_issue.id))
                if in_lines:
                    wh_receipt = create_from_invoice(db, business_id, document, in_lines, "receipt", user_id)
                    created_wh_ids.append(int(wh_receipt.id))
                    if auto_post_warehouse:
                        post_warehouse_document(db, int(wh_receipt.id))
            else:
                if invoice_type in {INVOICE_SALES, INVOICE_PURCHASE_RETURN, INVOICE_WASTE, INVOICE_DIRECT_CONSUMPTION}:
                    wh_type = "issue"
                elif invoice_type in {INVOICE_PURCHASE, INVOICE_SALES_RETURN}:
                    wh_type = "receipt"
                else:
                    wh_type = "issue"
                wh = create_from_invoice(db, business_id, document, lines_input, wh_type, user_id)
                created_wh_ids.append(int(wh.id))
                
                # قطعی خودکار حواله در صورت فعال بودن
                if auto_post_warehouse:
                    post_warehouse_document(db, int(wh.id))
                    
                    # به‌روزرسانی وضعیت کالاهای یونیک برای فاکتورهای فروش
                    if invoice_type == INVOICE_SALES:
                        for line in lines_input:
                            instance_id = (line.get("extra_info") or {}).get("instance_id")
                            if instance_id:
                                instance = db.query(ProductInstance).filter(
                                    ProductInstance.id == int(instance_id),
                                    ProductInstance.business_id == business_id,
                                ).first()
                                if instance:
                                    instance.status = "sold"
                                    instance.current_invoice_id = document.id
                                    # انبار را null می‌کنیم چون کالا فروخته شده
                                    instance.warehouse_id = None
                                    db.flush()

            if created_wh_ids:
                # ذخیره لینک حواله‌ها در extra_info.links
                extra = document.extra_info or {}
                links = dict((extra.get("links") or {}))
                links["warehouse_document_ids"] = created_wh_ids
                extra["links"] = links
                document.extra_info = _normalize_document_extra_info_for_storage(extra)
                flag_modified(document, "extra_info")
                db.commit()
    except Exception as ex:
        # عدم موفقیت در ساخت حواله نباید مانع بازگشت فاکتور شود
        # فاکتور قبلاً commit شده است، پس فقط exception را log می‌کنیم
        logger.exception(f"Failed to create warehouse document for invoice {document.id}: {ex}")
        # فقط تغییرات uncommitted را rollback می‌کنیم (نه فاکتور commit شده)
        try:
            db.rollback()
        except Exception:
            pass

    # فراخوانی workflow triggers برای فاکتور ایجاد شده
    try:
        from app.services.workflow.workflow_trigger_service import trigger_invoice_created
        trigger_invoice_created(
            db=db,
            business_id=business_id,
            invoice_id=document.id,
            invoice_type=invoice_type,
            total_amount=float(total_with_tax),
            user_id=user_id
        )
    except Exception as e:
        # عدم موفقیت در trigger نباید مانع بازگشت فاکتور شود
        logger.warning(f"Failed to trigger workflows for invoice {document.id}: {e}")

    result = invoice_document_to_dict(db, document)
    
    # Invalidate cache بعد از ایجاد موفق فاکتور
    invalidate_invoices_cache(
        business_id=business_id,
        fiscal_year_id=document.fiscal_year_id,
        invoice_id=document.id,
        document_type=document.document_type,
        project_id=document.project_id
    )
    
    # همچنین اسناد عمومی را هم invalidate کن (چون فاکتورها از Document ارث‌بری دارند)
    from app.services.document_service import invalidate_documents_cache
    invalidate_documents_cache(
        business_id=business_id,
        fiscal_year_id=document.fiscal_year_id,
        document_id=document.id,
        document_type=document.document_type
    )
    
    # اگر expense/income باشد، cache آن را هم invalidate کن
    if document.document_type in ['expense', 'income']:
        from app.services.expense_income_service import invalidate_expense_income_cache
        invalidate_expense_income_cache(
            business_id=business_id,
            fiscal_year_id=document.fiscal_year_id,
            document_id=document.id
        )
    
    return result


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
    # به‌روزرسانی پروژه
    if "project_id" in data:
        project_id = data.get("project_id")
        if project_id:
            from adapters.db.models.project import Project
            project = db.query(Project).filter(
                and_(Project.id == project_id, Project.business_id == document.business_id, Project.is_active == True)
            ).first()
            if not project:
                raise ApiError("PROJECT_NOT_FOUND", "پروژه یافت نشد یا غیرفعال است", http_status=404)
        document.project_id = project_id
    if isinstance(data.get("extra_info"), dict) or data.get("extra_info") is None:
        # merge extra_info: ابتدا old_extra را کپی کن، سپس new_extra را merge کن
        old_extra = dict(document.extra_info) if document.extra_info else {}
        new_extra = dict(data.get("extra_info") or {})
        # merge کردن: new_extra فیلدهای old_extra را override می‌کند؛ نرمال‌سازی برای ذخیره یکسان
        merged_extra = _normalize_document_extra_info_for_storage({**old_extra, **new_extra})
        document.extra_info = merged_extra
    if isinstance(data.get("description"), str) or data.get("description") is None:
        if data.get("description") is not None:
            document.description = data.get("description")

    # آزادسازی instance های قبلی این فاکتور (برای کالاهای یونیک)
    # قبل از حذف سطرها، instance های sold شده توسط این فاکتور را به حالت available برمی‌گردانیم
    from adapters.db.models.product_instance import ProductInstance
    try:
        old_invoice_lines = db.query(InvoiceItemLine).filter(
            InvoiceItemLine.document_id == document.id
        ).all()
        
        for old_line in old_invoice_lines:
            if old_line.extra_info:
                selected_ids = old_line.extra_info.get("selected_instance_ids")
                if selected_ids and isinstance(selected_ids, list):
                    # آزاد کردن instance هایی که به این فاکتور اختصاص داده شده بودند
                    db.query(ProductInstance).filter(
                        and_(
                            ProductInstance.id.in_([int(x) for x in selected_ids]),
                            ProductInstance.business_id == document.business_id,
                            ProductInstance.current_invoice_id == document.id,
                        )
                    ).update(
                        {
                            "status": "available",
                            "current_invoice_id": None,
                        },
                        synchronize_session=False
                    )
        db.flush()
    except Exception as e:
        # اگر خطایی رخ داد، فقط log می‌کنیم و ادامه می‌دهیم
        logger.warning(f"Failed to release instances for invoice {document.id}: {e}")
    
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
    product_tax_map = _build_product_tax_snapshot_map(db, document.business_id, all_product_ids)

    for ln in lines_input:
        pid = ln.get("product_id")
        if not pid:
            continue
        info = dict(ln.get("extra_info") or {})
        info["inventory_tracked"] = bool(track_map.get(int(pid), False))
        tax_meta = product_tax_map.get(int(pid))
        if tax_meta:
            snapshot = {k: v for k, v in tax_meta.items() if v is not None}
            snapshot["captured_at"] = datetime.utcnow().isoformat()
            info["tax_snapshot"] = snapshot
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
        
        # اعتبارسنجی selected_instance_ids برای کالاهای یونیک
        selected_instance_ids = extra_info.get("selected_instance_ids")
        if selected_instance_ids:
            _validate_selected_instances(
                db, document.business_id, int(product_id), selected_instance_ids, int(qty), inv_type
            )
        
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
        person_id = _resolve_and_validate_person_id(db, document.business_id, person_id)
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
                document.extra_info = _normalize_document_extra_info_for_storage(ex_new)
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
            # محاسبه COGS برای مصرف مستقیم
            total_cogs = _extract_cogs_total_for_invoice(lines_input)
            
            if total_cogs > 0:
                # بدهکار: هزینه مصرف مستقیم
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["direct_consumption"].id,
                    debit=total_cogs,
                    credit=Decimal(0),
                    description="هزینه مصرف مستقیم کالا",
                ))
                
                # بستانکار: موجودی کالا
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["inventory"].id,
                    debit=Decimal(0),
                    credit=total_cogs,
                    description="خروج کالا از موجودی (مصرف مستقیم)",
                ))
        elif inv_type == INVOICE_WASTE:
            # محاسبه COGS برای ضایعات
            total_cogs = _extract_cogs_total_for_invoice(lines_input)
            
            if total_cogs > 0:
                # بدهکار: هزینه ضایعات
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["waste_expense"].id,
                    debit=total_cogs,
                    credit=Decimal(0),
                    description="هزینه کسری و ضایعات کالا",
                ))
                
                # بستانکار: موجودی کالا
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["inventory"].id,
                    debit=Decimal(0),
                    credit=total_cogs,
                    description="خروج کالا از موجودی (ضایعات)",
                ))
        elif inv_type == INVOICE_PRODUCTION:
            # جداسازی خطوط ورودی و خروجی
            out_lines = [ln for ln in lines_input if (ln.get("extra_info") or {}).get("movement") == "out"]
            in_lines = [ln for ln in lines_input if (ln.get("extra_info") or {}).get("movement") == "in"]
            
            # محاسبه COGS برای مواد اولیه (خروج)
            total_materials_cost = _extract_cogs_total_for_invoice(out_lines)

            # هزینه عملیات/سربار تولید (در صورت ارسال از UI)
            operations_total_raw = (header_extra or {}).get("production_operations_total", 0)
            try:
                operations_total = Decimal(str(operations_total_raw or 0))
            except Exception:
                operations_total = Decimal(0)
            
            # محاسبه مجموع هزینه تمام‌شده (مواد اولیه + هزینه عملیات)
            total_production_cost = total_materials_cost + operations_total
            
            # محاسبه مجموع تعداد محصولات نهایی برای توزیع هزینه
            total_output_quantity = Decimal(0)
            for line in in_lines:
                qty = Decimal(str(line.get("quantity", 0) or 0))
                if qty > 0:
                    total_output_quantity += qty
            
            # محاسبه هزینه محصول نهایی (ورود)
            # ابتدا بررسی می‌کنیم که آیا cost_price دستی ارسال شده است یا نه
            total_finished_cost = Decimal(0)
            total_manual_cost = Decimal(0)  # مجموع هزینه‌های دستی
            remaining_quantity = Decimal(0)  # مجموع تعداد محصولاتی که cost_price دستی ندارند
            
            # مرحله 1: محاسبه هزینه‌های دستی (cost_price از extra_info)
            for line in in_lines:
                extra_info = line.get("extra_info") or {}
                qty = Decimal(str(line.get("quantity", 0) or 0))
                if qty <= 0:
                    continue
                
                if extra_info.get("cost_price") is not None:
                    # استفاده از cost_price دستی
                    cost_line = qty * Decimal(str(extra_info.get("cost_price")))
                    total_manual_cost += cost_line
                    total_finished_cost += cost_line
                else:
                    # این خط نیاز به محاسبه خودکار دارد
                    remaining_quantity += qty
            
            # مرحله 2: محاسبه خودکار برای خطوطی که cost_price ندارند
            if remaining_quantity > 0:
                remaining_cost = total_production_cost - total_manual_cost
                if remaining_cost < 0:
                    remaining_cost = Decimal(0)
                cost_per_unit = remaining_cost / remaining_quantity if remaining_quantity > 0 else Decimal(0)
                
                for line in in_lines:
                    extra_info = line.get("extra_info") or {}
                    qty = Decimal(str(line.get("quantity", 0) or 0))
                    if qty > 0 and extra_info.get("cost_price") is None:
                        cost_line = qty * cost_per_unit
                        total_finished_cost += cost_line
            
            # مرحله 3: اعتبارسنجی توازن WIP
            # اگر همه خطوط cost_price دستی دارند، باید بررسی کنیم که توازن برقرار است
            if remaining_quantity == 0 and total_output_quantity > 0:
                # همه خطوط cost_price دستی دارند
                total_wip_debit = total_materials_cost + operations_total
                total_wip_credit = total_finished_cost
                balance_diff = abs(total_wip_debit - total_wip_credit)
                tolerance = Decimal("0.01")
                
                if balance_diff > tolerance:
                    # توازن برقرار نیست، باید cost_price را اصلاح کنیم
                    # محاسبه خودکار بر اساس کل هزینه و تعداد کل
                    cost_per_unit = total_production_cost / total_output_quantity if total_output_quantity > 0 else Decimal(0)
                    total_finished_cost = Decimal(0)
                    for line in in_lines:
                        qty = Decimal(str(line.get("quantity", 0) or 0))
                        if qty > 0:
                            total_finished_cost += qty * cost_per_unit
            
            # اعتبارسنجی نهایی توازن WIP
            total_wip_debit = total_materials_cost + operations_total
            total_wip_credit = total_finished_cost
            balance_diff = abs(total_wip_debit - total_wip_credit)
            tolerance = Decimal("0.01")
            
            if balance_diff > tolerance:
                # اگر هنوز توازن برقرار نیست، خطا می‌دهیم
                raise ApiError(
                    "PRODUCTION_COST_MISMATCH",
                    f"عدم توازن در حساب WIP. بدهکار: {total_wip_debit:,.0f}, بستانکار: {total_wip_credit:,.0f}, اختلاف: {balance_diff:,.0f}",
                    http_status=400
                )
            
            # ثبت حسابداری برای مواد اولیه (خروج)
            if total_materials_cost > 0:
                # بدهکار: WIP
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["wip"].id,
                    debit=total_materials_cost,
                    credit=Decimal(0),
                    description="انتقال مواد اولیه به WIP",
                ))
                
                # بستانکار: موجودی کالا
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["inventory"].id,
                    debit=Decimal(0),
                    credit=total_materials_cost,
                    description="خروج مواد اولیه از موجودی",
                ))

            # ثبت حسابداری هزینه عملیات/سربار تولید: بدهکار WIP / بستانکار حساب سربار
            if operations_total > 0:
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["wip"].id,
                    debit=operations_total,
                    credit=Decimal(0),
                    description="هزینه عملیات تولید (انتقال به WIP)",
                    extra_info={"source": "production_operations"},
                ))
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["production_overhead"].id,
                    debit=Decimal(0),
                    credit=operations_total,
                    description="هزینه عملیات/سربار تولید",
                    extra_info={"source": "production_operations"},
                ))
            
            # ثبت حسابداری برای محصول نهایی (ورود)
            if total_finished_cost > 0:
                # بدهکار: موجودی کالا
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["inventory"].id,
                    debit=total_finished_cost,
                    credit=Decimal(0),
                    description="ورود محصول نهایی به موجودی",
                ))
                
                # بستانکار: WIP
                db.add(DocumentLine(
                    document_id=document.id,
                    account_id=accounts["wip"].id,
                    debit=Decimal(0),
                    credit=total_finished_cost,
                    description="انتقال محصول نهایی از WIP",
                ))

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
                                
                                # بررسی تطابق نوع چک با نوع فاکتور (در update)
                                # چک دریافتی فقط در فاکتور فروش/برگشت از فروش استفاده می‌شود
                                # چک پرداختی فقط در فاکتور خرید/برگشت از خرید استفاده می‌شود
                                is_receipt_invoice = inv_type in {INVOICE_SALES, INVOICE_PURCHASE_RETURN}
                                expected_check_type = CheckType.RECEIVED if is_receipt_invoice else CheckType.TRANSFERRED
                                
                                if chk.type != expected_check_type:
                                    check_type_name = "دریافتی" if chk.type == CheckType.RECEIVED else "پرداختی"
                                    expected_type_name = "دریافتی" if expected_check_type == CheckType.RECEIVED else "پرداختی"
                                    invoice_type_name = "فروش/برگشت از فروش" if is_receipt_invoice else "خرید/برگشت از خرید"
                                    raise ApiError(
                                        "CHECK_TYPE_MISMATCH_WITH_INVOICE",
                                        f"نوع چک با نوع فاکتور هم‌خوانی ندارد. چک {check_type_name} نمی‌تواند در فاکتور {invoice_type_name} استفاده شود. باید چک {expected_type_name} استفاده شود.",
                                        http_status=400
                                    )
                    
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
                    document.extra_info = _normalize_document_extra_info_for_storage(extra)
                    from sqlalchemy.orm.attributes import flag_modified
                    flag_modified(document, "extra_info")
        except Exception as ex:
            logger.exception("could not update receipt/payment for invoice: %s", ex)
            # حتی در صورت خطا، ادامه بده

    if not document.is_proforma:
        db.flush()
        from adapters.db.models.business import Business as _BizForPriceSyncU
        _biz_ps_u = db.query(_BizForPriceSyncU).filter(_BizForPriceSyncU.id == document.business_id).first()
        if _biz_ps_u:
            from app.services.invoice_product_price_sync_service import apply_invoice_product_price_sync
            apply_invoice_product_price_sync(db, _biz_ps_u, document, document.document_type)

    db.commit()
    db.refresh(document)
    result = invoice_document_to_dict(db, document)
    
    # Invalidate cache بعد از به‌روزرسانی موفق فاکتور
    invalidate_invoices_cache(
        business_id=document.business_id,
        fiscal_year_id=document.fiscal_year_id,
        invoice_id=document.id,
        document_type=document.document_type,
        project_id=document.project_id
    )
    
    # همچنین اسناد عمومی را هم invalidate کن (چون فاکتورها از Document ارث‌بری دارند)
    from app.services.document_service import invalidate_documents_cache
    invalidate_documents_cache(
        business_id=document.business_id,
        fiscal_year_id=document.fiscal_year_id,
        document_type=document.document_type
    )
    
    # اگر expense/income باشد، cache آن را هم invalidate کن
    if document.document_type in ['expense', 'income']:
        from app.services.expense_income_service import invalidate_expense_income_cache
        invalidate_expense_income_cache(
            business_id=document.business_id,
            fiscal_year_id=document.fiscal_year_id,
            document_id=document.id
        )
    
    return result


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
    logger.info(f"[DELETE_INVOICE] ===== Starting delete process for invoice {document_id} =====")
    try:
        document = db.query(Document).filter(Document.id == document_id).first()
        if not document:
            logger.error(f"[DELETE_INVOICE] Invoice {document_id} not found")
            raise ApiError("DOCUMENT_NOT_FOUND", "Invoice document not found", http_status=404)
        
        logger.info(f"[DELETE_INVOICE] Invoice {document_id}: Found document - code={document.code}, type={document.document_type}, business_id={document.business_id}")
        
        # بررسی نوع سند
        if document.document_type not in SUPPORTED_INVOICE_TYPES:
            logger.error(f"[DELETE_INVOICE] Invoice {document_id}: Invalid document type {document.document_type}")
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
        
        # 3) بررسی کارپوشه مودیان
        try:
            extra_info = document.extra_info or {}
            tax_workspace = bool(extra_info.get("tax_workspace"))
            tax_status = extra_info.get("tax_status", "")
            logger.info(f"[DELETE_INVOICE] Invoice {document_id}: Tax workspace check - in_workspace={tax_workspace}, status={tax_status}")
            
            if tax_workspace:
                logger.error(f"[DELETE_INVOICE] Invoice {document_id}: Cannot delete - invoice is in tax workspace")
                raise ApiError(
                    "TAX_WORKSPACE_INVOICE",
                    "این فاکتور در کارپوشه سامانه مودیان قرار دارد و قابل حذف نمی‌باشد",
                    http_status=409,
                )
        except ApiError:
            raise
        except Exception as ex:
            logger.warning(f"[DELETE_INVOICE] Invoice {document_id}: Error checking tax workspace: {ex}")
            pass
        
        # 3.5) جلوگیری از حذف اگر سند به تراکنش‌های کیف پول مرتبط باشد
        try:
            from app.services.wallet_service import check_document_has_wallet_transactions
            wallet_check = check_document_has_wallet_transactions(db, document_id)
            if wallet_check["has_wallet_transactions"] and wallet_check.get("has_protected_transactions", False):
                logger.error(f"[DELETE_INVOICE] Invoice {document_id}: Cannot delete - has wallet transactions")
                raise ApiError(
                    "DOCUMENT_HAS_WALLET_TRANSACTIONS",
                    wallet_check["message"],
                    http_status=409,
                )
        except ApiError:
            raise
        except Exception as ex:
            logger.warning(f"[DELETE_INVOICE] Invoice {document_id}: Error checking wallet transactions: {ex}")
            pass
        
        # 4) بررسی و حذف حواله‌های انبار مرتبط و اسناد دریافت/پرداخت
        # همه عملیات در یک transaction انجام می‌شوند و در صورت خطا rollback می‌شود
        extra_info = document.extra_info or {}
        links = extra_info.get("links") or {}
        logger.info(f"[DELETE_INVOICE] Invoice {document_id}: Extra info links: {links}")
        
        # بررسی و حذف حواله‌های انبار (همه انواع: draft و finalized)
        warehouse_document_ids = links.get("warehouse_document_ids") or []
        if warehouse_document_ids:
            try:
                from adapters.db.models.warehouse_document import WarehouseDocument
                from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
                warehouse_docs = db.query(WarehouseDocument).filter(
                    WarehouseDocument.id.in_(warehouse_document_ids)
                ).all()
                logger.info(f"[DELETE_INVOICE] Invoice {document_id}: Found {len(warehouse_docs)} warehouse documents")
                
                # حذف همه حواله‌های انبار (draft و finalized) - بدون commit
                for wd in warehouse_docs:
                    status = getattr(wd, "status", None)
                    logger.info(f"[DELETE_INVOICE] Invoice {document_id}: Warehouse document {wd.id} (code: {getattr(wd, 'code', 'N/A')}, status: {status})")
                    
                    # حذف خطوط حواله
                    lines_deleted = db.query(WarehouseDocumentLine).filter(
                        WarehouseDocumentLine.warehouse_document_id == wd.id
                    ).delete(synchronize_session=False)
                    logger.info(f"[DELETE_INVOICE] Invoice {document_id}: Deleted {lines_deleted} lines from warehouse document {wd.id}")
                    
                    # حذف حواله
                    db.delete(wd)
                    logger.info(f"[DELETE_INVOICE] Invoice {document_id}: Marked warehouse document {wd.id} for deletion")
            except ImportError:
                # اگر مدل WarehouseDocument وجود نداشت، از بررسی صرف‌نظر می‌کنیم
                logger.warning(f"[DELETE_INVOICE] Invoice {document_id}: WarehouseDocument model not available")
            except Exception as ex:
                logger.error(f"[DELETE_INVOICE] Invoice {document_id}: Error processing warehouse documents: {ex}", exc_info=True)
                raise  # خطا را propagate کن تا rollback شود
        
        # 5) حذف خودکار همه اسناد دریافت/پرداخت مرتبط (بدون توجه به مبلغ) - بدون commit
        receipt_payment_document_ids = links.get("receipt_payment_document_ids") or []
        logger.info(f"[DELETE_INVOICE] Invoice {document_id}: Found {len(receipt_payment_document_ids)} receipt/payment document IDs in links: {receipt_payment_document_ids}")
        
        if receipt_payment_document_ids:
            # ابتدا همه اسناد را بخوان
            related_docs = db.query(Document).filter(
                Document.id.in_(receipt_payment_document_ids)
            ).all()
            logger.info(f"[DELETE_INVOICE] Invoice {document_id}: Found {len(related_docs)} receipt/payment documents in database")
            
            # حذف همه اسناد دریافت/پرداخت مرتبط (بدون توجه به مبلغ) - بدون commit
            deleted_count = 0
            for rp_doc in related_docs:
                logger.info(f"[DELETE_INVOICE] Invoice {document_id}: Checking receipt/payment document {rp_doc.id} (code: {rp_doc.code}, type: {rp_doc.document_type})")
                
                # بررسی اینکه آیا این سند واقعاً برای این فاکتور است
                rp_extra_info = rp_doc.extra_info or {}
                rp_invoice_id = rp_extra_info.get("invoice_id")
                logger.info(f"[DELETE_INVOICE] Invoice {document_id}: Receipt/payment {rp_doc.id} extra_info.invoice_id={rp_invoice_id}, expected invoice_id={document_id}")
                
                # اگر invoice_id در extra_info وجود دارد و با document_id مطابقت ندارد، این سند برای فاکتور دیگری است
                if rp_invoice_id is not None and int(rp_invoice_id) != int(document_id):
                    logger.warning(f"[DELETE_INVOICE] Invoice {document_id}: Receipt/payment {rp_doc.id} belongs to different invoice {rp_invoice_id}, skipping deletion")
                    continue
                
                # بررسی نوع سند (باید receipt یا payment باشد)
                if rp_doc.document_type not in ("receipt", "payment"):
                    logger.warning(f"[DELETE_INVOICE] Invoice {document_id}: Receipt/payment {rp_doc.id} has invalid type {rp_doc.document_type}, skipping")
                    continue
                
                # بررسی محدودیت‌های حذف (سال مالی، قفل بودن، چک)
                # این بررسی‌ها را انجام می‌دهیم اما commit نمی‌کنیم
                try:
                    fiscal_year = db.query(FiscalYear).filter(FiscalYear.id == rp_doc.fiscal_year_id).first()
                    if fiscal_year is not None and getattr(fiscal_year, "is_last", False) is not True:
                        raise ApiError(
                            "FISCAL_YEAR_LOCKED",
                            f"سند دریافت/پرداخت {rp_doc.code} متعلق به سال مالی غیر جاری است",
                            http_status=409,
                        )
                    
                    # بررسی قفل بودن
                    locked_flags = []
                    if isinstance(rp_doc.extra_info, dict):
                        locked_flags.append(bool(rp_doc.extra_info.get("locked")))
                        locked_flags.append(bool(rp_doc.extra_info.get("is_locked")))
                    if isinstance(rp_doc.developer_settings, dict):
                        locked_flags.append(bool(rp_doc.developer_settings.get("locked")))
                        locked_flags.append(bool(rp_doc.developer_settings.get("is_locked")))
                    if any(locked_flags):
                        raise ApiError(
                            "DOCUMENT_LOCKED",
                            f"سند دریافت/پرداخت {rp_doc.code} قفل است",
                            http_status=409,
                        )
                    
                    # بررسی چک
                    has_related_checks = db.query(DocumentLine).filter(
                        and_(
                            DocumentLine.document_id == rp_doc.id,
                            DocumentLine.check_id.isnot(None),
                        )
                    ).first() is not None
                    if has_related_checks:
                        raise ApiError(
                            "DOCUMENT_REFERENCED",
                            f"سند دریافت/پرداخت {rp_doc.code} دارای اقلام مرتبط با چک است",
                            http_status=409,
                        )
                except ApiError:
                    raise  # خطاهای ApiError را propagate کن تا rollback شود
                except Exception as ex:
                    logger.warning(f"[DELETE_INVOICE] Invoice {document_id}: Error checking receipt/payment {rp_doc.id} constraints: {ex}")
                    raise  # هر خطای دیگری را هم propagate کن
                
                # حذف خطوط سند دریافت/پرداخت
                rp_lines_deleted = db.query(DocumentLine).filter(
                    DocumentLine.document_id == rp_doc.id
                ).delete(synchronize_session=False)
                logger.info(f"[DELETE_INVOICE] Invoice {document_id}: Deleted {rp_lines_deleted} lines from receipt/payment document {rp_doc.id}")
                
                # حذف سند دریافت/پرداخت (بدون commit)
                db.delete(rp_doc)
                deleted_count += 1
                logger.info(f"[DELETE_INVOICE] Invoice {document_id}: Marked receipt/payment document {rp_doc.id} for deletion")
            
            logger.info(f"[DELETE_INVOICE] Invoice {document_id}: Marked {deleted_count} receipt/payment documents for deletion")
        
        logger.info(f"[DELETE_INVOICE] Invoice {document_id}: All checks passed, proceeding with final deletion")
        
        # حذف خطوط سند حسابداری فاکتور
        lines_deleted = db.query(DocumentLine).filter(DocumentLine.document_id == document_id).delete(synchronize_session=False)
        logger.info(f"[DELETE_INVOICE] Invoice {document_id}: Deleted {lines_deleted} document lines")
        
        # حذف اقلام فاکتور
        items_deleted = db.query(InvoiceItemLine).filter(InvoiceItemLine.document_id == document_id).delete(synchronize_session=False)
        logger.info(f"[DELETE_INVOICE] Invoice {document_id}: Deleted {items_deleted} invoice item lines")
        
        # اقساط در extra_info.installment_plan ذخیره می‌شوند و با حذف سند خودشان حذف می‌شوند
        # نیازی به حذف جداگانه نیست
        
        # دریافت اطلاعات قبل از حذف برای invalidation
        business_id = document.business_id
        fiscal_year_id = document.fiscal_year_id
        document_type = document.document_type
        project_id = document.project_id
        
        # حذف سند فاکتور
        db.delete(document)
        logger.info(f"[DELETE_INVOICE] Invoice {document_id}: Marked invoice document for deletion")
        
        # commit همه تغییرات به صورت اتمیک
        try:
            db.commit()
            logger.info(f"[DELETE_INVOICE] Invoice {document_id}: ===== Successfully committed all deletions =====")
            
            # Invalidate cache بعد از حذف موفق فاکتور
            invalidate_invoices_cache(
                business_id=business_id,
                fiscal_year_id=fiscal_year_id,
                invoice_id=document_id,
                document_type=document_type,
                project_id=project_id
            )
            
            # همچنین اسناد عمومی را هم invalidate کن
            from app.services.document_service import invalidate_documents_cache
            invalidate_documents_cache(
                business_id=business_id,
                fiscal_year_id=fiscal_year_id,
                document_id=document_id,
                document_type=document_type
            )
            
            # اگر expense/income باشد
            if document_type in ['expense', 'income']:
                from app.services.expense_income_service import invalidate_expense_income_cache
                invalidate_expense_income_cache(
                    business_id=business_id,
                    fiscal_year_id=fiscal_year_id,
                    document_id=document_id
                )
            
        except Exception as commit_ex:
            logger.error(f"[DELETE_INVOICE] Invoice {document_id}: Error committing transaction: {commit_ex}", exc_info=True)
            db.rollback()
            raise ApiError("DELETE_FAILED", f"Failed to commit invoice deletion: {str(commit_ex)}", http_status=500)
        
        return True
    except ApiError as api_err:
        # ApiError code و message در detail ذخیره می‌شوند
        error_detail = api_err.detail if isinstance(api_err.detail, dict) else {}
        error_info = error_detail.get("error", {}) if isinstance(error_detail, dict) else {}
        error_code = error_info.get("code", "UNKNOWN") if isinstance(error_info, dict) else "UNKNOWN"
        error_message = error_info.get("message", str(api_err.detail)) if isinstance(error_info, dict) else str(api_err.detail)
        logger.error(f"[DELETE_INVOICE] Invoice {document_id}: ApiError raised - code={error_code}, message={error_message}, status={api_err.status_code}")
        db.rollback()
        raise
    except Exception as e:
        logger.error(f"[DELETE_INVOICE] Invoice {document_id}: Unexpected error deleting invoice: {e}", exc_info=True)
        db.rollback()
        raise ApiError("DELETE_FAILED", f"Failed to delete invoice: {str(e)}", http_status=500)


BULK_DELETE_INVOICES_MAX = 100


def bulk_delete_invoices(
    db: Session,
    business_id: int,
    invoice_ids: List[int],
) -> Dict[str, Any]:
    """
    حذف گروهی فاکتورها. برای هر فاکتور delete_invoice فراخوانی می‌شود.
    مواردی که به هر دلیل حذف نشوند در skipped با دلیل برگردانده می‌شوند.

    Returns:
        {"deleted": [id, ...], "skipped": [{"id": int, "code": str, "reason": str}, ...]}
    """
    invoice_ids = list(dict.fromkeys(invoice_ids))  # unique, preserve order
    if len(invoice_ids) > BULK_DELETE_INVOICES_MAX:
        raise ApiError(
            "TOO_MANY_ITEMS",
            f"حداکثر {BULK_DELETE_INVOICES_MAX} فاکتور در هر درخواست قابل حذف است",
            http_status=400,
        )
    deleted: List[int] = []
    skipped: List[Dict[str, Any]] = []

    for invoice_id in invoice_ids:
        doc = db.query(Document).filter(Document.id == invoice_id).first()
        code = doc.code if doc else ""
        if not doc or doc.business_id != business_id:
            skipped.append({"id": invoice_id, "code": code, "reason": "سند یافت نشد یا متعلق به این کسب‌وکار نیست"})
            continue
        if doc.document_type not in SUPPORTED_INVOICE_TYPES:
            skipped.append({"id": invoice_id, "code": code, "reason": "نوع سند فاکتور نیست"})
            continue
        try:
            delete_invoice(db, invoice_id)
            deleted.append(invoice_id)
        except ApiError as api_err:
            detail = api_err.detail
            if isinstance(detail, dict) and "error" in detail and isinstance(detail["error"], dict):
                reason = detail["error"].get("message", str(detail))
            else:
                reason = str(detail) if detail else api_err.detail
            skipped.append({"id": invoice_id, "code": code, "reason": reason})
        except Exception as e:
            skipped.append({"id": invoice_id, "code": code, "reason": str(e)})

    return {"deleted": deleted, "skipped": skipped}


def _cleanup_dead_receipt_payment_links(db: Session, document: Document) -> bool:
    """
    پاک‌سازی لینک‌های مرده receipt_payment_document_ids از extra_info فاکتور.
    این تابع لینک‌هایی که به اسناد حذف شده اشاره می‌کنند را پیدا و حذف می‌کند.
    
    Returns:
        bool: True اگر تغییری اعمال شد، False در غیر این صورت
    """
    try:
        extra_info = document.extra_info or {}
        links = extra_info.get('links', {})
        receipt_payment_ids = links.get('receipt_payment_document_ids', [])
        
        if not receipt_payment_ids:
            return False
        
        # بررسی وجود واقعی هر سند
        valid_ids = []
        for doc_id in receipt_payment_ids:
            try:
                doc_id_int = int(doc_id)
                # بررسی وجود سند در دیتابیس
                doc = db.query(Document).filter(
                    Document.id == doc_id_int,
                    Document.document_type.in_(['receipt', 'payment']),
                ).first()
                if doc:
                    valid_ids.append(doc_id_int)
            except (ValueError, TypeError):
                # شناسه نامعتبر، رد می‌شود
                continue
        
        # اگر همه لینک‌ها معتبر هستند، نیازی به به‌روزرسانی نیست
        if len(valid_ids) == len(receipt_payment_ids):
            return False
        
        # به‌روزرسانی extra_info با لینک‌های معتبر
        extra_info = dict(extra_info)
        links = dict(links)
        links['receipt_payment_document_ids'] = valid_ids
        extra_info['links'] = links

        document.extra_info = _normalize_document_extra_info_for_storage(extra_info)
        flag_modified(document, "extra_info")
        db.add(document)
        
        logger.info(f"پاک‌سازی لینک‌های مرده برای فاکتور {document.id}: {len(receipt_payment_ids)} -> {len(valid_ids)}")
        return True
    except Exception as e:
        logger.warning(f"خطا در پاک‌سازی لینک‌های مرده برای فاکتور {document.id}: {e}")
        return False


def invoice_document_to_dict(db: Session, document: Document) -> Dict[str, Any]:
    # اقلام فاکتور از جدول مجزا خوانده می‌شوند
    item_rows = db.query(InvoiceItemLine).filter(InvoiceItemLine.document_id == document.id).all()
    product_lines: List[Dict[str, Any]] = []
    for it in item_rows:
        product = db.query(Product).filter(Product.id == it.product_id).first()
        product_lines.append({
            "id": it.id,
            "product_id": it.product_id,
            "product_code": getattr(product, "code", None) if product else None,
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
    
    # دریافت نام پروژه
    project_name = None
    if document.project_id:
        from adapters.db.models.project import Project
        project = db.query(Project).filter(Project.id == document.project_id).first()
        if project:
            project_name = project.name

    # محاسبه سود فاکتور (در صورت فعال بودن)
    profit_data = {}
    business = db.query(Business).filter(Business.id == document.business_id).first()
    if business and business.invoice_profit_calculation_method != "disabled":
        try:
            profit_data = _calculate_invoice_profit(
                db,
                document.business_id,
                document.id,
                business.invoice_profit_calculation_method or "automatic",
                business.invoice_profit_calculation_basis or "purchase_price",
                business.invoice_profit_include_overhead or False,
                business.invoice_profit_overhead_type or "none",
                Decimal(str(business.invoice_profit_overhead_percent or 0)) if business.invoice_profit_overhead_percent else None,
                business.invoice_profit_calculation_type or "gross"
            )
        except Exception as e:
            logger.warning(f"Error calculating invoice profit for document {document.id}: {e}")
            profit_data = {}

    # پاک‌سازی لینک‌های مرده قبل از بازگرداندن نتیجه
    try:
        if _cleanup_dead_receipt_payment_links(db, document):
            # commit تغییرات
            db.commit()
            db.refresh(document)
    except Exception as e:
        logger.warning(f"خطا در پاک‌سازی لینک‌های مرده در invoice_document_to_dict: {e}")
        try:
            db.rollback()
        except Exception:
            pass
    
    result = {
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
        "project_id": document.project_id,
        "project_name": project_name,
        "extra_info": _normalize_document_extra_info_for_storage(document.extra_info),
        "product_lines": product_lines,
        "account_lines": account_lines,
        "created_at": document.created_at.isoformat(),
        "updated_at": document.updated_at.isoformat(),
    }
    
    # اضافه کردن اطلاعات سود به response
    if profit_data:
        if "gross_profit" in profit_data:
            result["gross_profit"] = profit_data["gross_profit"]
            result["gross_profit_percent"] = profit_data["gross_profit_percent"]
        if "net_profit" in profit_data:
            result["net_profit"] = profit_data["net_profit"]
            result["net_profit_percent"] = profit_data["net_profit_percent"]
        if "total_profit" in profit_data:
            result["total_profit"] = profit_data["total_profit"]
            result["total_profit_percent"] = profit_data["total_profit_percent"]
        result["total_overhead"] = profit_data.get("total_overhead", 0.0)
        result["line_profits"] = profit_data.get("line_profits", [])
    
    return result


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
    *,
    disable_pagination: bool = False,
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
    take = max(1, min(take, 1000))
    skip = max(0, skip)

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
    sum_principal = Decimal(0)
    sum_interest = Decimal(0)
    sum_total = Decimal(0)
    sum_paid = Decimal(0)
    sum_remaining = Decimal(0)
    sum_late_fee = Decimal(0)
    status_counts: Dict[str, int] = {"pending": 0, "partial": 0, "paid": 0, "overdue": 0}
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
        person_name = (extra.get("person_name") or extra.get("person_title")) if isinstance(extra, dict) else None
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
            sum_principal += principal
            sum_interest += interest
            sum_total += total
            sum_paid += paid
            sum_remaining += remaining
            sum_late_fee += late_fee_amount
            status_counts[st] = status_counts.get(st, 0) + 1
            items.append({
                "invoice_id": int(doc.id),
                "invoice_code": doc.code,
                "person_id": extra.get("person_id"),
                "person_name": person_name,
                "document_date": doc.document_date,
                "seq": int(it.get("seq") or 0),
                "due_date": due,
                "principal": float(principal),
                "interest": float(interest),
                "total": float(total),
                "paid_amount": float(paid),
                "remaining": float(remaining),
                "status": st,
                "overdue_days": overdue_days,
                "late_fee_amount": float(late_fee_amount),
            })

    items.sort(key=lambda row: (row["due_date"], row["invoice_id"], row["seq"]))
    total_count = len(items)

    if disable_pagination:
        page_items = items
        effective_take = total_count or take
        effective_skip = 0
        has_next = False
    else:
        page_items = items[skip: skip + take]
        effective_take = take
        effective_skip = skip
        has_next = skip + take < total_count

    stats = {
        "total_count": total_count,
        "principal_total": float(sum_principal),
        "interest_total": float(sum_interest),
        "amount_total": float(sum_total),
        "paid_total": float(sum_paid),
        "remaining_total": float(sum_remaining),
        "late_fee_total": float(sum_late_fee),
        "status_breakdown": {k: int(v) for k, v in status_counts.items()},
    }

    return {
        "items": page_items,
        "pagination": {
            "total": total_count,
            "take": effective_take,
            "skip": effective_skip,
            "page": (effective_skip // effective_take) + 1 if effective_take else 1,
            "has_next": has_next,
        },
        "stats": stats,
        "filters": {
            "fiscal_year_id": fiscal_year_id,
            "due_from": due_from,
            "due_to": due_to,
            "status": status_filter,
            "person_id": person_id_filter,
            "invoice_id": invoice_id_filter,
        },
    }


def _format_date_for_calendar(value: Any, calendar_type: CalendarType) -> str | None:
    if value is None:
        return None
    dt_value: datetime | None = None
    if isinstance(value, datetime):
        dt_value = value
    elif isinstance(value, date):
        dt_value = datetime.combine(value, datetime.min.time())
    elif isinstance(value, str):
        return value
    if dt_value is None:
        return str(value)
    formatted = CalendarConverter.format_datetime(dt_value, calendar_type)
    return formatted.get("date_only") or formatted.get("formatted")


def export_installments_csv(
    db: Session,
    business_id: int,
    query: Dict[str, Any],
    calendar_type: CalendarType = "gregorian",
) -> bytes:
    """
    خروجی CSV اقساط بر اساس همان فیلترهای search_installments.
    """
    data = search_installments(db, business_id, query, disable_pagination=True)
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
            _format_date_for_calendar(it.get("document_date"), calendar_type),
            it.get("seq"),
            _format_date_for_calendar(it.get("due_date"), calendar_type),
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
    calendar_type: CalendarType = "gregorian",
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
        data = search_installments(db, business_id, query, disable_pagination=True)
        for it in data.get("items", []):
            ws.append([
                it.get("invoice_id"),
                it.get("invoice_code"),
                it.get("person_id"),
                it.get("person_name"),
                _format_date_for_calendar(it.get("document_date"), calendar_type),
                it.get("seq"),
                _format_date_for_calendar(it.get("due_date"), calendar_type),
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
        content = export_installments_csv(db, business_id, query, calendar_type=calendar_type)
        return content, "text/csv; charset=utf-8", "csv"


def get_daily_sales_report(
    db: Session,
    business_id: int,
    fiscal_year_id: Optional[int] = None,
    currency_id: Optional[int] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    skip: int = 0,
    take: int = 50,
) -> Dict[str, Any]:
    """
    گزارش فروش روزانه
    
    Args:
        db: نشست پایگاه داده
        business_id: شناسه کسب‌وکار
        fiscal_year_id: شناسه سال مالی (اختیاری)
        currency_id: شناسه ارز (اختیاری)
        date_from: از تاریخ (اختیاری، فرمت YYYY-MM-DD)
        date_to: تا تاریخ (اختیاری، فرمت YYYY-MM-DD)
        skip: تعداد رکوردهای رد شده برای pagination
        take: تعداد رکوردهای برگشتی
    
    Returns:
        dict: {
            'items': لیست روزها با آمار فروش,
            'summary': خلاصه آمار,
            'pagination': اطلاعات pagination
        }
    """
    from collections import defaultdict
    
    # تبدیل تاریخ‌ها
    date_from_obj = None
    date_to_obj = None
    
    if date_from:
        try:
            date_from_obj = _parse_iso_date(date_from)
        except Exception:
            pass
    
    if date_to:
        try:
            date_to_obj = _parse_iso_date(date_to)
        except Exception:
            pass
    
    # اگر تاریخ‌ها مشخص نشده‌اند، از سال مالی استفاده کن
    if date_from_obj is None or date_to_obj is None:
        try:
            if fiscal_year_id:
                fiscal_year = db.query(FiscalYear).filter(FiscalYear.id == fiscal_year_id).first()
            else:
                fiscal_year = db.query(FiscalYear).filter(
                    and_(
                        FiscalYear.business_id == business_id,
                        FiscalYear.is_last == True
                    )
                ).first()
            
            if fiscal_year:
                if date_from_obj is None:
                    date_from_obj = fiscal_year.start_date
                if date_to_obj is None:
                    date_to_obj = fiscal_year.end_date if fiscal_year.end_date else date.today()
        except Exception:
            pass
    
    # اگر هنوز تاریخ مشخص نشده
    if date_to_obj is None:
        date_to_obj = date.today()
    if date_from_obj is None:
        date_from_obj = date.today()
    
    # Query فاکتورهای فروش
    sales_query = db.query(
        Document.document_date,
        Document.extra_info,
        Document.currency_id,
    ).filter(
        and_(
            Document.business_id == business_id,
            Document.document_type == INVOICE_SALES,
            Document.is_proforma == False,
            Document.document_date >= date_from_obj,
            Document.document_date <= date_to_obj,
        )
    )
    
    if currency_id:
        sales_query = sales_query.filter(Document.currency_id == currency_id)
    
    if fiscal_year_id:
        sales_query = sales_query.filter(Document.fiscal_year_id == fiscal_year_id)
    
    sales_documents = sales_query.order_by(Document.document_date.asc()).all()
    
    # گروه‌بندی بر اساس روز
    daily_stats: Dict[str, Dict[str, Any]] = defaultdict(lambda: {
        'date': None,
        'invoice_count': 0,
        'total_gross': Decimal(0),
        'total_discount': Decimal(0),
        'total_tax': Decimal(0),
        'total_net': Decimal(0),
    })
    
    for doc in sales_documents:
        doc_date = doc.document_date
        if not doc_date:
            continue
        
        date_key = doc_date.isoformat()
        extra_info = doc.extra_info or {}
        totals = extra_info.get('totals') or {}
        
        daily_stats[date_key]['date'] = doc_date.isoformat()
        daily_stats[date_key]['invoice_count'] += 1
        daily_stats[date_key]['total_gross'] += Decimal(str(totals.get('gross', 0) or 0))
        daily_stats[date_key]['total_discount'] += Decimal(str(totals.get('discount', 0) or 0))
        daily_stats[date_key]['total_tax'] += Decimal(str(totals.get('tax', 0) or 0))
        daily_stats[date_key]['total_net'] += Decimal(str(totals.get('net', 0) or 0))
    
    # تبدیل به لیست و مرتب‌سازی (ترتیب نزولی)
    items = []
    for date_key in sorted(daily_stats.keys(), reverse=True):
        stats = daily_stats[date_key]
        items.append({
            'date': stats['date'],
            'invoice_count': stats['invoice_count'],
            'total_gross': float(stats['total_gross']),
            'total_discount': float(stats['total_discount']),
            'total_tax': float(stats['total_tax']),
            'total_net': float(stats['total_net']),
        })
    
    total = len(items)
    current_page = (skip // take) + 1
    total_pages = (total + take - 1) // take if take > 0 else 1
    paginated_items = items[skip:skip + take]
    
    total_invoice_count = sum(item['invoice_count'] for item in items)
    total_gross_sum = sum(item['total_gross'] for item in items)
    total_discount_sum = sum(item['total_discount'] for item in items)
    total_tax_sum = sum(item['total_tax'] for item in items)
    total_net_sum = sum(item['total_net'] for item in items)
    
    return {
        'items': paginated_items,
        'summary': {
            'total_count': total,
            'total_invoice_count': total_invoice_count,
            'total_gross': float(total_gross_sum),
            'total_discount': float(total_discount_sum),
            'total_tax': float(total_tax_sum),
            'total_net': float(total_net_sum),
        },
        'pagination': {
            'total': total,
            'page': current_page,
            'per_page': take,
            'total_pages': total_pages,
            'has_next': current_page < total_pages,
            'has_prev': current_page > 1,
        }
    }


def get_daily_purchases_report(
    db: Session,
    business_id: int,
    fiscal_year_id: Optional[int] = None,
    currency_id: Optional[int] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    skip: int = 0,
    take: int = 50,
) -> Dict[str, Any]:
    """
    گزارش خرید روزانه
    
    Args:
        db: نشست پایگاه داده
        business_id: شناسه کسب‌وکار
        fiscal_year_id: شناسه سال مالی (اختیاری)
        currency_id: شناسه ارز (اختیاری)
        date_from: از تاریخ (اختیاری، فرمت YYYY-MM-DD)
        date_to: تا تاریخ (اختیاری، فرمت YYYY-MM-DD)
        skip: تعداد رکوردهای رد شده برای pagination
        take: تعداد رکوردهای برگشتی
    
    Returns:
        dict: {
            'items': لیست روزها با آمار خرید,
            'summary': خلاصه آمار,
            'pagination': اطلاعات pagination
        }
    """
    from collections import defaultdict
    
    # تبدیل تاریخ‌ها
    date_from_obj = None
    date_to_obj = None
    
    if date_from:
        try:
            date_from_obj = _parse_iso_date(date_from)
        except Exception:
            pass
    
    if date_to:
        try:
            date_to_obj = _parse_iso_date(date_to)
        except Exception:
            pass
    
    # اگر تاریخ‌ها مشخص نشده‌اند، از سال مالی استفاده کن
    if date_from_obj is None or date_to_obj is None:
        try:
            if fiscal_year_id:
                fiscal_year = db.query(FiscalYear).filter(FiscalYear.id == fiscal_year_id).first()
            else:
                fiscal_year = db.query(FiscalYear).filter(
                    and_(
                        FiscalYear.business_id == business_id,
                        FiscalYear.is_last == True
                    )
                ).first()
            
            if fiscal_year:
                if date_from_obj is None:
                    date_from_obj = fiscal_year.start_date
                if date_to_obj is None:
                    date_to_obj = fiscal_year.end_date if fiscal_year.end_date else date.today()
        except Exception:
            pass
    
    # اگر هنوز تاریخ مشخص نشده
    if date_to_obj is None:
        date_to_obj = date.today()
    if date_from_obj is None:
        date_from_obj = date.today()
    
    # Query فاکتورهای خرید
    purchases_query = db.query(
        Document.document_date,
        Document.extra_info,
        Document.currency_id,
    ).filter(
        and_(
            Document.business_id == business_id,
            Document.document_type == INVOICE_PURCHASE,
            Document.is_proforma == False,
            Document.document_date >= date_from_obj,
            Document.document_date <= date_to_obj,
        )
    )
    
    if currency_id:
        purchases_query = purchases_query.filter(Document.currency_id == currency_id)
    
    if fiscal_year_id:
        purchases_query = purchases_query.filter(Document.fiscal_year_id == fiscal_year_id)
    
    purchases_documents = purchases_query.order_by(Document.document_date.asc()).all()
    
    # گروه‌بندی بر اساس روز
    daily_stats: Dict[str, Dict[str, Any]] = defaultdict(lambda: {
        'date': None,
        'invoice_count': 0,
        'total_gross': Decimal(0),
        'total_discount': Decimal(0),
        'total_tax': Decimal(0),
        'total_net': Decimal(0),
    })
    
    for doc in purchases_documents:
        doc_date = doc.document_date
        if not doc_date:
            continue
        
        date_key = doc_date.isoformat()
        extra_info = doc.extra_info or {}
        totals = extra_info.get('totals') or {}
        
        daily_stats[date_key]['date'] = doc_date.isoformat()
        daily_stats[date_key]['invoice_count'] += 1
        daily_stats[date_key]['total_gross'] += Decimal(str(totals.get('gross', 0) or 0))
        daily_stats[date_key]['total_discount'] += Decimal(str(totals.get('discount', 0) or 0))
        daily_stats[date_key]['total_tax'] += Decimal(str(totals.get('tax', 0) or 0))
        daily_stats[date_key]['total_net'] += Decimal(str(totals.get('net', 0) or 0))
    
    # تبدیل به لیست و مرتب‌سازی (ترتیب نزولی)
    items = []
    for date_key in sorted(daily_stats.keys(), reverse=True):
        stats = daily_stats[date_key]
        items.append({
            'date': stats['date'],
            'invoice_count': stats['invoice_count'],
            'total_gross': float(stats['total_gross']),
            'total_discount': float(stats['total_discount']),
            'total_tax': float(stats['total_tax']),
            'total_net': float(stats['total_net']),
        })
    
    total = len(items)
    current_page = (skip // take) + 1
    total_pages = (total + take - 1) // take if take > 0 else 1
    paginated_items = items[skip:skip + take]
    
    total_invoice_count = sum(item['invoice_count'] for item in items)
    total_gross_sum = sum(item['total_gross'] for item in items)
    total_discount_sum = sum(item['total_discount'] for item in items)
    total_tax_sum = sum(item['total_tax'] for item in items)
    total_net_sum = sum(item['total_net'] for item in items)
    
    return {
        'items': paginated_items,
        'summary': {
            'total_count': total,
            'total_invoice_count': total_invoice_count,
            'total_gross': float(total_gross_sum),
            'total_discount': float(total_discount_sum),
            'total_tax': float(total_tax_sum),
            'total_net': float(total_net_sum),
        },
        'pagination': {
            'total': total,
            'page': current_page,
            'per_page': take,
            'total_pages': total_pages,
            'has_next': current_page < total_pages,
            'has_prev': current_page > 1,
        }
    }


def get_monthly_sales_report(
    db: Session,
    business_id: int,
    fiscal_year_id: Optional[int] = None,
    currency_id: Optional[int] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    skip: int = 0,
    take: int = 50,
) -> Dict[str, Any]:
    """
    گزارش فروش ماهانه
    
    Args:
        db: نشست پایگاه داده
        business_id: شناسه کسب‌وکار
        fiscal_year_id: شناسه سال مالی (اختیاری)
        currency_id: شناسه ارز (اختیاری)
        date_from: از تاریخ (اختیاری، فرمت YYYY-MM-DD)
        date_to: تا تاریخ (اختیاری، فرمت YYYY-MM-DD)
        skip: تعداد رکوردهای رد شده برای pagination
        take: تعداد رکوردهای برگشتی
    
    Returns:
        dict: {
            'items': لیست ماه‌ها با آمار فروش,
            'summary': خلاصه آمار,
            'pagination': اطلاعات pagination
        }
    """
    from collections import defaultdict
    
    # تبدیل تاریخ‌ها
    date_from_obj = None
    date_to_obj = None
    
    if date_from:
        try:
            date_from_obj = _parse_iso_date(date_from)
        except Exception:
            pass
    
    if date_to:
        try:
            date_to_obj = _parse_iso_date(date_to)
        except Exception:
            pass
    
    # اگر تاریخ‌ها مشخص نشده‌اند، از سال مالی استفاده کن
    if date_from_obj is None or date_to_obj is None:
        try:
            if fiscal_year_id:
                fiscal_year = db.query(FiscalYear).filter(FiscalYear.id == fiscal_year_id).first()
            else:
                fiscal_year = db.query(FiscalYear).filter(
                    and_(
                        FiscalYear.business_id == business_id,
                        FiscalYear.is_last == True
                    )
                ).first()
            
            if fiscal_year:
                if date_from_obj is None:
                    date_from_obj = fiscal_year.start_date
                if date_to_obj is None:
                    date_to_obj = fiscal_year.end_date if fiscal_year.end_date else date.today()
        except Exception:
            pass
    
    # اگر هنوز تاریخ مشخص نشده
    if date_to_obj is None:
        date_to_obj = date.today()
    if date_from_obj is None:
        date_from_obj = date.today()
    
    # Query فاکتورهای فروش
    sales_query = db.query(
        Document.document_date,
        Document.extra_info,
        Document.currency_id,
    ).filter(
        and_(
            Document.business_id == business_id,
            Document.document_type == INVOICE_SALES,
            Document.is_proforma == False,
            Document.document_date >= date_from_obj,
            Document.document_date <= date_to_obj,
        )
    )
    
    if currency_id:
        sales_query = sales_query.filter(Document.currency_id == currency_id)
    
    if fiscal_year_id:
        sales_query = sales_query.filter(Document.fiscal_year_id == fiscal_year_id)
    
    sales_documents = sales_query.order_by(Document.document_date.asc()).all()
    
    # گروه‌بندی بر اساس ماه
    monthly_stats: Dict[str, Dict[str, Any]] = defaultdict(lambda: {
        'year': None,
        'month': None,
        'month_key': None,
        'invoice_count': 0,
        'total_gross': Decimal(0),
        'total_discount': Decimal(0),
        'total_tax': Decimal(0),
        'total_net': Decimal(0),
    })
    
    for doc in sales_documents:
        doc_date = doc.document_date
        if not doc_date:
            continue
        
        # کلید ماه: YYYY-MM
        month_key = f"{doc_date.year:04d}-{doc_date.month:02d}"
        extra_info = doc.extra_info or {}
        totals = extra_info.get('totals') or {}
        
        monthly_stats[month_key]['year'] = doc_date.year
        monthly_stats[month_key]['month'] = doc_date.month
        monthly_stats[month_key]['month_key'] = month_key
        monthly_stats[month_key]['invoice_count'] += 1
        monthly_stats[month_key]['total_gross'] += Decimal(str(totals.get('gross', 0) or 0))
        monthly_stats[month_key]['total_discount'] += Decimal(str(totals.get('discount', 0) or 0))
        monthly_stats[month_key]['total_tax'] += Decimal(str(totals.get('tax', 0) or 0))
        monthly_stats[month_key]['total_net'] += Decimal(str(totals.get('net', 0) or 0))
    
    # تبدیل به لیست و مرتب‌سازی (ترتیب نزولی)
    items = []
    for month_key in sorted(monthly_stats.keys(), reverse=True):
        stats = monthly_stats[month_key]
        # ساخت تاریخ اول ماه برای نمایش
        try:
            from datetime import date as date_class
            first_day_of_month = date_class(stats['year'], stats['month'], 1)
        except Exception:
            first_day_of_month = None
        
        items.append({
            'year': stats['year'],
            'month': stats['month'],
            'month_key': stats['month_key'],
            'date': first_day_of_month.isoformat() if first_day_of_month else None,
            'invoice_count': stats['invoice_count'],
            'total_gross': float(stats['total_gross']),
            'total_discount': float(stats['total_discount']),
            'total_tax': float(stats['total_tax']),
            'total_net': float(stats['total_net']),
        })
    
    # Pagination
    total = len(items)
    current_page = (skip // take) + 1
    total_pages = (total + take - 1) // take if take > 0 else 1
    paginated_items = items[skip:skip + take]
    
    total_invoice_count = sum(item['invoice_count'] for item in items)
    total_gross_sum = sum(item['total_gross'] for item in items)
    total_discount_sum = sum(item['total_discount'] for item in items)
    total_tax_sum = sum(item['total_tax'] for item in items)
    total_net_sum = sum(item['total_net'] for item in items)
    
    return {
        'items': paginated_items,
        'summary': {
            'total_count': total,
            'total_invoice_count': total_invoice_count,
            'total_gross': float(total_gross_sum),
            'total_discount': float(total_discount_sum),
            'total_tax': float(total_tax_sum),
            'total_net': float(total_net_sum),
        },
        'pagination': {
            'total': total,
            'page': current_page,
            'per_page': take,
            'total_pages': total_pages,
            'has_next': current_page < total_pages,
            'has_prev': current_page > 1,
        }
    }


def get_top_customers_report(
    db: Session,
    business_id: int,
    fiscal_year_id: Optional[int] = None,
    currency_id: Optional[int] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    limit: Optional[int] = None,
    skip: int = 0,
    take: int = 50,
) -> Dict[str, Any]:
    """
    گزارش برترین مشتریان بر اساس مبلغ فروش
    
    Args:
        db: نشست پایگاه داده
        business_id: شناسه کسب‌وکار
        fiscal_year_id: شناسه سال مالی (اختیاری)
        currency_id: شناسه ارز (اختیاری)
        date_from: از تاریخ (اختیاری، فرمت YYYY-MM-DD)
        date_to: تا تاریخ (اختیاری، فرمت YYYY-MM-DD)
        limit: تعداد مشتریان برتر (اختیاری، برای pagination)
        skip: تعداد رکوردهای رد شده برای pagination
        take: تعداد رکوردهای برگشتی
    
    Returns:
        dict: {
            'items': لیست مشتریان برتر,
            'summary': خلاصه آمار,
            'pagination': اطلاعات pagination
        }
    """
    from collections import defaultdict
    
    # تبدیل تاریخ‌ها
    date_from_obj = None
    date_to_obj = None
    
    if date_from:
        try:
            date_from_obj = _parse_iso_date(date_from)
        except Exception:
            pass
    
    if date_to:
        try:
            date_to_obj = _parse_iso_date(date_to)
        except Exception:
            pass
    
    # اگر تاریخ‌ها مشخص نشده‌اند، از سال مالی استفاده کن
    if date_from_obj is None or date_to_obj is None:
        try:
            if fiscal_year_id:
                fiscal_year = db.query(FiscalYear).filter(FiscalYear.id == fiscal_year_id).first()
            else:
                fiscal_year = db.query(FiscalYear).filter(
                    and_(
                        FiscalYear.business_id == business_id,
                        FiscalYear.is_last == True
                    )
                ).first()
            
            if fiscal_year:
                if date_from_obj is None:
                    date_from_obj = fiscal_year.start_date
                if date_to_obj is None:
                    date_to_obj = fiscal_year.end_date if fiscal_year.end_date else date.today()
        except Exception:
            pass
    
    # اگر هنوز تاریخ مشخص نشده، از یک بازه زمانی معقول استفاده کن
    # مثلاً از ابتدای سال جاری تا امروز
    if date_to_obj is None:
        date_to_obj = date.today()
    if date_from_obj is None:
        # اگر سال مالی پیدا نشد، از ابتدای سال جاری استفاده کن
        try:
            current_year = date.today().year
            date_from_obj = date(current_year, 1, 1)
        except Exception:
            date_from_obj = date.today()
    
    # Query فاکتورهای فروش
    sales_query = db.query(Document).filter(
        and_(
            Document.business_id == business_id,
            Document.document_type == INVOICE_SALES,
            Document.is_proforma == False,
            Document.document_date >= date_from_obj,
            Document.document_date <= date_to_obj,
        )
    )
    
    if currency_id:
        sales_query = sales_query.filter(Document.currency_id == currency_id)
    
    if fiscal_year_id:
        sales_query = sales_query.filter(Document.fiscal_year_id == fiscal_year_id)
    
    sales_documents = sales_query.order_by(Document.document_date.asc()).all()
    
    # Debug: لاگ تعداد فاکتورهای پیدا شده و بازه زمانی
    logger.debug(f"Top customers report: Found {len(sales_documents)} sales invoices for business {business_id}, date_range: {date_from_obj} to {date_to_obj}")
    
    # استخراج person_id از DocumentLine ها به صورت batch برای بهبود کارایی
    doc_ids = [doc.id for doc in sales_documents]
    person_id_map = {}
    if doc_ids:
        # دریافت person_id از DocumentLine برای تمام فاکتورها در یک query
        doc_lines_with_person = db.query(
            DocumentLine.document_id,
            DocumentLine.person_id
        ).filter(
            and_(
                DocumentLine.document_id.in_(doc_ids),
                DocumentLine.person_id.isnot(None)
            )
        ).all()
        
        # ساخت map از document_id به person_id (اولین person_id پیدا شده)
        for line in doc_lines_with_person:
            if line.document_id not in person_id_map:
                person_id_map[line.document_id] = line.person_id
    
    # گروه‌بندی بر اساس person_id
    customer_stats: Dict[int, Dict[str, Any]] = defaultdict(lambda: {
        'person_id': None,
        'invoice_count': 0,
        'total_sales': Decimal(0),
        'last_sale_date': None,
    })
    
    # دریافت اطلاعات شخص‌ها از پایگاه داده
    person_ids_set = set()
    invoices_without_person = 0
    
    for doc in sales_documents:
        extra_info = doc.extra_info or {}
        
        # استخراج person_id از extra_info
        person_id = extra_info.get('person_id')
        
        # اگر person_id در extra_info نبود، از person_id_map استفاده کن (از DocumentLine)
        if person_id is None:
            person_id = person_id_map.get(doc.id)
        
        if person_id is None:
            invoices_without_person += 1
            continue
        
        try:
            person_id_int = int(person_id)
        except (ValueError, TypeError):
            invoices_without_person += 1
            continue
        
        person_ids_set.add(person_id_int)
        
        # محاسبه مبلغ فروش از extra_info.totals.net
        totals = extra_info.get('totals') or {}
        net_amount = Decimal(str(totals.get('net', 0) or 0))
        
        customer_stats[person_id_int]['person_id'] = person_id_int
        customer_stats[person_id_int]['invoice_count'] += 1
        customer_stats[person_id_int]['total_sales'] += net_amount
        
        # به‌روزرسانی آخرین تاریخ فروش
        doc_date = doc.document_date
        if doc_date:
            current_last_date = customer_stats[person_id_int]['last_sale_date']
            if current_last_date is None or doc_date > current_last_date:
                customer_stats[person_id_int]['last_sale_date'] = doc_date
    
    # Debug: لاگ تعداد فاکتورهای بدون person_id
    if invoices_without_person > 0:
        logger.debug(f"Top customers report: {invoices_without_person} invoices without person_id")
    
    # دریافت اطلاعات شخص‌ها از پایگاه داده
    persons_map = {}
    if person_ids_set:
        persons = db.query(Person).filter(
            and_(
                Person.business_id == business_id,
                Person.id.in_(list(person_ids_set))
            )
        ).all()
        
        for person in persons:
            # ساخت نام نمایشی
            display_name = person.alias_name or ''
            if person.company_name:
                display_name = person.company_name
            elif person.first_name or person.last_name:
                parts = []
                if person.first_name:
                    parts.append(person.first_name)
                if person.last_name:
                    parts.append(person.last_name)
                display_name = ' '.join(parts) if parts else person.alias_name or ''
            
            persons_map[person.id] = {
                'id': person.id,
                'code': person.code,
                'alias_name': person.alias_name,
                'first_name': person.first_name,
                'last_name': person.last_name,
                'company_name': person.company_name,
                'display_name': display_name,
            }
    
    # تبدیل به لیست و مرتب‌سازی بر اساس مبلغ فروش (ترتیب نزولی)
    items = []
    for person_id, stats in customer_stats.items():
        person_info = persons_map.get(person_id, {})
        
        items.append({
            'person_id': person_id,
            'person_code': person_info.get('code'),
            'person_name': person_info.get('display_name', person_info.get('alias_name', '')),
            'invoice_count': stats['invoice_count'],
            'total_sales': float(stats['total_sales']),
            'last_sale_date': stats['last_sale_date'].isoformat() if stats['last_sale_date'] else None,
        })
    
    # مرتب‌سازی بر اساس مبلغ فروش (ترتیب نزولی)
    items.sort(key=lambda x: x['total_sales'], reverse=True)
    
    # اعمال limit اگر مشخص شده باشد
    if limit is not None and limit > 0:
        items = items[:limit]
    
    # Pagination
    total = len(items)
    current_page = (skip // take) + 1
    total_pages = (total + take - 1) // take if take > 0 else 1
    paginated_items = items[skip:skip + take]
    
    # محاسبه خلاصه
    total_customers = len(customer_stats)
    total_invoice_count = sum(item['invoice_count'] for item in items)
    total_sales_sum = sum(item['total_sales'] for item in items)
    
    return {
        'items': paginated_items,
        'summary': {
            'total_count': total,
            'total_customers': total_customers,
            'total_invoice_count': total_invoice_count,
            'total_sales': float(total_sales_sum),
        },
        'pagination': {
            'total': total,
            'page': current_page,
            'per_page': take,
            'total_pages': total_pages,
            'has_next': current_page < total_pages,
            'has_prev': current_page > 1,
        }
    }


def get_top_suppliers_report(
    db: Session,
    business_id: int,
    fiscal_year_id: Optional[int] = None,
    currency_id: Optional[int] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    limit: Optional[int] = None,
    skip: int = 0,
    take: int = 50,
) -> Dict[str, Any]:
    """
    گزارش برترین تامین‌کنندگان بر اساس مبلغ خرید
    
    Args:
        db: نشست پایگاه داده
        business_id: شناسه کسب‌وکار
        fiscal_year_id: شناسه سال مالی (اختیاری)
        currency_id: شناسه ارز (اختیاری)
        date_from: از تاریخ (اختیاری، فرمت YYYY-MM-DD)
        date_to: تا تاریخ (اختیاری، فرمت YYYY-MM-DD)
        limit: تعداد تامین‌کنندگان برتر (اختیاری، برای pagination)
        skip: تعداد رکوردهای رد شده برای pagination
        take: تعداد رکوردهای برگشتی
    
    Returns:
        dict: {
            'items': لیست تامین‌کنندگان برتر,
            'summary': خلاصه آمار,
            'pagination': اطلاعات pagination
        }
    """
    from collections import defaultdict
    
    # تبدیل تاریخ‌ها
    date_from_obj = None
    date_to_obj = None
    
    if date_from:
        try:
            date_from_obj = _parse_iso_date(date_from)
        except Exception:
            pass
    
    if date_to:
        try:
            date_to_obj = _parse_iso_date(date_to)
        except Exception:
            pass
    
    # اگر تاریخ‌ها مشخص نشده‌اند، از سال مالی استفاده کن
    if date_from_obj is None or date_to_obj is None:
        try:
            if fiscal_year_id:
                fiscal_year = db.query(FiscalYear).filter(FiscalYear.id == fiscal_year_id).first()
            else:
                fiscal_year = db.query(FiscalYear).filter(
                    and_(
                        FiscalYear.business_id == business_id,
                        FiscalYear.is_last == True
                    )
                ).first()
            
            if fiscal_year:
                if date_from_obj is None:
                    date_from_obj = fiscal_year.start_date
                if date_to_obj is None:
                    date_to_obj = fiscal_year.end_date if fiscal_year.end_date else date.today()
        except Exception:
            pass
    
    # اگر هنوز تاریخ مشخص نشده، از یک بازه زمانی معقول استفاده کن
    # مثلاً از ابتدای سال جاری تا امروز
    if date_to_obj is None:
        date_to_obj = date.today()
    if date_from_obj is None:
        # اگر سال مالی پیدا نشد، از ابتدای سال جاری استفاده کن
        try:
            current_year = date.today().year
            date_from_obj = date(current_year, 1, 1)
        except Exception:
            date_from_obj = date.today()
    
    # Query فاکتورهای خرید
    purchases_query = db.query(Document).filter(
        and_(
            Document.business_id == business_id,
            Document.document_type == INVOICE_PURCHASE,
            Document.is_proforma == False,
            Document.document_date >= date_from_obj,
            Document.document_date <= date_to_obj,
        )
    )
    
    if currency_id:
        purchases_query = purchases_query.filter(Document.currency_id == currency_id)
    
    if fiscal_year_id:
        purchases_query = purchases_query.filter(Document.fiscal_year_id == fiscal_year_id)
    
    purchases_documents = purchases_query.order_by(Document.document_date.asc()).all()
    
    # Debug: لاگ تعداد فاکتورهای پیدا شده
    logger.debug(f"Top suppliers report: Found {len(purchases_documents)} purchase invoices for business {business_id}")
    
    # استخراج person_id از DocumentLine ها به صورت batch برای بهبود کارایی
    doc_ids = [doc.id for doc in purchases_documents]
    person_id_map = {}
    if doc_ids:
        # دریافت person_id از DocumentLine برای تمام فاکتورها در یک query
        doc_lines_with_person = db.query(
            DocumentLine.document_id,
            DocumentLine.person_id
        ).filter(
            and_(
                DocumentLine.document_id.in_(doc_ids),
                DocumentLine.person_id.isnot(None)
            )
        ).all()
        
        # ساخت map از document_id به person_id (اولین person_id پیدا شده)
        for line in doc_lines_with_person:
            if line.document_id not in person_id_map:
                person_id_map[line.document_id] = line.person_id
    
    # گروه‌بندی بر اساس person_id
    supplier_stats: Dict[int, Dict[str, Any]] = defaultdict(lambda: {
        'person_id': None,
        'invoice_count': 0,
        'total_purchases': Decimal(0),
        'last_purchase_date': None,
    })
    
    # دریافت اطلاعات شخص‌ها از پایگاه داده
    person_ids_set = set()
    invoices_without_person = 0
    
    for doc in purchases_documents:
        extra_info = doc.extra_info or {}
        
        # استخراج person_id از extra_info
        person_id = extra_info.get('person_id')
        
        # اگر person_id در extra_info نبود، از person_id_map استفاده کن (از DocumentLine)
        if person_id is None:
            person_id = person_id_map.get(doc.id)
        
        if person_id is None:
            invoices_without_person += 1
            continue
        
        try:
            person_id_int = int(person_id)
        except (ValueError, TypeError):
            invoices_without_person += 1
            continue
        
        person_ids_set.add(person_id_int)
        
        # محاسبه مبلغ خرید از extra_info.totals.net
        totals = extra_info.get('totals') or {}
        net_amount = Decimal(str(totals.get('net', 0) or 0))
        
        supplier_stats[person_id_int]['person_id'] = person_id_int
        supplier_stats[person_id_int]['invoice_count'] += 1
        supplier_stats[person_id_int]['total_purchases'] += net_amount
        
        # به‌روزرسانی آخرین تاریخ خرید
        doc_date = doc.document_date
        if doc_date:
            current_last_date = supplier_stats[person_id_int]['last_purchase_date']
            if current_last_date is None or doc_date > current_last_date:
                supplier_stats[person_id_int]['last_purchase_date'] = doc_date
    
    # Debug: لاگ تعداد فاکتورهای بدون person_id و تعداد تامین‌کنندگان پیدا شده
    if invoices_without_person > 0:
        logger.debug(f"Top suppliers report: {invoices_without_person} invoices without person_id out of {len(purchases_documents)} total")
    logger.debug(f"Top suppliers report: Found {len(person_ids_set)} unique suppliers")
    
    # دریافت اطلاعات شخص‌ها از پایگاه داده
    persons_map = {}
    if person_ids_set:
        persons = db.query(Person).filter(
            and_(
                Person.business_id == business_id,
                Person.id.in_(list(person_ids_set))
            )
        ).all()
        
        for person in persons:
            # ساخت نام نمایشی
            display_name = person.alias_name or ''
            if person.company_name:
                display_name = person.company_name
            elif person.first_name or person.last_name:
                parts = []
                if person.first_name:
                    parts.append(person.first_name)
                if person.last_name:
                    parts.append(person.last_name)
                display_name = ' '.join(parts) if parts else person.alias_name or ''
            
            persons_map[person.id] = {
                'id': person.id,
                'code': person.code,
                'alias_name': person.alias_name,
                'first_name': person.first_name,
                'last_name': person.last_name,
                'company_name': person.company_name,
                'display_name': display_name,
            }
    
    # تبدیل به لیست و مرتب‌سازی بر اساس مبلغ خرید (ترتیب نزولی)
    items = []
    for person_id, stats in supplier_stats.items():
        person_info = persons_map.get(person_id, {})
        
        items.append({
            'person_id': person_id,
            'person_code': person_info.get('code'),
            'person_name': person_info.get('display_name', person_info.get('alias_name', '')),
            'invoice_count': stats['invoice_count'],
            'total_purchases': float(stats['total_purchases']),
            'last_purchase_date': stats['last_purchase_date'].isoformat() if stats['last_purchase_date'] else None,
        })
    
    # مرتب‌سازی بر اساس مبلغ خرید (ترتیب نزولی)
    items.sort(key=lambda x: x['total_purchases'], reverse=True)
    
    # اعمال limit اگر مشخص شده باشد
    if limit is not None and limit > 0:
        items = items[:limit]
    
    # Pagination
    total = len(items)
    current_page = (skip // take) + 1
    total_pages = (total + take - 1) // take if take > 0 else 1
    paginated_items = items[skip:skip + take]
    
    # محاسبه خلاصه
    total_suppliers = len(supplier_stats)
    total_invoice_count = sum(item['invoice_count'] for item in items)
    total_purchases_sum = sum(item['total_purchases'] for item in items)
    
    return {
        'items': paginated_items,
        'summary': {
            'total_count': total,
            'total_suppliers': total_suppliers,
            'total_invoice_count': total_invoice_count,
            'total_purchases': float(total_purchases_sum),
        },
        'pagination': {
            'total': total,
            'page': current_page,
            'per_page': take,
            'total_pages': total_pages,
            'has_next': current_page < total_pages,
            'has_prev': current_page > 1,
        }
    }


def get_materials_consumption_report(
    db: Session,
    business_id: int,
    fiscal_year_id: Optional[int] = None,
    currency_id: Optional[int] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    product_id: Optional[int] = None,
    warehouse_id: Optional[int] = None,
    skip: int = 0,
    take: int = 50,
) -> Dict[str, Any]:
    """
    گزارش مصرف مواد از فاکتورهای تولید
    
    این گزارش خطوط فاکتورهای تولید (invoice_production) که movement: "out" دارند را نمایش می‌دهد.
    این خطوط نشان‌دهنده مواد اولیه مصرف شده در فرآیند تولید هستند.
    
    Args:
        db: نشست پایگاه داده
        business_id: شناسه کسب‌وکار
        fiscal_year_id: شناسه سال مالی (اختیاری)
        currency_id: شناسه ارز (اختیاری)
        date_from: از تاریخ (اختیاری، فرمت YYYY-MM-DD)
        date_to: تا تاریخ (اختیاری، فرمت YYYY-MM-DD)
        product_id: شناسه محصول (اختیاری)
        warehouse_id: شناسه انبار (اختیاری)
        skip: تعداد رکوردهای رد شده برای pagination
        take: تعداد رکوردهای برگشتی
    
    Returns:
        dict: {
            'items': لیست خطوط مصرف مواد,
            'summary': خلاصه آمار,
            'pagination': اطلاعات pagination
        }
    """
    # تبدیل تاریخ‌ها
    date_from_obj = None
    date_to_obj = None
    
    if date_from:
        try:
            date_from_obj = _parse_iso_date(date_from)
        except Exception:
            pass
    
    if date_to:
        try:
            date_to_obj = _parse_iso_date(date_to)
        except Exception:
            pass
    
    # اگر تاریخ‌ها مشخص نشده‌اند، از سال مالی استفاده کن
    if date_from_obj is None or date_to_obj is None:
        try:
            if fiscal_year_id:
                fiscal_year = db.query(FiscalYear).filter(FiscalYear.id == fiscal_year_id).first()
            else:
                fiscal_year = db.query(FiscalYear).filter(
                    and_(
                        FiscalYear.business_id == business_id,
                        FiscalYear.is_last == True
                    )
                ).first()
            
            if fiscal_year:
                if date_from_obj is None:
                    date_from_obj = fiscal_year.start_date
                if date_to_obj is None:
                    date_to_obj = fiscal_year.end_date if fiscal_year.end_date else date.today()
        except Exception:
            pass
    
    # اگر هنوز تاریخ مشخص نشده، از یک بازه زمانی معقول استفاده کن
    if date_to_obj is None:
        date_to_obj = date.today()
    if date_from_obj is None:
        try:
            current_year = date.today().year
            date_from_obj = date(current_year, 1, 1)
        except Exception:
            date_from_obj = date.today()
    
    # Query فاکتورهای تولید
    production_query = db.query(Document).filter(
        and_(
            Document.business_id == business_id,
            Document.document_type == INVOICE_PRODUCTION,
            Document.is_proforma == False,
            Document.document_date >= date_from_obj,
            Document.document_date <= date_to_obj,
        )
    )
    
    if currency_id:
        production_query = production_query.filter(Document.currency_id == currency_id)
    
    if fiscal_year_id:
        production_query = production_query.filter(Document.fiscal_year_id == fiscal_year_id)
    
    production_documents = production_query.order_by(Document.document_date.asc()).all()
    
    doc_ids = [doc.id for doc in production_documents]
    
    if not doc_ids:
        return {
            'items': [],
            'summary': {
                'total_count': 0,
                'total_quantity': 0.0,
                'total_amount': 0.0,
            },
            'pagination': {
                'total': 0,
                'page': 1,
                'per_page': take,
                'total_pages': 1,
                'has_next': False,
                'has_prev': False,
            }
        }
    
    # Query خطوط فاکتورها که movement: "out" دارند (مواد مصرف شده)
    lines_query = db.query(
        InvoiceItemLine,
        Document,
    ).join(
        Document, Document.id == InvoiceItemLine.document_id
    ).filter(
        and_(
            InvoiceItemLine.document_id.in_(doc_ids),
            InvoiceItemLine.product_id.isnot(None),
        )
    )
    
    if product_id:
        lines_query = lines_query.filter(InvoiceItemLine.product_id == product_id)
    
    lines_with_docs = lines_query.all()
    
    # فیلتر کردن خطوطی که movement: "out" دارند
    items = []
    product_ids_set = set()
    warehouse_ids_set = set()
    
    for line, doc in lines_with_docs:
        line_info = line.extra_info or {}
        movement = line_info.get('movement')
        
        # فقط خطوطی که movement: "out" دارند (مواد مصرف شده)
        if movement != 'out':
            continue
        
        # فیلتر انبار
        line_warehouse_id = line_info.get('warehouse_id')
        if warehouse_id and line_warehouse_id != warehouse_id:
            continue
        
        product_ids_set.add(line.product_id)
        if line_warehouse_id:
            warehouse_ids_set.add(line_warehouse_id)
        
        # محاسبه مبلغ
        unit_price = Decimal(str(line_info.get('unit_price', 0) or 0))
        quantity = Decimal(str(line.quantity or 0))
        amount = unit_price * quantity
        
        items.append({
            'document_id': doc.id,
            'document_code': doc.code,
            'document_date': doc.document_date.isoformat() if doc.document_date else None,
            'product_id': line.product_id,
            'warehouse_id': line_warehouse_id,
            'quantity': float(quantity),
            'unit_price': float(unit_price),
            'amount': float(amount),
            'description': line.description,
        })
    
    # دریافت اطلاعات محصولات
    products_map = {}
    if product_ids_set:
        products = db.query(Product).filter(
            and_(
                Product.business_id == business_id,
                Product.id.in_(list(product_ids_set))
            )
        ).all()
        
        for product in products:
            products_map[product.id] = {
                'id': product.id,
                'code': product.code,
                'name': product.name,
                'unit': product.main_unit or "",
            }
    
    # دریافت اطلاعات انبارها
    warehouses_map = {}
    if warehouse_ids_set:
        from adapters.db.models.warehouse import Warehouse
        warehouses = db.query(Warehouse).filter(
            and_(
                Warehouse.business_id == business_id,
                Warehouse.id.in_(list(warehouse_ids_set))
            )
        ).all()
        
        for warehouse in warehouses:
            warehouses_map[warehouse.id] = {
                'id': warehouse.id,
                'code': warehouse.code,
                'name': warehouse.name,
            }
    
    # اضافه کردن اطلاعات محصول و انبار به آیتم‌ها
    for item in items:
        product_info = products_map.get(item['product_id'], {})
        item['product_code'] = product_info.get('code')
        item['product_name'] = product_info.get('name')
        item['product_unit'] = product_info.get('unit')
        
        if item.get('warehouse_id'):
            warehouse_info = warehouses_map.get(item['warehouse_id'], {})
            item['warehouse_code'] = warehouse_info.get('code')
            item['warehouse_name'] = warehouse_info.get('name')
        else:
            item['warehouse_code'] = None
            item['warehouse_name'] = None
    
    # مرتب‌سازی بر اساس تاریخ سند
    items.sort(key=lambda x: (x['document_date'] or '', x['document_code'] or ''))
    
    # Pagination
    total = len(items)
    current_page = (skip // take) + 1
    total_pages = (total + take - 1) // take if take > 0 else 1
    paginated_items = items[skip:skip + take]
    
    # محاسبه خلاصه
    total_quantity_sum = sum(item['quantity'] for item in items)
    total_amount_sum = sum(item['amount'] for item in items)
    
    return {
        'items': paginated_items,
        'summary': {
            'total_count': total,
            'total_quantity': float(total_quantity_sum),
            'total_amount': float(total_amount_sum),
        },
        'pagination': {
            'total': total,
            'page': current_page,
            'per_page': take,
            'total_pages': total_pages,
            'has_next': current_page < total_pages,
            'has_prev': current_page > 1,
        }
    }


def get_production_report(
    db: Session,
    business_id: int,
    fiscal_year_id: Optional[int] = None,
    currency_id: Optional[int] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    product_id: Optional[int] = None,
    warehouse_id: Optional[int] = None,
    skip: int = 0,
    take: int = 50,
) -> Dict[str, Any]:
    """
    گزارش تولید (کالاهای ساخته شده) از فاکتورهای تولید
    
    این گزارش خطوط فاکتورهای تولید (invoice_production) که movement: "in" دارند را نمایش می‌دهد.
    این خطوط نشان‌دهنده کالاهای ساخته شده در فرآیند تولید هستند.
    
    Args:
        db: نشست پایگاه داده
        business_id: شناسه کسب‌وکار
        fiscal_year_id: شناسه سال مالی (اختیاری)
        currency_id: شناسه ارز (اختیاری)
        date_from: از تاریخ (اختیاری، فرمت YYYY-MM-DD)
        date_to: تا تاریخ (اختیاری، فرمت YYYY-MM-DD)
        product_id: شناسه محصول (اختیاری)
        warehouse_id: شناسه انبار (اختیاری)
        skip: تعداد رکوردهای رد شده برای pagination
        take: تعداد رکوردهای برگشتی
    
    Returns:
        dict: {
            'items': لیست خطوط تولید,
            'summary': خلاصه آمار,
            'pagination': اطلاعات pagination
        }
    """
    # تبدیل تاریخ‌ها
    date_from_obj = None
    date_to_obj = None
    
    if date_from:
        try:
            date_from_obj = _parse_iso_date(date_from)
        except Exception:
            pass
    
    if date_to:
        try:
            date_to_obj = _parse_iso_date(date_to)
        except Exception:
            pass
    
    # اگر تاریخ‌ها مشخص نشده‌اند، از سال مالی استفاده کن
    if date_from_obj is None or date_to_obj is None:
        try:
            if fiscal_year_id:
                fiscal_year = db.query(FiscalYear).filter(FiscalYear.id == fiscal_year_id).first()
            else:
                fiscal_year = db.query(FiscalYear).filter(
                    and_(
                        FiscalYear.business_id == business_id,
                        FiscalYear.is_last == True
                    )
                ).first()
            
            if fiscal_year:
                if date_from_obj is None:
                    date_from_obj = fiscal_year.start_date
                if date_to_obj is None:
                    date_to_obj = fiscal_year.end_date if fiscal_year.end_date else date.today()
        except Exception:
            pass
    
    # اگر هنوز تاریخ مشخص نشده، از یک بازه زمانی معقول استفاده کن
    if date_to_obj is None:
        date_to_obj = date.today()
    if date_from_obj is None:
        try:
            current_year = date.today().year
            date_from_obj = date(current_year, 1, 1)
        except Exception:
            date_from_obj = date.today()
    
    # Query فاکتورهای تولید
    production_query = db.query(Document).filter(
        and_(
            Document.business_id == business_id,
            Document.document_type == INVOICE_PRODUCTION,
            Document.is_proforma == False,
            Document.document_date >= date_from_obj,
            Document.document_date <= date_to_obj,
        )
    )
    
    if currency_id:
        production_query = production_query.filter(Document.currency_id == currency_id)
    
    if fiscal_year_id:
        production_query = production_query.filter(Document.fiscal_year_id == fiscal_year_id)
    
    production_documents = production_query.order_by(Document.document_date.asc()).all()
    
    doc_ids = [doc.id for doc in production_documents]
    
    if not doc_ids:
        return {
            'items': [],
            'summary': {
                'total_count': 0,
                'total_quantity': 0.0,
                'total_amount': 0.0,
            },
            'pagination': {
                'total': 0,
                'page': 1,
                'per_page': take,
                'total_pages': 1,
                'has_next': False,
                'has_prev': False,
            }
        }
    
    # Query خطوط فاکتورها که movement: "in" دارند (کالاهای تولید شده)
    lines_query = db.query(
        InvoiceItemLine,
        Document,
    ).join(
        Document, Document.id == InvoiceItemLine.document_id
    ).filter(
        and_(
            InvoiceItemLine.document_id.in_(doc_ids),
            InvoiceItemLine.product_id.isnot(None),
        )
    )
    
    if product_id:
        lines_query = lines_query.filter(InvoiceItemLine.product_id == product_id)
    
    lines_with_docs = lines_query.all()
    
    # فیلتر کردن خطوطی که movement: "in" دارند
    items = []
    product_ids_set = set()
    warehouse_ids_set = set()
    
    for line, doc in lines_with_docs:
        line_info = line.extra_info or {}
        movement = line_info.get('movement')
        
        # فقط خطوطی که movement: "in" دارند (کالاهای تولید شده)
        if movement != 'in':
            continue
        
        # فیلتر انبار
        line_warehouse_id = line_info.get('warehouse_id')
        if warehouse_id and line_warehouse_id != warehouse_id:
            continue
        
        product_ids_set.add(line.product_id)
        if line_warehouse_id:
            warehouse_ids_set.add(line_warehouse_id)
        
        # محاسبه مبلغ
        unit_price = Decimal(str(line_info.get('unit_price', 0) or 0))
        quantity = Decimal(str(line.quantity or 0))
        amount = unit_price * quantity
        
        items.append({
            'document_id': doc.id,
            'document_code': doc.code,
            'document_date': doc.document_date.isoformat() if doc.document_date else None,
            'product_id': line.product_id,
            'warehouse_id': line_warehouse_id,
            'quantity': float(quantity),
            'unit_price': float(unit_price),
            'amount': float(amount),
            'description': line.description,
        })
    
    # دریافت اطلاعات محصولات
    products_map = {}
    if product_ids_set:
        products = db.query(Product).filter(
            and_(
                Product.business_id == business_id,
                Product.id.in_(list(product_ids_set))
            )
        ).all()
        
        for product in products:
            products_map[product.id] = {
                'id': product.id,
                'code': product.code,
                'name': product.name,
                'unit': product.main_unit or "",
            }
    
    # دریافت اطلاعات انبارها
    warehouses_map = {}
    if warehouse_ids_set:
        from adapters.db.models.warehouse import Warehouse
        warehouses = db.query(Warehouse).filter(
            and_(
                Warehouse.business_id == business_id,
                Warehouse.id.in_(list(warehouse_ids_set))
            )
        ).all()
        
        for warehouse in warehouses:
            warehouses_map[warehouse.id] = {
                'id': warehouse.id,
                'code': warehouse.code,
                'name': warehouse.name,
            }
    
    # اضافه کردن اطلاعات محصول و انبار به آیتم‌ها
    for item in items:
        product_info = products_map.get(item['product_id'], {})
        item['product_code'] = product_info.get('code')
        item['product_name'] = product_info.get('name')
        item['product_unit'] = product_info.get('unit')
        
        if item.get('warehouse_id'):
            warehouse_info = warehouses_map.get(item['warehouse_id'], {})
            item['warehouse_code'] = warehouse_info.get('code')
            item['warehouse_name'] = warehouse_info.get('name')
        else:
            item['warehouse_code'] = None
            item['warehouse_name'] = None
    
    # مرتب‌سازی بر اساس تاریخ سند
    items.sort(key=lambda x: (x['document_date'] or '', x['document_code'] or ''))
    
    # Pagination
    total = len(items)
    current_page = (skip // take) + 1
    total_pages = (total + take - 1) // take if take > 0 else 1
    paginated_items = items[skip:skip + take]
    
    # محاسبه خلاصه
    total_quantity_sum = sum(item['quantity'] for item in items)
    total_amount_sum = sum(item['amount'] for item in items)
    
    return {
        'items': paginated_items,
        'summary': {
            'total_count': total,
            'total_quantity': float(total_quantity_sum),
            'total_amount': float(total_amount_sum),
        },
        'pagination': {
            'total': total,
            'page': current_page,
            'per_page': take,
            'total_pages': total_pages,
            'has_next': current_page < total_pages,
            'has_prev': current_page > 1,
        }
    }



def calculate_invoice_remaining(
    db: Session,
    business_id: int,
    invoice_id: int,
) -> Dict[str, Any]:
    """
    محاسبه مانده فاکتور بر اساس تراکنش‌های مرتبط
    
    Args:
        db: Session دیتابیس
        business_id: شناسه کسب‌وکار
        invoice_id: شناسه فاکتور
    
    Returns:
        {
            'invoice_id': int,
            'total_amount': float,
            'paid_amount': float,
            'remaining': float,
            'is_settled': bool
        }
    """
    try:
        logger.info(f"شروع محاسبه مانده فاکتور - invoice_id: {invoice_id}, business_id: {business_id}")
        
        # دریافت فاکتور
        invoice = db.query(Document).filter(
            Document.id == invoice_id,
            Document.business_id == business_id,
        ).first()
        
        if not invoice:
            logger.warning(f"فاکتور یافت نشد - invoice_id: {invoice_id}, business_id: {business_id}")
            raise ApiError("INVOICE_NOT_FOUND", "فاکتور یافت نشد", http_status=404)
        
        logger.info(f"فاکتور یافت شد - code: {invoice.code}, document_type: {invoice.document_type}")
        
        # پاک‌سازی لینک‌های مرده قبل از محاسبه مانده
        try:
            if _cleanup_dead_receipt_payment_links(db, invoice):
                # commit تغییرات
                db.commit()
                db.refresh(invoice)
        except Exception as e:
            logger.warning(f"خطا در پاک‌سازی لینک‌های مرده در calculate_invoice_remaining: {e}")
            db.rollback()
        
        # محاسبه مبلغ کل فاکتور
        total_amount = Decimal(0)
        extra_info = invoice.extra_info or {}
        
        # اول از extra_info.totals.net
        totals = extra_info.get('totals', {})
        if isinstance(totals, dict) and 'net' in totals:
            try:
                total_amount = Decimal(str(totals['net']))
                logger.info(f"total_amount از extra_info.totals.net: {total_amount}")
            except (ValueError, TypeError) as e:
                logger.warning(f"خطا در خواندن totals.net: {e}")
                pass
        
        # اگر total_amount هنوز 0 است، از InvoiceItemLine محاسبه کن
        if total_amount == 0:
            try:
                logger.info("محاسبه total_amount از InvoiceItemLine")
                item_lines = db.query(InvoiceItemLine).filter(
                    InvoiceItemLine.document_id == invoice_id
                ).all()
                
                for item_line in item_lines:
                    item_extra = item_line.extra_info or {}
                    line_total = item_extra.get('line_total')
                    if line_total is not None:
                        total_amount += Decimal(str(line_total))
                    else:
                        # محاسبه از quantity و unit_price
                        qty = Decimal(str(item_line.quantity or 0))
                        unit_price = Decimal(str(item_extra.get('unit_price', 0)))
                        line_discount = Decimal(str(item_extra.get('line_discount', 0)))
                        tax_amount = Decimal(str(item_extra.get('tax_amount', 0)))
                        line_total = (qty * unit_price) - line_discount + tax_amount
                        total_amount += line_total
                logger.info(f"total_amount از InvoiceItemLine: {total_amount}")
            except Exception as e:
                logger.exception(f"خطا در محاسبه total_amount از InvoiceItemLine: {e}")
    
        # محاسبه مبلغ پرداخت شده
        total_paid = Decimal(0)
        processed_doc_ids = set()
        
        # 1. بررسی از طریق links.receipt_payment_document_ids
        links = extra_info.get('links', {})
        receipt_payment_ids = links.get('receipt_payment_document_ids', [])
    
        for doc_id in receipt_payment_ids:
            try:
                doc_id_int = int(doc_id)
                doc = db.query(Document).filter(
                    Document.id == doc_id_int,
                    Document.business_id == business_id,
                    Document.document_type.in_(['receipt', 'payment']),
                ).first()
                
                if not doc:
                    continue
                
                processed_doc_ids.add(doc_id_int)
                
                # مجموع account_lines (بدون کارمزد)
                # account_lines خطوطی هستند که bank_account_id, cash_register_id, petty_cash_id یا check_id دارند
                for line in doc.lines:
                    # بررسی اینکه آیا این خط مربوط به حساب است (نه person)
                    if line.person_id is None and (line.bank_account_id is not None or 
                                                   line.cash_register_id is not None or 
                                                   line.petty_cash_id is not None or 
                                                   line.check_id is not None):
                        line_extra = line.extra_info or {}
                        if not line_extra.get('is_commission_line'):
                            # amount = debit + credit (همیشه یکی از آنها 0 است)
                            line_amount = Decimal(str(line.debit)) + Decimal(str(line.credit))
                            total_paid += line_amount
            except (ValueError, TypeError) as e:
                logger.warning(f"خطا در پردازش receipt_payment_id {doc_id}: {e}")
                continue
        
        # 2. بررسی از طریق person_lines که invoice_id دارند
        # جستجوی receipts-payments که در person_lines به این فاکتور لینک شده‌اند
        # بهینه‌سازی: فقط خطوطی که invoice_id در extra_info دارند را بررسی کن
        receipt_payment_lines = db.query(DocumentLine).join(
            Document, DocumentLine.document_id == Document.id
        ).filter(
            Document.business_id == business_id,
            Document.document_type.in_(['receipt', 'payment']),
            DocumentLine.person_id.isnot(None),
        ).all()
        
        # استخراج document_ids منحصر به فرد
        receipt_payment_doc_ids = set()
        for line in receipt_payment_lines:
            line_extra = line.extra_info or {}
            line_invoice_id = line_extra.get('invoice_id')
            if line_invoice_id is not None:
                try:
                    if isinstance(line_invoice_id, (int, float)):
                        line_invoice_id_int = int(line_invoice_id)
                    else:
                        line_invoice_id_int = int(str(line_invoice_id))
                    
                    if line_invoice_id_int == invoice_id:
                        receipt_payment_doc_ids.add(line.document_id)
                except (ValueError, TypeError):
                    continue
        
        # دریافت documents
        receipt_payment_docs = []
        if receipt_payment_doc_ids:
            receipt_payment_docs = db.query(Document).filter(
                Document.id.in_(list(receipt_payment_doc_ids)),
                Document.business_id == business_id,
            ).all()
        
        for doc in receipt_payment_docs:
            if doc.id in processed_doc_ids:
                continue
            
            # بررسی person_lines (خطوطی که person_id دارند)
            for line in doc.lines:
                if line.person_id is not None:
                    line_extra = line.extra_info or {}
                    line_invoice_id = line_extra.get('invoice_id')
                    
                    # تبدیل به int برای مقایسه
                    if line_invoice_id is not None:
                        try:
                            if isinstance(line_invoice_id, (int, float)):
                                line_invoice_id_int = int(line_invoice_id)
                            else:
                                line_invoice_id_int = int(str(line_invoice_id))
                            
                            if line_invoice_id_int == invoice_id:
                                processed_doc_ids.add(doc.id)
                                
                                # مجموع account_lines (بدون کارمزد)
                                # account_lines خطوطی هستند که bank_account_id, cash_register_id, petty_cash_id یا check_id دارند
                                for acc_line in doc.lines:
                                    if acc_line.person_id is None and (acc_line.bank_account_id is not None or 
                                                                       acc_line.cash_register_id is not None or 
                                                                       acc_line.petty_cash_id is not None or 
                                                                       acc_line.check_id is not None):
                                        acc_extra = acc_line.extra_info or {}
                                        if not acc_extra.get('is_commission_line'):
                                            # amount = debit + credit (همیشه یکی از آنها 0 است)
                                            acc_line_amount = Decimal(str(acc_line.debit)) + Decimal(str(acc_line.credit))
                                            total_paid += acc_line_amount
                                break
                        except (ValueError, TypeError):
                            continue
        
        remaining = total_amount - total_paid
        
        logger.info(f"محاسبه مانده تمام شد - invoice_id: {invoice_id}, total_amount: {total_amount}, paid_amount: {total_paid}, remaining: {remaining}")
        
        return {
            'invoice_id': invoice_id,
            'total_amount': float(total_amount),
            'paid_amount': float(total_paid),
            'remaining': float(remaining),
            'is_settled': float(remaining) <= 0.01,  # tolerance برای خطای ممیز شناور
        }
    except ApiError:
        raise
    except Exception as e:
        logger.exception(f"خطا در محاسبه مانده فاکتور {invoice_id}: {e}")
        raise
