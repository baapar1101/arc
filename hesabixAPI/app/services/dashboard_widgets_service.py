from __future__ import annotations

from typing import Any, Dict, List, Callable, Optional
from datetime import datetime, date, timedelta

from sqlalchemy.orm import Session
from sqlalchemy import and_, func

from adapters.db.models.business_dashboard_layout import (
    BusinessUserDashboardLayout,
    BusinessDashboardDefaultLayout,
)
from adapters.db.models.document import Document
from adapters.db.models.invoice_item_line import InvoiceItemLine
from adapters.db.models.currency import Currency
from adapters.db.models.check import Check, CheckStatus, CheckType
from adapters.db.models.person import Person
from adapters.db.models.product import Product
from app.services.invoice_service import INVOICE_SALES, INVOICE_PURCHASE
from sqlalchemy import or_
from app.core.calendar import CalendarConverter, CalendarType
import jdatetime

# ----------------------------
# Responsive columns per breakpoint
# ----------------------------
COLUMNS_BY_BREAKPOINT: Dict[str, int] = {
    "xs": 4,
    "sm": 6,
    "md": 8,
    "lg": 12,
    "xl": 12,
}


# ----------------------------
# Widget Definitions (Server-side)
# ----------------------------
DEFAULT_WIDGET_DEFINITIONS: List[Dict[str, Any]] = [
    {
        "key": "quick_links",
        "title": "دسترسی سریع",
        "icon": "dashboard_customize",
        "version": 1,
        "permissions_required": [],
        "defaults": {
            "xs": {"colSpan": 4, "rowSpan": 2},
            "sm": {"colSpan": 6, "rowSpan": 2},
            "md": {"colSpan": 4, "rowSpan": 2},
            "lg": {"colSpan": 4, "rowSpan": 2},
            "xl": {"colSpan": 4, "rowSpan": 2},
        },
        "cache_ttl": 10,
    },
    {
        "key": "latest_sales_invoices",
        "title": "آخرین فاکتورهای فروش",
        "icon": "receipt_long",
        "version": 1,
        "permissions_required": ["invoices.view"],
        "defaults": {
            # default colSpan/rowSpan per breakpoint
            "xs": {"colSpan": 4, "rowSpan": 3},
            "sm": {"colSpan": 6, "rowSpan": 3},
            "md": {"colSpan": 4, "rowSpan": 3},
            "lg": {"colSpan": 4, "rowSpan": 3},
            "xl": {"colSpan": 4, "rowSpan": 3},
        },
        "cache_ttl": 30,  # seconds (hint)
    },
    {
        "key": "sales_bar_chart",
        "title": "نمودار فروش",
        "icon": "bar_chart",
        "version": 1,
        "permissions_required": ["invoices.view"],
        "defaults": {
            "xs": {"colSpan": 4, "rowSpan": 4},
            "sm": {"colSpan": 6, "rowSpan": 4},
            "md": {"colSpan": 8, "rowSpan": 4},
            "lg": {"colSpan": 12, "rowSpan": 4},
            "xl": {"colSpan": 12, "rowSpan": 4},
        },
        "cache_ttl": 15,
    },
    {
        "key": "checks_today",
        "title": "چک‌های امروز",
        "icon": "account_balance_wallet",
        "version": 1,
        "permissions_required": ["checks.view"],
        "defaults": {
            "xs": {"colSpan": 4, "rowSpan": 3},
            "sm": {"colSpan": 6, "rowSpan": 3},
            "md": {"colSpan": 4, "rowSpan": 3},
            "lg": {"colSpan": 4, "rowSpan": 3},
            "xl": {"colSpan": 4, "rowSpan": 3},
        },
        "cache_ttl": 60,
    },
    {
        "key": "checks_tomorrow",
        "title": "چک‌های فردا",
        "icon": "account_balance_wallet",
        "version": 1,
        "permissions_required": ["checks.view"],
        "defaults": {
            "xs": {"colSpan": 4, "rowSpan": 3},
            "sm": {"colSpan": 6, "rowSpan": 3},
            "md": {"colSpan": 4, "rowSpan": 3},
            "lg": {"colSpan": 4, "rowSpan": 3},
            "xl": {"colSpan": 4, "rowSpan": 3},
        },
        "cache_ttl": 60,
    },
    {
        "key": "checks_this_month",
        "title": "چک‌های این ماه",
        "icon": "account_balance_wallet",
        "version": 1,
        "permissions_required": ["checks.view"],
        "defaults": {
            "xs": {"colSpan": 4, "rowSpan": 4},
            "sm": {"colSpan": 6, "rowSpan": 4},
            "md": {"colSpan": 8, "rowSpan": 4},
            "lg": {"colSpan": 8, "rowSpan": 4},
            "xl": {"colSpan": 8, "rowSpan": 4},
        },
        "cache_ttl": 60,
    },
    {
        "key": "top_selling_products",
        "title": "کالاهای پرفروش",
        "icon": "trending_up",
        "version": 1,
        "permissions_required": ["invoices.view"],
        "defaults": {
            "xs": {"colSpan": 4, "rowSpan": 4},
            "sm": {"colSpan": 6, "rowSpan": 4},
            "md": {"colSpan": 6, "rowSpan": 4},
            "lg": {"colSpan": 6, "rowSpan": 4},
            "xl": {"colSpan": 6, "rowSpan": 4},
        },
        "cache_ttl": 30,
    },
    # چک‌های سررسید گذشته
    {
        "key": "checks_overdue",
        "title": "چک‌های سررسید گذشته",
        "icon": "warning_amber",
        "version": 1,
        "permissions_required": ["checks.view"],
        "defaults": {
            "xs": {"colSpan": 4, "rowSpan": 3},
            "sm": {"colSpan": 6, "rowSpan": 3},
            "md": {"colSpan": 4, "rowSpan": 3},
            "lg": {"colSpan": 4, "rowSpan": 3},
            "xl": {"colSpan": 4, "rowSpan": 3},
        },
        "cache_ttl": 60,
    },
    # آخرین دریافت و پرداخت‌ها
    {
        "key": "latest_receipts_payments",
        "title": "آخرین دریافت و پرداخت‌ها",
        "icon": "payments",
        "version": 1,
        "permissions_required": ["people_transactions.view"],
        "defaults": {
            "xs": {"colSpan": 4, "rowSpan": 3},
            "sm": {"colSpan": 6, "rowSpan": 3},
            "md": {"colSpan": 4, "rowSpan": 3},
            "lg": {"colSpan": 4, "rowSpan": 3},
            "xl": {"colSpan": 4, "rowSpan": 3},
        },
        "cache_ttl": 30,
    },
    # خلاصه بدهکاران
    {
        "key": "debtors_summary",
        "title": "خلاصه بدهکاران",
        "icon": "person_search",
        "version": 1,
        "permissions_required": ["persons.view"],
        "defaults": {
            "xs": {"colSpan": 4, "rowSpan": 3},
            "sm": {"colSpan": 6, "rowSpan": 3},
            "md": {"colSpan": 4, "rowSpan": 3},
            "lg": {"colSpan": 4, "rowSpan": 3},
            "xl": {"colSpan": 4, "rowSpan": 3},
        },
        "cache_ttl": 60,
    },
    # خلاصه بستانکاران
    {
        "key": "creditors_summary",
        "title": "خلاصه بستانکاران",
        "icon": "groups",
        "version": 1,
        "permissions_required": ["persons.view"],
        "defaults": {
            "xs": {"colSpan": 4, "rowSpan": 3},
            "sm": {"colSpan": 6, "rowSpan": 3},
            "md": {"colSpan": 4, "rowSpan": 3},
            "lg": {"colSpan": 4, "rowSpan": 3},
            "xl": {"colSpan": 4, "rowSpan": 3},
        },
        "cache_ttl": 60,
    },
    # آخرین فاکتورهای خرید
    {
        "key": "latest_purchase_invoices",
        "title": "آخرین فاکتورهای خرید",
        "icon": "shopping_cart",
        "version": 1,
        "permissions_required": ["invoices.view"],
        "defaults": {
            "xs": {"colSpan": 4, "rowSpan": 3},
            "sm": {"colSpan": 6, "rowSpan": 3},
            "md": {"colSpan": 4, "rowSpan": 3},
            "lg": {"colSpan": 4, "rowSpan": 3},
            "xl": {"colSpan": 4, "rowSpan": 3},
        },
        "cache_ttl": 30,
    },
    # بهترین مشتریان
    {
        "key": "top_customers",
        "title": "بهترین مشتریان",
        "icon": "star",
        "version": 1,
        "permissions_required": ["invoices.view"],
        "defaults": {
            "xs": {"colSpan": 4, "rowSpan": 3},
            "sm": {"colSpan": 6, "rowSpan": 3},
            "md": {"colSpan": 4, "rowSpan": 3},
            "lg": {"colSpan": 4, "rowSpan": 3},
            "xl": {"colSpan": 4, "rowSpan": 3},
        },
        "cache_ttl": 60,
    },
    # بهترین تأمین‌کنندگان
    {
        "key": "top_suppliers",
        "title": "بهترین تأمین‌کنندگان",
        "icon": "local_shipping",
        "version": 1,
        "permissions_required": ["invoices.view"],
        "defaults": {
            "xs": {"colSpan": 4, "rowSpan": 3},
            "sm": {"colSpan": 6, "rowSpan": 3},
            "md": {"colSpan": 4, "rowSpan": 3},
            "lg": {"colSpan": 4, "rowSpan": 3},
            "xl": {"colSpan": 4, "rowSpan": 3},
        },
        "cache_ttl": 60,
    },
    # خلاصه سود و زیان
    {
        "key": "pnl_summary",
        "title": "خلاصه سود و زیان",
        "icon": "show_chart",
        "version": 1,
        "permissions_required": ["reports.view"],
        "defaults": {
            "xs": {"colSpan": 4, "rowSpan": 2},
            "sm": {"colSpan": 6, "rowSpan": 2},
            "md": {"colSpan": 4, "rowSpan": 2},
            "lg": {"colSpan": 4, "rowSpan": 2},
            "xl": {"colSpan": 4, "rowSpan": 2},
        },
        "cache_ttl": 60,
    },
    {
        "key": "crm_calendar",
        "title": "تقویم CRM",
        "icon": "calendar_month",
        "version": 1,
        "permissions_required": ["crm.view"],
        "defaults": {
            "xs": {"colSpan": 4, "rowSpan": 4},
            "sm": {"colSpan": 6, "rowSpan": 4},
            "md": {"colSpan": 8, "rowSpan": 4},
            "lg": {"colSpan": 12, "rowSpan": 4},
            "xl": {"colSpan": 12, "rowSpan": 4},
        },
        "cache_ttl": 30,
    },
]


