from __future__ import annotations

from typing import Any, Dict, List, Callable
from datetime import datetime

from sqlalchemy.orm import Session
from sqlalchemy import and_, func

from adapters.db.models.document import Document
from adapters.db.models.invoice_item_line import InvoiceItemLine
from adapters.db.models.currency import Currency
from app.services.invoice_service import INVOICE_SALES

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
}


def get_widgets_batch_data(
    db: Session,
    business_id: int,
    user_id: int,
    widget_keys: List[str],
    filters: Dict[str, Any],
) -> Dict[str, Any]:
    """
    Returns a map: { widget_key: data or error } for requested widget_keys.
    """
    result: Dict[str, Any] = {}
    for key in widget_keys:
        resolver = WIDGET_RESOLVERS.get(key)
        if not resolver:
            result[key] = {"error": "UNKNOWN_WIDGET"}
            continue
        try:
            result[key] = resolver(db, business_id, user_id, filters or {})
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


