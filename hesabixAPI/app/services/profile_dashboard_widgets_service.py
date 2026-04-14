from __future__ import annotations

from typing import Any, Dict, List, Callable
from datetime import datetime

from sqlalchemy.orm import Session

from app.services.business_service import get_user_businesses
from app.services.announcement_service import user_list as list_announcements
from adapters.db.repositories.support.ticket_repository import TicketRepository
from adapters.api.v1.schemas import QueryInfo

# ----------------------------
# Responsive columns per breakpoint
# ----------------------------
COLUMNS_BY_BREAKPOINT: Dict[str, int] = {
    "xs": 1,
    "sm": 4,
    "md": 8,
    "lg": 12,
    "xl": 12,
}


# ----------------------------
# Profile Widget Definitions
# ----------------------------
PROFILE_WIDGET_DEFINITIONS: List[Dict[str, Any]] = [
    {
        "key": "profile_recent_businesses",
        "title": "کسب‌وکارهای شما",
        "icon": "business",
        "version": 1,
        "permissions_required": [],
        "defaults": {
            "xs": {"colSpan": 1, "rowSpan": 2},
            "sm": {"colSpan": 2, "rowSpan": 2},
            "md": {"colSpan": 4, "rowSpan": 2},
            "lg": {"colSpan": 4, "rowSpan": 2},
            "xl": {"colSpan": 4, "rowSpan": 2},
        },
        "cache_ttl": 60,
    },
    {
        "key": "profile_announcements",
        "title": "اعلان‌ها",
        "icon": "notifications",
        "version": 1,
        "permissions_required": [],
        "defaults": {
            "xs": {"colSpan": 1, "rowSpan": 2},
            "sm": {"colSpan": 2, "rowSpan": 2},
            "md": {"colSpan": 4, "rowSpan": 2},
            "lg": {"colSpan": 4, "rowSpan": 2},
            "xl": {"colSpan": 4, "rowSpan": 2},
        },
        "cache_ttl": 30,
    },
    {
        "key": "profile_support_tickets",
        "title": "تیکت‌های پشتیبانی",
        "icon": "support_agent",
        "version": 1,
        "permissions_required": [],
        "defaults": {
            "xs": {"colSpan": 1, "rowSpan": 2},
            "sm": {"colSpan": 2, "rowSpan": 2},
            "md": {"colSpan": 4, "rowSpan": 2},
            "lg": {"colSpan": 4, "rowSpan": 2},
            "xl": {"colSpan": 4, "rowSpan": 2},
        },
        "cache_ttl": 30,
    },
]


def get_profile_widget_definitions(db: Session, user_id: int) -> Dict[str, Any]:
    """
    Returns available widgets for profile dashboard along with responsive columns map.
    """
    return {
        "columns": COLUMNS_BY_BREAKPOINT,
        "items": PROFILE_WIDGET_DEFINITIONS,
    }


# ----------------------------
# Layout Storage (in-memory for now)
# ----------------------------
_IN_MEMORY_LAYOUTS: Dict[str, Dict[str, Any]] = {}


def _layout_key(user_id: int, breakpoint: str) -> str:
    return f"profile:{user_id}:{breakpoint}"


def get_profile_dashboard_layout_profile(
    db: Session,
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
    key = _layout_key(user_id, bp)
    found = _IN_MEMORY_LAYOUTS.get(key)
    if found:
        return found

    # Build default layout from definitions
    columns = COLUMNS_BY_BREAKPOINT[bp]
    items: List[Dict[str, Any]] = []
    order = 1
    for d in PROFILE_WIDGET_DEFINITIONS:
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
        "version": 1,
        "updated_at": datetime.utcnow().isoformat() + "Z",
    }
    _IN_MEMORY_LAYOUTS[key] = profile
    return profile


def save_profile_dashboard_layout_profile(
    db: Session,
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
        "version": 1,
        "updated_at": datetime.utcnow().isoformat() + "Z",
    }
    _IN_MEMORY_LAYOUTS[_layout_key(user_id, bp)] = profile
    return profile


# ----------------------------
# Data resolvers (Batch)
# ----------------------------
WidgetResolver = Callable[[Session, int, Dict[str, Any]], Any]