def _check_widget_permissions(
    permissions_required: List[str],
    ctx: Any  # AuthContext
) -> bool:
    """
    بررسی اینکه آیا کاربر دسترسی به تمام permission های مورد نیاز ویجت را دارد یا نه.
    
    Args:
        permissions_required: لیست permission های مورد نیاز (مثل ["invoices.view"])
        ctx: AuthContext برای بررسی دسترسی‌ها
    
    Returns:
        True اگر کاربر دسترسی دارد، False در غیر این صورت
    """
    if not permissions_required:
        # اگر ویجت permission خاصی نیاز ندارد، نمایش داده می‌شود
        return True
    
    # اگر superadmin یا مالک کسب و کار است، دسترسی کامل دارد
    if ctx.is_superadmin() or ctx.is_business_owner():
        return True
    
    # بررسی هر permission
    for perm_str in permissions_required:
        # Parse permission string (مثل "invoices.view" -> section="invoices", action="view")
        if "." not in perm_str:
            # اگر فرمت صحیح نیست، از آن عبور می‌کنیم (برای سازگاری)
            continue
        
        section, action = perm_str.split(".", 1)
        
        # بررسی دسترسی
        if not ctx.has_business_permission(section, action):
            return False
    
    return True


def get_widget_definitions(
    db: Session, 
    business_id: int, 
    user_id: int,
    ctx: Any = None  # AuthContext (اختیاری برای سازگاری با کدهای قدیمی)
) -> Dict[str, Any]:
    """
    Returns available widgets for current user/business along with responsive columns map.
    Widgets are filtered based on user's business permissions.
    
    Args:
        db: Database session
        business_id: Business ID
        user_id: User ID
        ctx: AuthContext for permission checking (optional)
    """
    # اگر ctx ارائه نشده، همه ویجت‌ها را برمی‌گردانیم (برای سازگاری)
    if ctx is None:
        return {
            "columns": COLUMNS_BY_BREAKPOINT,
            "items": DEFAULT_WIDGET_DEFINITIONS,
        }
    
    # فیلتر ویجت‌ها بر اساس دسترسی
    filtered_widgets = []
    for widget_def in DEFAULT_WIDGET_DEFINITIONS:
        permissions_required = widget_def.get("permissions_required", [])
        if _check_widget_permissions(permissions_required, ctx):
            filtered_widgets.append(widget_def)
    
    return {
        "columns": COLUMNS_BY_BREAKPOINT,
        "items": filtered_widgets,
    }


# ----------------------------
# Layout storage (DB): چند worker و رفرش مرورگر — منبع حقیقت پایگاه داده
# ----------------------------

def _normalize_layout_breakpoint(breakpoint: str) -> str:
    bp = (breakpoint or "md").lower()
    if bp not in COLUMNS_BY_BREAKPOINT:
        return "md"
    return bp


