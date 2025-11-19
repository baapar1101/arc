from __future__ import annotations

from typing import Any, Dict, List, Callable
from datetime import datetime, date, timedelta

from sqlalchemy.orm import Session
from sqlalchemy import and_, func

from adapters.db.models.document import Document
from adapters.db.models.invoice_item_line import InvoiceItemLine
from adapters.db.models.currency import Currency
from adapters.db.models.check import Check, CheckStatus, CheckType
from adapters.db.models.person import Person
from app.services.invoice_service import INVOICE_SALES
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
]


def get_widget_definitions(db: Session, business_id: int, user_id: int) -> Dict[str, Any]:
    """
    Returns available widgets for current user/business along with responsive columns map.
    NOTE: Permission filtering can be added by checking user's business permissions.
    """
    return {
        "columns": COLUMNS_BY_BREAKPOINT,
        "items": DEFAULT_WIDGET_DEFINITIONS,
    }


# ----------------------------
# Layout Storage (in-memory for now)
# In production, persist in DB (e.g., dashboard_layouts table or settings)
# ----------------------------
_IN_MEMORY_LAYOUTS: Dict[str, Dict[str, Any]] = {}
_IN_MEMORY_DEFAULTS: Dict[str, Dict[str, Any]] = {}


def _layout_key(business_id: int, user_id: int, breakpoint: str) -> str:
    return f"{business_id}:{user_id}:{breakpoint}"