def _resolve_profile_recent_businesses(
    db: Session, user_id: int, filters: Dict[str, Any]
) -> Dict[str, Any]:
    """
    Returns user's businesses (owner + member).
    """
    limit_raw = filters.get("limit", 10)
    try:
        limit = max(1, min(50, int(limit_raw)))
    except Exception:
        limit = 10

    query_dict = {
        "take": limit,
        "skip": 0,
        "sort_by": "created_at",
        "sort_desc": True,
        "search": None,
    }
    # برای داشبورد پروفایل، کسب‌وکارهای حذف‌شده را نشان نمی‌دهیم
    result = get_user_businesses(db, user_id, query_dict, include_deleted_for_owner=False)
    items = result.get("items", [])
    
    # فیلتر کردن کسب و کارهای حذف شده (در حال حذف یا حذف شده)
    # کسب و کارهایی که deleted_at دارند یا در حال حذف هستند را نشان نمی‌دهیم
    filtered_items = []
    for item in items:
        deleted_at = item.get("deleted_at")
        is_deleted = item.get("is_deleted", False)
        is_deletion_pending = item.get("is_deletion_pending", False)
        
        # بررسی اینکه آیا کسب و کار حذف شده یا در حال حذف است
        # deleted_at می‌تواند None، string خالی یا string با تاریخ باشد
        has_deleted_at = deleted_at is not None and deleted_at != ""
        
        # اگر حذف نشده و در حال حذف نیست، اضافه کن
        if not has_deleted_at and not is_deleted and not is_deletion_pending:
            filtered_items.append(item)
    
    items = filtered_items
    
    # Format items for widget
    formatted_items = []
    for item in items:
        formatted_items.append({
            "id": item.get("id"),
            "name": item.get("name"),
            "role": item.get("role", "عضو"),
            "is_owner": item.get("is_owner", False),
        })
    
    return {"items": formatted_items}


def _resolve_profile_announcements(
    db: Session, user_id: int, filters: Dict[str, Any]
) -> Dict[str, Any]:
    """
    Returns user's announcements.
    """
    limit_raw = filters.get("limit", 5)
    try:
        limit = max(1, min(50, int(limit_raw)))
    except Exception:
        limit = 5

    only_unread = filters.get("only_unread", False)
    
    # Call the announcements service
    try:
        result = list_announcements(
            db=db,
            user_id=user_id,
            page=1,
            limit=limit,
            only_unread=only_unread,
            level=None,
            locale=None,
        )
        items = result.get("items", [])
        return {"items": items}
    except Exception:
        return {"items": []}


def _resolve_profile_support_tickets(
    db: Session, user_id: int, filters: Dict[str, Any]
) -> Dict[str, Any]:
    """
    Returns user's support tickets.
    """
    limit_raw = filters.get("limit", 5)
    try:
        limit = max(1, min(50, int(limit_raw)))
    except Exception:
        limit = 5

    # Call the support tickets repository
    try:
        ticket_repo = TicketRepository(db)
        query_info = QueryInfo(
            take=limit,
            skip=0,
            sort_by="updated_at",
            sort_desc=True,
            search=None,
            search_fields=None,
        )
        tickets, total = ticket_repo.get_user_tickets(user_id, query_info)
        
        # Format items for widget
        formatted_items = []
        for ticket in tickets:
            formatted_items.append({
                "id": ticket.id,
                "subject": ticket.title,
                "status": ticket.status.name if ticket.status else "",
                "updated_at": ticket.updated_at.isoformat() if ticket.updated_at else "",
            })
        
        return {"items": formatted_items}
    except Exception:
        return {"items": []}


PROFILE_WIDGET_RESOLVERS: Dict[str, WidgetResolver] = {
    "profile_recent_businesses": _resolve_profile_recent_businesses,
    "profile_announcements": _resolve_profile_announcements,
    "profile_support_tickets": _resolve_profile_support_tickets,
}


def get_profile_widgets_batch_data(
    db: Session,
    user_id: int,
    widget_keys: List[str],
    filters: Dict[str, Any],
) -> Dict[str, Any]:
    """
    Returns a map: { widget_key: data or error } for requested widget_keys.
    """
    result: Dict[str, Any] = {}
    for key in widget_keys:
        resolver = PROFILE_WIDGET_RESOLVERS.get(key)
        if not resolver:
            result[key] = {"error": "UNKNOWN_WIDGET"}
            continue
        try:
            result[key] = resolver(db, user_id, filters or {})
        except Exception as ex:
            # Avoid breaking the whole dashboard; return error per widget
            result[key] = {"error": str(ex)}
    return result