def _default_layout_items(breakpoint: str) -> List[Dict[str, Any]]:
    columns = COLUMNS_BY_BREAKPOINT[breakpoint]
    out: List[Dict[str, Any]] = []
    order = 1
    for d in DEFAULT_WIDGET_DEFINITIONS:
        defaults = (d.get("defaults") or {}).get(breakpoint) or {}
        out.append({
            "key": d["key"],
            "order": order,
            "colSpan": int(defaults.get("colSpan", max(1, columns // 2))),
            "rowSpan": int(defaults.get("rowSpan", 2)),
            "hidden": False,
        })
        order += 1
    return out


def _layout_profile_dict(
    bp: str,
    items: List[Dict[str, Any]],
    updated_at: datetime,
) -> Dict[str, Any]:
    columns = COLUMNS_BY_BREAKPOINT[bp]
    return {
        "breakpoint": bp,
        "columns": columns,
        "items": items,
        "version": 2,
        "updated_at": updated_at.isoformat() + "Z",
    }


def get_dashboard_layout_profile(
    db: Session,
    business_id: int,
    user_id: int,
    breakpoint: str,
) -> Dict[str, Any]:
    """
    Returns a profile for the requested breakpoint:
    { breakpoint, columns, items: [{ key, order, colSpan, rowSpan, hidden }] }
    """
    bp = _normalize_layout_breakpoint(breakpoint)
    row = (
        db.query(BusinessUserDashboardLayout)
        .filter(
            BusinessUserDashboardLayout.business_id == business_id,
            BusinessUserDashboardLayout.user_id == user_id,
            BusinessUserDashboardLayout.breakpoint == bp,
        )
        .first()
    )
    if row is not None and row.items is not None:
        stored = list(row.items)  # type: ignore[arg-type]
        return _layout_profile_dict(
            bp,
            sorted(stored, key=lambda x: int(x.get("order", 1))),
            row.updated_at,
        )

    now = datetime.utcnow()
    return _layout_profile_dict(bp, _default_layout_items(bp), now)


def save_dashboard_layout_profile(
    db: Session,
    business_id: int,
    user_id: int,
    breakpoint: str,
    items: List[Dict[str, Any]],
) -> Dict[str, Any]:
    bp = _normalize_layout_breakpoint(breakpoint)
    columns = COLUMNS_BY_BREAKPOINT[bp]
    sanitized: List[Dict[str, Any]] = []
    for it in (items or []):
        try:
            wkey = str(it.get("key"))
            order = int(it.get("order", 1))
            col_span = max(1, min(columns, int(it.get("colSpan", 1))))
            row_span = int(it.get("rowSpan", 1))
            hidden = bool(it.get("hidden", False))
            sanitized.append({
                "key": wkey,
                "order": order,
                "colSpan": col_span,
                "rowSpan": row_span,
                "hidden": hidden,
            })
        except Exception:
            continue
    sanitized = sorted(sanitized, key=lambda x: x.get("order", 1))
    now = datetime.utcnow()
    row = (
        db.query(BusinessUserDashboardLayout)
        .filter(
            BusinessUserDashboardLayout.business_id == business_id,
            BusinessUserDashboardLayout.user_id == user_id,
            BusinessUserDashboardLayout.breakpoint == bp,
        )
        .first()
    )
    if row is None:
        row = BusinessUserDashboardLayout(
            business_id=business_id,
            user_id=user_id,
            breakpoint=bp,
            items=sanitized,
        )
        db.add(row)
    else:
        row.items = sanitized
        row.updated_at = now
    db.flush()
    return _layout_profile_dict(bp, sanitized, row.updated_at)


def get_business_default_layout(
    db: Session,
    business_id: int,
    breakpoint: str,
) -> Dict[str, Any] | None:
    bp = _normalize_layout_breakpoint(breakpoint)
    row = (
        db.query(BusinessDashboardDefaultLayout)
        .filter(
            BusinessDashboardDefaultLayout.business_id == business_id,
            BusinessDashboardDefaultLayout.breakpoint == bp,
        )
        .first()
    )
    if row is None or row.items is None:
        return None
    stored = list(row.items)  # type: ignore[arg-type]
    return _layout_profile_dict(
        bp,
        sorted(stored, key=lambda x: int(x.get("order", 1))),
        row.updated_at,
    )


def save_business_default_layout(
    db: Session,
    business_id: int,
    breakpoint: str,
    items: List[Dict[str, Any]],
) -> Dict[str, Any]:
    bp = _normalize_layout_breakpoint(breakpoint)
    columns = COLUMNS_BY_BREAKPOINT[bp]
    sanitized: List[Dict[str, Any]] = []
    for it in (items or []):
        try:
            wkey = str(it.get("key"))
            order = int(it.get("order", 1))
            col_span = max(1, min(columns, int(it.get("colSpan", 1))))
            row_span = int(it.get("rowSpan", 1))
            hidden = bool(it.get("hidden", False))
            sanitized.append({
                "key": wkey,
                "order": order,
                "colSpan": col_span,
                "rowSpan": row_span,
                "hidden": hidden,
            })
        except Exception:
            continue
    sanitized = sorted(sanitized, key=lambda x: x.get("order", 1))
    now = datetime.utcnow()
    row = (
        db.query(BusinessDashboardDefaultLayout)
        .filter(
            BusinessDashboardDefaultLayout.business_id == business_id,
            BusinessDashboardDefaultLayout.breakpoint == bp,
        )
        .first()
    )
    if row is None:
        row = BusinessDashboardDefaultLayout(
            business_id=business_id,
            breakpoint=bp,
            items=sanitized,
        )
        db.add(row)
    else:
        row.items = sanitized
        row.updated_at = now
    db.flush()
    return _layout_profile_dict(bp, sanitized, row.updated_at)


# ----------------------------
# Data resolvers (Batch)
# ----------------------------
WidgetResolver = Callable[[Session, int, int, Dict[str, Any]], Any]


def _parse_fiscal_year_id(filters: Dict[str, Any]) -> int | None:
    raw = filters.get("fiscal_year_id")
    if raw is None:
        return None
    try:
        return int(raw)
    except (TypeError, ValueError):
        return None


def _fiscal_year_dates_or_none(db: Session, business_id: int, fiscal_year_id: int | None) -> tuple[datetime.date | None, datetime.date | None]:
    """بازهٔ تاریخ سال مالی انتخاب‌شده (متعلق به همین کسب‌وکار)."""
    if fiscal_year_id is None:
        return None, None
    from adapters.db.models.fiscal_year import FiscalYear

    fy = db.query(FiscalYear).filter(
        and_(FiscalYear.id == fiscal_year_id, FiscalYear.business_id == business_id)
    ).first()
    if fy and getattr(fy, "start_date", None) and getattr(fy, "end_date", None):
        return fy.start_date, fy.end_date
    return None, None


def _resolve_latest_sales_invoices(
    db: Session, business_id: int, user_id: int, filters: Dict[str, Any]
) -> Dict[str, Any]:
    """
    Returns latest sales invoices (header-level info).
    """
    limit_raw = filters.get("limit", 10)
    try:
        limit = max(1, min(50, int(limit_raw)))
    except Exception:
        limit = 10

    fy_id = _parse_fiscal_year_id(filters)
    doc_filters = [
        Document.business_id == business_id,
        Document.document_type == INVOICE_SALES,
    ]
    if fy_id is not None:
        doc_filters.append(Document.fiscal_year_id == fy_id)

    # Fetch last N documents with currency info
    q = (
        db.query(
            Document.id,
            Document.code,
            Document.document_date,
            Document.created_at,
            Document.currency_id,
            Currency.code.label("currency_code"),
            Document.extra_info,
        )
        .outerjoin(Currency, Currency.id == Document.currency_id)
        .filter(and_(*doc_filters))
        .order_by(Document.created_at.desc())
        .limit(limit)
    )
    rows = q.all()
    doc_ids = [int(r.id) for r in rows]
    # Count items per document in batch
    items_count_by_doc: Dict[int, int] = {}
    if doc_ids:
        counts = (
            db.query(InvoiceItemLine.document_id, func.count(InvoiceItemLine.id))
            .filter(InvoiceItemLine.document_id.in_(doc_ids))
            .group_by(InvoiceItemLine.document_id)
            .all()
        )
        for did, cnt in counts:
            items_count_by_doc[int(did)] = int(cnt or 0)
    items: List[Dict[str, Any]] = []
    for d in rows:
        extra = d.extra_info or {}
        totals = (extra.get("totals") or {})
        items.append({
            "id": int(d.id),
            "code": d.code,
            "document_date": d.document_date.isoformat() if d.document_date else None,
            "created_at": d.created_at.isoformat() if d.created_at else None,
            "net_amount": float(totals.get("net", 0) or 0),
            "currency_id": int(d.currency_id) if d.currency_id is not None else None,
            "currency_code": d.currency_code,
            "items_count": items_count_by_doc.get(int(d.id), 0),
        })
    return {"items": items}


def _resolve_top_selling_products(
    db: Session, business_id: int, user_id: int, filters: Dict[str, Any]
) -> Dict[str, Any]:
    """
    Returns top selling products by quantity or amount.
    filters:
      - calculation_type: 'quantity' | 'amount' (default: 'amount')
      - limit: number of products to return (default: 10)
      - currency_id: filter by currency (optional, only used when calculation_type is 'amount')
    """
    calculation_type = str(filters.get("calculation_type", "amount")).lower()
    if calculation_type not in ["quantity", "amount"]:
        calculation_type = "amount"
    
    limit_raw = filters.get("limit", 10)
    try:
        limit = max(1, min(50, int(limit_raw)))
    except Exception:
        limit = 10

    # بهینه‌سازی: استفاده از aggregation در SQL برای quantity
    # برای amount، از روش hybrid استفاده می‌کنیم (SQL برای quantity، Python برای amount)
    currency_id = filters.get("currency_id")
    fy_id = _parse_fiscal_year_id(filters)

    doc_base_filters = [
        Document.business_id == business_id,
        Document.document_type == INVOICE_SALES,
        Document.is_proforma == False,  # noqa: E712
    ]
    if fy_id is not None:
        doc_base_filters.append(Document.fiscal_year_id == fy_id)

    # Query برای quantity aggregation در SQL (سریع‌تر)
    quantity_query = (
        db.query(
            Product.id.label("product_id"),
            Product.code.label("product_code"),
            Product.name.label("product_name"),
            func.sum(InvoiceItemLine.quantity).label("total_quantity")
        )
        .join(InvoiceItemLine, InvoiceItemLine.product_id == Product.id)
        .join(Document, Document.id == InvoiceItemLine.document_id)
        .filter(and_(*doc_base_filters))
        .group_by(Product.id, Product.code, Product.name)
    )
    
    # If calculation_type is 'amount', filter by currency_id if provided
    if calculation_type == "amount" and currency_id is not None:
        try:
            currency_id_int = int(currency_id)
            quantity_query = quantity_query.filter(Document.currency_id == currency_id_int)
        except Exception:
            pass
    
    # Order by و limit در SQL
    if calculation_type == "quantity":
        quantity_query = quantity_query.order_by(func.sum(InvoiceItemLine.quantity).desc())
    else:
        # برای amount، ابتدا بر اساس quantity مرتب می‌کنیم (تقریبی)
        quantity_query = quantity_query.order_by(func.sum(InvoiceItemLine.quantity).desc())
    
    # افزایش limit برای amount (چون بعداً بر اساس amount مرتب می‌کنیم)
    query_limit = limit * 3 if calculation_type == "amount" else limit
    quantity_query = quantity_query.limit(query_limit)
    
    # اجرای query
    quantity_rows = quantity_query.all()
    
    # برای amount، باید extra_info را هم بخوانیم
    if calculation_type == "amount":
        product_ids = [int(row.product_id) for row in quantity_rows]
        if product_ids:
            # خواندن extra_info فقط برای product های انتخاب شده
            amount_filters = list(doc_base_filters) + [Product.id.in_(product_ids)]
            amount_query = (
                db.query(
                    Product.id.label("product_id"),
                    InvoiceItemLine.extra_info
                )
                .join(InvoiceItemLine, InvoiceItemLine.product_id == Product.id)
                .join(Document, Document.id == InvoiceItemLine.document_id)
                .filter(and_(*amount_filters))
            )
            if currency_id is not None:
                try:
                    currency_id_int = int(currency_id)
                    amount_query = amount_query.filter(Document.currency_id == currency_id_int)
                except Exception:
                    pass
            
            amount_rows = amount_query.all()
            # Aggregate amount در Python (فقط برای product های انتخاب شده)
            amount_by_product: Dict[int, float] = {}
            for row in amount_rows:
                product_id = int(row.product_id)
                extra_info = row.extra_info or {}
                line_total = float(extra_info.get("line_total", 0) or 0)
                amount_by_product[product_id] = amount_by_product.get(product_id, 0) + line_total
        else:
            amount_by_product = {}
    else:
        amount_by_product = {}
    
    # تبدیل نتایج به فرمت مورد نیاز
    products_list = []
    for row in quantity_rows:
        product_id = int(row.product_id)
        total_quantity = float(row.total_quantity or 0)
        total_amount = amount_by_product.get(product_id, 0.0) if calculation_type == "amount" else 0.0
        
        products_list.append({
            "product_id": product_id,
            "product_code": row.product_code,
            "product_name": row.product_name,
            "total_quantity": total_quantity,
            "total_amount": total_amount,
        })
    
    # برای amount، بر اساس total_amount مرتب می‌کنیم
    if calculation_type == "amount":
        products_list.sort(key=lambda x: x["total_amount"], reverse=True)
        products_list = products_list[:limit]
    
    result = {
        "items": products_list,
        "calculation_type": calculation_type,
        "limit": limit,
    }
    
    if currency_id is not None:
        result["currency_id"] = currency_id
    
    return result


def _resolve_checks_overdue(db: Session, business_id: int, filters: Dict[str, Any]) -> Dict[str, Any]:
    """چک‌های سررسید گذشته (due_date < امروز، وضعیت غیر از CLEARED)."""
    calendar_type = str(filters.get("calendar_type", "gregorian")).lower()
    today = _get_date_by_calendar(calendar_type, is_tomorrow=False)
    limit = int(filters.get("limit", 15))
    q = (
        db.query(
            Check.id,
            Check.check_number,
            Check.amount,
            Check.currency_id,
            Check.type,
            Check.status,
            Check.due_date,
            Check.person_id,
            Person.alias_name.label("person_name"),
            Currency.code.label("currency_code"),
            Currency.title.label("currency_title"),
        )
        .outerjoin(Person, Person.id == Check.person_id)
        .outerjoin(Currency, Currency.id == Check.currency_id)
        .filter(
            and_(
                Check.business_id == business_id,
                func.date(Check.due_date) < today,
                or_(
                    Check.status != CheckStatus.CLEARED,
                    Check.status.is_(None),
                ),
            )
        )
        .order_by(Check.due_date.asc(), Check.amount.desc())
        .limit(limit)
    )
    rows = q.all()
    items = []
    totals_by_currency = {}
    for row in rows:
        currency_code = row.currency_code or "UNKNOWN"
        amount = float(row.amount)
        items.append({
            "id": int(row.id),
            "check_number": row.check_number,
            "amount": amount,
            "currency_code": currency_code,
            "type": row.type.name.lower() if row.type else None,
            "status": row.status.name if row.status else None,
            "due_date": row.due_date.isoformat() if row.due_date else None,
            "person_name": row.person_name,
        })
        totals_by_currency[currency_code] = totals_by_currency.get(currency_code, 0.0) + amount
    return {"items": items, "totals_by_currency": totals_by_currency, "count": len(items)}


def _resolve_latest_receipts_payments(
    db: Session, business_id: int, user_id: int, filters: Dict[str, Any]
) -> Dict[str, Any]:
    """آخرین دریافت و پرداخت‌ها."""
    from app.services.receipt_payment_service import list_receipts_payments
    limit = max(1, min(20, int(filters.get("limit", 10))))
    fiscal_year_id = filters.get("fiscal_year_id")
    query = {"skip": 0, "take": limit, "sort_by": "document_date", "sort_desc": True}
    if fiscal_year_id is not None:
        query["fiscal_year_id"] = int(fiscal_year_id)
    result = list_receipts_payments(db, business_id, query)
    return {"items": result.get("items", [])[:limit], "pagination": result.get("pagination", {})}


def _resolve_debtors_summary(
    db: Session, business_id: int, user_id: int, filters: Dict[str, Any]
) -> Dict[str, Any]:
    """خلاصه بدهکاران (۱۰ نفر اول)."""
    from app.services.person_service import get_debtors_report
    fiscal_year_id = filters.get("fiscal_year_id")
    r = get_debtors_report(
        db, business_id,
        fiscal_year_id=int(fiscal_year_id) if fiscal_year_id is not None else None,
        skip=0, take=10,
    )
    return {
        "items": r.get("items", []),
        "summary": r.get("summary", {}),
        "pagination": r.get("pagination", {}),
    }


def _resolve_creditors_summary(
    db: Session, business_id: int, user_id: int, filters: Dict[str, Any]
) -> Dict[str, Any]:
    """خلاصه بستانکاران (۱۰ نفر اول)."""
    from app.services.person_service import get_creditors_report
    fiscal_year_id = filters.get("fiscal_year_id")
    r = get_creditors_report(
        db, business_id,
        fiscal_year_id=int(fiscal_year_id) if fiscal_year_id is not None else None,
        skip=0, take=10,
    )
    return {
        "items": r.get("items", []),
        "summary": r.get("summary", {}),
        "pagination": r.get("pagination", {}),
    }


def _resolve_latest_purchase_invoices(
    db: Session, business_id: int, user_id: int, filters: Dict[str, Any]
) -> Dict[str, Any]:
    """آخرین فاکتورهای خرید (مشابه آخرین فاکتورهای فروش)."""
    limit_raw = filters.get("limit", 10)
    try:
        limit = max(1, min(50, int(limit_raw)))
    except Exception:
        limit = 10

    fy_id = _parse_fiscal_year_id(filters)
    doc_filters = [
        Document.business_id == business_id,
        Document.document_type == INVOICE_PURCHASE,
    ]
    if fy_id is not None:
        doc_filters.append(Document.fiscal_year_id == fy_id)

    q = (
        db.query(
            Document.id,
            Document.code,
            Document.document_date,
            Document.created_at,
            Document.currency_id,
            Currency.code.label("currency_code"),
            Document.extra_info,
        )
        .outerjoin(Currency, Currency.id == Document.currency_id)
        .filter(and_(*doc_filters))
        .order_by(Document.created_at.desc())
        .limit(limit)
    )
    rows = q.all()
    doc_ids = [int(r.id) for r in rows]
    items_count_by_doc = {}
    if doc_ids:
        counts = (
            db.query(InvoiceItemLine.document_id, func.count(InvoiceItemLine.id))
            .filter(InvoiceItemLine.document_id.in_(doc_ids))
            .group_by(InvoiceItemLine.document_id)
            .all()
        )
        for did, cnt in counts:
            items_count_by_doc[int(did)] = int(cnt or 0)
    items = []
    for d in rows:
        extra = d.extra_info or {}
        totals = extra.get("totals") or {}
        items.append({
            "id": int(d.id),
            "code": d.code,
            "document_date": d.document_date.isoformat() if d.document_date else None,
            "created_at": d.created_at.isoformat() if d.created_at else None,
            "net_amount": float(totals.get("net", 0) or 0),
            "currency_id": int(d.currency_id) if d.currency_id is not None else None,
            "currency_code": d.currency_code,
            "items_count": items_count_by_doc.get(int(d.id), 0),
        })
    return {"items": items}


def _resolve_top_customers(
    db: Session, business_id: int, user_id: int, filters: Dict[str, Any]
) -> Dict[str, Any]:
    """بهترین مشتریان (۱۰ نفر اول)."""
    from app.services.invoice_service import get_top_customers_report
    fiscal_year_id = filters.get("fiscal_year_id")
    r = get_top_customers_report(
        db, business_id,
        fiscal_year_id=int(fiscal_year_id) if fiscal_year_id is not None else None,
        skip=0, take=10,
    )
    return {"items": r.get("items", []), "summary": r.get("summary", {}), "pagination": r.get("pagination", {})}


def _resolve_top_suppliers(
    db: Session, business_id: int, user_id: int, filters: Dict[str, Any]
) -> Dict[str, Any]:
    """بهترین تأمین‌کنندگان (۱۰ نفر اول)."""
    from app.services.invoice_service import get_top_suppliers_report
    fiscal_year_id = filters.get("fiscal_year_id")
    r = get_top_suppliers_report(
        db, business_id,
        fiscal_year_id=int(fiscal_year_id) if fiscal_year_id is not None else None,
        skip=0, take=10,
    )
    return {"items": r.get("items", []), "summary": r.get("summary", {}), "pagination": r.get("pagination", {})}


def _resolve_pnl_summary(
    db: Session, business_id: int, user_id: int, filters: Dict[str, Any]
) -> Dict[str, Any]:
    """خلاصه سود و زیان دوره (ماه جاری یا سال مالی)."""
    from app.services.pnl_service import get_pnl_period_report
    fiscal_year_id = filters.get("fiscal_year_id")
    date_from = filters.get("date_from")
    date_to = filters.get("date_to")
    r = get_pnl_period_report(
        db, business_id,
        fiscal_year_id=int(fiscal_year_id) if fiscal_year_id is not None else None,
        date_from=date_from,
        date_to=date_to,
        skip=0, take=1,
    )
    return {"summary": r.get("summary", {}), "date_from": date_from, "date_to": date_to}


WIDGET_RESOLVERS: Dict[str, WidgetResolver] = {
    "latest_sales_invoices": _resolve_latest_sales_invoices,
    "sales_bar_chart": lambda db, business_id, user_id, filters: _resolve_sales_bar_chart(db, business_id, filters),
    "checks_today": lambda db, business_id, user_id, filters: _resolve_checks_today(db, business_id, filters),
    "checks_tomorrow": lambda db, business_id, user_id, filters: _resolve_checks_tomorrow(db, business_id, filters),
    "checks_this_month": lambda db, business_id, user_id, filters: _resolve_checks_this_month(db, business_id, filters),
    "top_selling_products": _resolve_top_selling_products,
    "checks_overdue": lambda db, business_id, user_id, filters: _resolve_checks_overdue(db, business_id, filters),
    "latest_receipts_payments": _resolve_latest_receipts_payments,
    "debtors_summary": _resolve_debtors_summary,
    "creditors_summary": _resolve_creditors_summary,
    "latest_purchase_invoices": _resolve_latest_purchase_invoices,
    "top_customers": _resolve_top_customers,
    "top_suppliers": _resolve_top_suppliers,
    "pnl_summary": _resolve_pnl_summary,
}


def get_widgets_batch_data(
    db: Session,
    business_id: int,
    user_id: int,
    widget_keys: List[str],
    filters: Dict[str, Any],
    calendar_type: str = "gregorian",
    auth_ctx: Optional[Any] = None,
) -> Dict[str, Any]:
    """
    Returns a map: { widget_key: data or error } for requested widget_keys.
    calendar_type: "jalali" or "gregorian" - used for date calculations in check widgets
    auth_ctx: برای ویجت‌هایی مثل quick_links که به مجوز نیاز دارند
    """
    from adapters.db.models.user import User
    from app.core.auth_dependency import AuthContext
    from app.services.business_quick_links_service import build_quick_links_widget_data

    result: Dict[str, Any] = {}
    filters_with_calendar = dict(filters or {})
    filters_with_calendar["calendar_type"] = calendar_type
    for key in widget_keys:
        if key == "quick_links":
            ctx = auth_ctx
            if ctx is None:
                u = db.get(User, user_id)
                if u is None:
                    result[key] = {"error": "NO_USER"}
                    continue
                ctx = AuthContext(user=u, api_key_id=0, business_id=business_id, db=db)
            try:
                result[key] = build_quick_links_widget_data(db, business_id, user_id, ctx)
            except Exception as ex:
                result[key] = {"error": str(ex)}
            continue
        if key == "crm_calendar":
            ctx = auth_ctx
            if ctx is None:
                u = db.get(User, user_id)
                if u is None:
                    result[key] = {"error": "NO_USER", "events": []}
                    continue
                ctx = AuthContext(user=u, api_key_id=0, business_id=business_id, db=db)
            try:
                result[key] = _resolve_crm_calendar(db, business_id, ctx, filters_with_calendar)
            except Exception as ex:
                result[key] = {"error": str(ex), "events": []}
            continue
        resolver = WIDGET_RESOLVERS.get(key)
        if not resolver:
            result[key] = {"error": "UNKNOWN_WIDGET"}
            continue
        try:
            result[key] = resolver(db, business_id, user_id, filters_with_calendar)
        except Exception as ex:
            # Avoid breaking the whole dashboard; return error per widget
            result[key] = {"error": str(ex)}
    return result


def _parse_date_str(s: str) -> datetime.date | None:
    try:
        from datetime import datetime as _dt
        s = s.replace('Z', '')
        return _dt.fromisoformat(s).date()
    except Exception:
        try:
            from datetime import datetime as _dt
            return _dt.strptime(s, "%Y-%m-%d").date()
        except Exception:
            return None


def _get_fiscal_range(db: Session, business_id: int) -> tuple[datetime.date, datetime.date]:
    from adapters.db.models.fiscal_year import FiscalYear
    fy = db.query(FiscalYear).filter(
        and_(FiscalYear.business_id == business_id, FiscalYear.is_last == True)  # noqa: E712
    ).first()
    if fy and getattr(fy, "start_date", None) and getattr(fy, "end_date", None):
        return (fy.start_date, fy.end_date)
    # fallback: current year
    today = datetime.utcnow().date()
    start = datetime(today.year, 1, 1).date()
    end = datetime(today.year, 12, 31).date()
    return (start, end)


def _resolve_sales_bar_chart(db: Session, business_id: int, filters: Dict[str, Any]) -> Dict[str, Any]:
    """
    Aggregates sales net amounts per day over a date range.
    filters:
      - range: 'week' | 'month' | 'fiscal' | 'custom'
      - from: ISO date (YYYY-MM-DD)
      - to: ISO date
      - fiscal_year_id: با هدر داشبورد؛ بازهٔ fiscal و فیلتر اسناد را هم‌تراز می‌کند.
    """
    from datetime import timedelta
    rng = str(filters.get("range") or "week").lower()
    group = str(filters.get("group") or "day").lower()  # day | week | month
    today = datetime.utcnow().date()
    start_date: datetime.date
    end_date: datetime.date
    fy_id = _parse_fiscal_year_id(filters)

    if rng == "week":
        # last 7 days including today
        end_date = today
        start_date = today - timedelta(days=6)
    elif rng == "month":
        end_date = today
        start_date = today.replace(day=1)
    elif rng == "fiscal":
        fs, fe = _fiscal_year_dates_or_none(db, business_id, fy_id)
        if fs is not None and fe is not None:
            start_date, end_date = fs, fe
        else:
            start_date, end_date = _get_fiscal_range(db, business_id)
    elif rng == "custom":
        from_s = str(filters.get("from") or "")
        to_s = str(filters.get("to") or "")
        sd = _parse_date_str(from_s)
        ed = _parse_date_str(to_s)
        if sd is None or ed is None:
            end_date = today
            start_date = today - timedelta(days=6)
        else:
            start_date, end_date = sd, ed
    else:
        end_date = today
        start_date = today - timedelta(days=6)

    doc_chart_filters = [
        Document.business_id == business_id,
        Document.document_type == INVOICE_SALES,
        Document.is_proforma == False,  # noqa: E712
        Document.document_date >= start_date,
        Document.document_date <= end_date,
    ]
    if fy_id is not None:
        doc_chart_filters.append(Document.fiscal_year_id == fy_id)

    q = (
        db.query(
            Document.document_date,
            Document.extra_info,
        )
        .filter(and_(*doc_chart_filters))
        .order_by(Document.document_date.asc())
    )
    rows = q.all()
    from collections import defaultdict
    agg: Dict[str, float] = defaultdict(float)
    for doc_date, extra in rows:
        if not doc_date:
            continue
        totals = (extra or {}).get("totals") or {}
        net = float(totals.get("net", 0) or 0)
        if group == "month":
            key = f"{doc_date.year:04d}-{doc_date.month:02d}"
        elif group == "week":
            # ISO week number
            key = f"{doc_date.isocalendar()[0]:04d}-{doc_date.isocalendar()[1]:02d}"
        else:
            key = doc_date.isoformat()
        agg[key] += net

    data: List[Dict[str, Any]] = []
    if group == "day":
        # fill all dates in range
        cur = start_date
        while cur <= end_date:
            key = cur.isoformat()
            data.append({"date": key, "amount": float(agg.get(key, 0.0))})
            cur += timedelta(days=1)
    else:
        # just return aggregated keys sorted
        for key in sorted(agg.keys()):
            data.append({"key": key, "amount": float(agg[key])})

    return {
        "items": data,
        "range": rng,
        "from": start_date.isoformat(),
        "to": end_date.isoformat(),
        "group": group,
    }


def _resolve_checks_by_due_date(
    db: Session, business_id: int, target_date: datetime.date, limit: int = 15
) -> Dict[str, Any]:
    """
    Helper function to resolve checks by due date.
    Returns checks that are not CLEARED and have due_date matching target_date.
    """
    from sqlalchemy import or_
    
    # Query checks with due_date matching target_date, excluding CLEARED status
    q = (
        db.query(
            Check.id,
            Check.check_number,
            Check.amount,
            Check.currency_id,
            Check.type,
            Check.status,
            Check.due_date,
            Check.person_id,
            Person.alias_name.label("person_name"),
            Currency.code.label("currency_code"),
            Currency.title.label("currency_title"),
        )
        .outerjoin(Person, Person.id == Check.person_id)
        .outerjoin(Currency, Currency.id == Check.currency_id)
        .filter(
            and_(
                Check.business_id == business_id,
                func.date(Check.due_date) == target_date,
                or_(
                    Check.status != CheckStatus.CLEARED,
                    Check.status.is_(None),
                ),
            )
        )
        .order_by(Check.due_date.asc(), Check.amount.desc())
        .limit(limit)
    )
    
    rows = q.all()
    items: List[Dict[str, Any]] = []
    totals_by_currency: Dict[str, float] = {}
    
    for row in rows:
        currency_code = row.currency_code or "UNKNOWN"
        currency_title = row.currency_title or currency_code
        amount = float(row.amount)
        
        items.append({
            "id": int(row.id),
            "check_number": row.check_number,
            "amount": amount,
            "currency_id": int(row.currency_id) if row.currency_id else None,
            "currency_code": currency_code,
            "currency_title": currency_title,
            "type": row.type.name.lower() if row.type else None,
            "status": row.status.name if row.status else None,
            "due_date": row.due_date.isoformat() if row.due_date else None,
            "person_id": int(row.person_id) if row.person_id else None,
            "person_name": row.person_name,
        })
        
        # Aggregate totals by currency
        if currency_code not in totals_by_currency:
            totals_by_currency[currency_code] = 0.0
        totals_by_currency[currency_code] += amount
    
    return {
        "items": items,
        "totals_by_currency": totals_by_currency,
        "count": len(items),
    }


def _get_date_by_calendar(calendar_type: str, is_tomorrow: bool = False) -> date:
    """
    Get today or tomorrow date based on user's calendar type.
    If jalali, calculates in jalali calendar and converts to gregorian for DB query.
    """
    if calendar_type == "jalali":
        jalali_now = jdatetime.datetime.now()
        if is_tomorrow:
            # Get tomorrow in jalali calendar
            jalali_tomorrow = jalali_now + timedelta(days=1)
            # Convert to gregorian for DB query
            gregorian_tomorrow = jalali_tomorrow.togregorian()
            return date(gregorian_tomorrow.year, gregorian_tomorrow.month, gregorian_tomorrow.day)
        else:
            # Convert today to gregorian for DB query
            gregorian_today = jalali_now.togregorian()
            return date(gregorian_today.year, gregorian_today.month, gregorian_today.day)
    else:
        # Gregorian calendar
        if is_tomorrow:
            return date.today() + timedelta(days=1)
        else:
            return date.today()


def _get_month_range_by_calendar(calendar_type: str) -> tuple[date, date]:
    """
    Get start and end date of current month based on user's calendar type.
    Returns gregorian dates for DB query.
    """
    if calendar_type == "jalali":
        jalali_now = jdatetime.datetime.now()
        # Start of current jalali month
        jalali_start = jdatetime.datetime(jalali_now.year, jalali_now.month, 1)
        # End of current jalali month
        days_in_month = jdatetime.j_days_in_month[jalali_now.month - 1]
        if jalali_now.month == 12 and jalali_now.isleap():
            days_in_month = 30  # Leap year in jalali
        jalali_end = jdatetime.datetime(jalali_now.year, jalali_now.month, days_in_month)
        
        # Convert to gregorian
        greg_start = jalali_start.togregorian()
        greg_end = jalali_end.togregorian()
        return (
            date(greg_start.year, greg_start.month, greg_start.day),
            date(greg_end.year, greg_end.month, greg_end.day),
        )
    else:
        # Gregorian calendar
        today = date.today()
        start_date = date(today.year, today.month, 1)
        if today.month == 12:
            end_date = date(today.year + 1, 1, 1) - timedelta(days=1)
        else:
            end_date = date(today.year, today.month + 1, 1) - timedelta(days=1)
        return (start_date, end_date)


def _crm_calendar_resolve_month_range(filters: Dict[str, Any]) -> tuple[date, date, int, int]:
    """
    بازهٔ یک ماه در تقویم نمایشی کاربر (شمسی/میلادی) به تاریخ میلادی برای کوئری DB.
    خروجی: (شروع میلادی، پایان میلادی، سال نمایشی، ماه نمایشی).
    """
    calendar_type = str(filters.get("calendar_type", "gregorian")).lower()
    y_raw, m_raw = filters.get("crm_calendar_year"), filters.get("crm_calendar_month")
    if calendar_type == "jalali":
        if y_raw is not None and m_raw is not None:
            y, m = int(y_raw), int(m_raw)
        else:
            jn = jdatetime.datetime.now()
            y, m = int(jn.year), int(jn.month)
        jalali_start = jdatetime.datetime(y, m, 1)
        days_in_month = jdatetime.j_days_in_month[m - 1]
        if m == 12 and jalali_start.isleap():
            days_in_month = 30
        jalali_end = jdatetime.datetime(y, m, days_in_month)
        gs = jalali_start.togregorian()
        ge = jalali_end.togregorian()
        return (
            date(gs.year, gs.month, gs.day),
            date(ge.year, ge.month, ge.day),
            y,
            m,
        )
    if y_raw is not None and m_raw is not None:
        gy, gm = int(y_raw), int(m_raw)
    else:
        t = date.today()
        gy, gm = t.year, t.month
    start_date = date(gy, gm, 1)
    if gm == 12:
        end_date = date(gy, 12, 31)
    else:
        end_date = date(gy, gm + 1, 1) - timedelta(days=1)
    return (start_date, end_date, gy, gm)


def _resolve_crm_calendar(
    db: Session,
    business_id: int,
    ctx: Any,
    filters: Dict[str, Any],
) -> Dict[str, Any]:
    """فعالیت‌ها و یادداشت‌های تقویم CRM در بازهٔ یک ماه (تقویم نمایشی کاربر)."""
    from datetime import datetime, time
    from adapters.db.models.crm import CrmActivity
    from app.services import crm_calendar_note_service as crm_cal_notes

    if ctx is None:
        return {"error": "NO_CONTEXT", "events": []}

    if (
        not ctx.is_superadmin()
        and not ctx.is_business_owner(business_id)
        and not ctx.has_business_permission("crm", "view")
    ):
        return {
            "events": [],
            "month_start": None,
            "month_end": None,
            "display_year": None,
            "display_month": None,
            "forbidden": True,
        }

    start_d, end_d, disp_y, disp_m = _crm_calendar_resolve_month_range(filters)
    start_dt = datetime.combine(start_d, time.min)
    end_dt_excl = datetime.combine(end_d + timedelta(days=1), time.min)

    activities = (
        db.query(CrmActivity)
        .filter(
            CrmActivity.business_id == business_id,
            CrmActivity.activity_date >= start_dt,
            CrmActivity.activity_date < end_dt_excl,
        )
        .order_by(CrmActivity.activity_date.asc())
        .limit(500)
        .all()
    )
    events: List[Dict[str, Any]] = []
    for a in activities:
        ad = a.activity_date
        if ad is None:
            continue
        day_g = ad.date() if isinstance(ad, datetime) else ad
        events.append({
            "kind": "activity",
            "id": a.id,
            "at": ad.isoformat() if hasattr(ad, "isoformat") else str(ad),
            "day": day_g.isoformat(),
            "title": (a.subject or "").strip() or (a.activity_type or ""),
            "activity_type": a.activity_type,
        })

    lang = getattr(ctx, "language", None) or "fa"
    try:
        notes = crm_cal_notes.list_notes(db, ctx, business_id, start_d, end_d, lang)
    except Exception:
        notes = []
    for n in notes:
        od = n.get("occurs_on")
        if isinstance(od, date):
            day_s = od.isoformat()
        elif isinstance(od, datetime):
            day_s = od.date().isoformat()
        elif isinstance(od, str):
            day_s = od[:10]
        else:
            continue
        title = (n.get("title") or n.get("note_type_title") or "")
        if isinstance(title, str):
            title = title.strip()
        events.append({
            "kind": "note",
            "id": n.get("id"),
            "day": day_s,
            "title": title or (n.get("note_type_title") or ""),
            "note_type_title": n.get("note_type_title"),
        })

    return {
        "events": events,
        "month_start": start_d.isoformat(),
        "month_end": end_d.isoformat(),
        "display_year": disp_y,
        "display_month": disp_m,
        "calendar_type": str(filters.get("calendar_type", "gregorian")).lower(),
    }


def _resolve_checks_today(db: Session, business_id: int, filters: Dict[str, Any]) -> Dict[str, Any]:
    """
    Returns checks due today (excluding CLEARED status).
    Uses user's calendar type to determine "today".
    """
    calendar_type = str(filters.get("calendar_type", "gregorian")).lower()
    today = _get_date_by_calendar(calendar_type, is_tomorrow=False)
    limit = int(filters.get("limit", 15))
    return _resolve_checks_by_due_date(db, business_id, today, limit)


def _resolve_checks_tomorrow(db: Session, business_id: int, filters: Dict[str, Any]) -> Dict[str, Any]:
    """
    Returns checks due tomorrow (excluding CLEARED status).
    Uses user's calendar type to determine "tomorrow".
    """
    calendar_type = str(filters.get("calendar_type", "gregorian")).lower()
    tomorrow = _get_date_by_calendar(calendar_type, is_tomorrow=True)
    limit = int(filters.get("limit", 15))
    return _resolve_checks_by_due_date(db, business_id, tomorrow, limit)


def _resolve_checks_this_month(db: Session, business_id: int, filters: Dict[str, Any]) -> Dict[str, Any]:
    """
    Returns checks due this month (excluding CLEARED status).
    Uses user's calendar type to determine current month.
    """
    from sqlalchemy import or_
    
    calendar_type = str(filters.get("calendar_type", "gregorian")).lower()
    start_date, end_date = _get_month_range_by_calendar(calendar_type)
    
    limit = int(filters.get("limit", 15))
    
    # Query checks with due_date in this month, excluding CLEARED status
    q = (
        db.query(
            Check.id,
            Check.check_number,
            Check.amount,
            Check.currency_id,
            Check.type,
            Check.status,
            Check.due_date,
            Check.person_id,
            Person.alias_name.label("person_name"),
            Currency.code.label("currency_code"),
            Currency.title.label("currency_title"),
        )
        .outerjoin(Person, Person.id == Check.person_id)
        .outerjoin(Currency, Currency.id == Check.currency_id)
        .filter(
            and_(
                Check.business_id == business_id,
                func.date(Check.due_date) >= start_date,
                func.date(Check.due_date) <= end_date,
                or_(
                    Check.status != CheckStatus.CLEARED,
                    Check.status.is_(None),
                ),
            )
        )
        .order_by(Check.due_date.asc(), Check.amount.desc())
        .limit(limit)
    )
    
    rows = q.all()
    items: List[Dict[str, Any]] = []
    totals_by_currency: Dict[str, float] = {}
    
    for row in rows:
        currency_code = row.currency_code or "UNKNOWN"
        currency_title = row.currency_title or currency_code
        amount = float(row.amount)
        
        items.append({
            "id": int(row.id),
            "check_number": row.check_number,
            "amount": amount,
            "currency_id": int(row.currency_id) if row.currency_id else None,
            "currency_code": currency_code,
            "currency_title": currency_title,
            "type": row.type.name.lower() if row.type else None,
            "status": row.status.name if row.status else None,
            "due_date": row.due_date.isoformat() if row.due_date else None,
            "person_id": int(row.person_id) if row.person_id else None,
            "person_name": row.person_name,
        })
        
        # Aggregate totals by currency
        if currency_code not in totals_by_currency:
            totals_by_currency[currency_code] = 0.0
        totals_by_currency[currency_code] += amount
    
    return {
        "items": items,
        "totals_by_currency": totals_by_currency,
        "count": len(items),
        "start_date": start_date.isoformat(),
        "end_date": end_date.isoformat(),
    }