def _default_key(business_id: int, breakpoint: str) -> str:
    return f"{business_id}:DEFAULT:{breakpoint}"

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
    bp = (breakpoint or "md").lower()
    if bp not in COLUMNS_BY_BREAKPOINT:
        bp = "md"
    key = _layout_key(business_id, user_id, bp)
    found = _IN_MEMORY_LAYOUTS.get(key)
    if found:
        return found

    # Build default layout from definitions
    columns = COLUMNS_BY_BREAKPOINT[bp]
    items: List[Dict[str, Any]] = []
    order = 1
    for d in DEFAULT_WIDGET_DEFINITIONS:
        defaults = (d.get("defaults") or {}).get(bp) or {}
        items.append({
            "key": d["key"],
            "order": order,
            "colSpan": int(defaults.get("colSpan", max(1, columns // 2))),
            "rowSpan": int(defaults.get("rowSpan", 2)),
            "hidden": False,
        })
        order += 1
    profile = {
        "breakpoint": bp,
        "columns": columns,
        "items": items,
        "version": 2,
        "updated_at": datetime.utcnow().isoformat() + "Z",
    }
    _IN_MEMORY_LAYOUTS[key] = profile
    return profile


def save_dashboard_layout_profile(
    db: Session,
    business_id: int,
    user_id: int,
    breakpoint: str,
    items: List[Dict[str, Any]],
) -> Dict[str, Any]:
    bp = (breakpoint or "md").lower()
    if bp not in COLUMNS_BY_BREAKPOINT:
        bp = "md"
    columns = COLUMNS_BY_BREAKPOINT[bp]
    sanitized: List[Dict[str, Any]] = []
    for it in (items or []):
        try:
            key = str(it.get("key"))
            order = int(it.get("order", 1))
            col_span = max(1, min(columns, int(it.get("colSpan", 1))))
            row_span = int(it.get("rowSpan", 1))
            hidden = bool(it.get("hidden", False))
            sanitized.append({
                "key": key,
                "order": order,
                "colSpan": col_span,
                "rowSpan": row_span,
                "hidden": hidden,
            })
        except Exception:
            continue
    profile = {
        "breakpoint": bp,
        "columns": columns,
        "items": sorted(sanitized, key=lambda x: x.get("order", 1)),
        "version": 2,
        "updated_at": datetime.utcnow().isoformat() + "Z",
    }
    _IN_MEMORY_LAYOUTS[_layout_key(business_id, user_id, bp)] = profile
    return profile


def get_business_default_layout(
    db: Session,
    business_id: int,
    breakpoint: str,
) -> Dict[str, Any] | None:
    bp = (breakpoint or "md").lower()
    if bp not in COLUMNS_BY_BREAKPOINT:
        bp = "md"
    key = _default_key(business_id, bp)
    return _IN_MEMORY_DEFAULTS.get(key)


def save_business_default_layout(
    db: Session,
    business_id: int,
    breakpoint: str,
    items: List[Dict[str, Any]],
) -> Dict[str, Any]:
    bp = (breakpoint or "md").lower()
    if bp not in COLUMNS_BY_BREAKPOINT:
        bp = "md"
    columns = COLUMNS_BY_BREAKPOINT[bp]
    sanitized: List[Dict[str, Any]] = []
    for it in (items or []):
        try:
            key = str(it.get("key"))
            order = int(it.get("order", 1))
            col_span = max(1, min(columns, int(it.get("colSpan", 1))))
            row_span = int(it.get("rowSpan", 1))
            hidden = bool(it.get("hidden", False))
            sanitized.append({
                "key": key,
                "order": order,
                "colSpan": col_span,
                "rowSpan": row_span,
                "hidden": hidden,
            })
        except Exception:
            continue
    profile = {
        "breakpoint": bp,
        "columns": columns,
        "items": sorted(sanitized, key=lambda x: x.get("order", 1)),
        "version": 2,
        "updated_at": datetime.utcnow().isoformat() + "Z",
    }
    _IN_MEMORY_DEFAULTS[_default_key(business_id, bp)] = profile
    return profile


# ----------------------------
# Data resolvers (Batch)
# ----------------------------
WidgetResolver = Callable[[Session, int, int, Dict[str, Any]], Any]


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
        .filter(
            and_(
                Document.business_id == business_id,
                Document.document_type == INVOICE_SALES,
            )
        )
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


WIDGET_RESOLVERS: Dict[str, WidgetResolver] = {
    "latest_sales_invoices": _resolve_latest_sales_invoices,
    "sales_bar_chart": lambda db, business_id, user_id, filters: _resolve_sales_bar_chart(db, business_id, filters),
    "checks_today": lambda db, business_id, user_id, filters: _resolve_checks_today(db, business_id, filters),
    "checks_tomorrow": lambda db, business_id, user_id, filters: _resolve_checks_tomorrow(db, business_id, filters),
    "checks_this_month": lambda db, business_id, user_id, filters: _resolve_checks_this_month(db, business_id, filters),
}


def get_widgets_batch_data(
    db: Session,
    business_id: int,
    user_id: int,
    widget_keys: List[str],
    filters: Dict[str, Any],
    calendar_type: str = "gregorian",
) -> Dict[str, Any]:
    """
    Returns a map: { widget_key: data or error } for requested widget_keys.
    calendar_type: "jalali" or "gregorian" - used for date calculations in check widgets
    """
    result: Dict[str, Any] = {}
    filters_with_calendar = dict(filters or {})
    filters_with_calendar["calendar_type"] = calendar_type
    for key in widget_keys:
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
    """
    from datetime import timedelta
    rng = str(filters.get("range") or "week").lower()
    group = str(filters.get("group") or "day").lower()  # day | week | month
    today = datetime.utcnow().date()
    start_date: datetime.date
    end_date: datetime.date

    if rng == "week":
        # last 7 days including today
        end_date = today
        start_date = today - timedelta(days=6)
    elif rng == "month":
        end_date = today
        start_date = today.replace(day=1)
    elif rng == "fiscal":
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

    q = (
        db.query(
            Document.document_date,
            Document.extra_info,
        )
        .filter(
            and_(
                Document.business_id == business_id,
                Document.document_type == INVOICE_SALES,
                Document.is_proforma == False,  # noqa: E712
                Document.document_date >= start_date,
                Document.document_date <= end_date,
            )
        )
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
            gregorian_tomorrow = jdatetime.datetime.to_gregorian(jalali_tomorrow)
            return date(gregorian_tomorrow.year, gregorian_tomorrow.month, gregorian_tomorrow.day)
        else:
            # Convert today to gregorian for DB query
            gregorian_today = jdatetime.datetime.to_gregorian(jalali_now)
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
        greg_start = jdatetime.datetime.to_gregorian(jalali_start)
        greg_end = jdatetime.datetime.to_gregorian(jalali_end)
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


