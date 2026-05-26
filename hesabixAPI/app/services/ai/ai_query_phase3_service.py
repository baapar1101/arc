"""
Queryهای فاز ۳ AI — باشگاه مشتری، فروش سریع، یکپارچه‌سازی، اعتبار، …
"""
from __future__ import annotations

import logging
from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy.orm import Session

from app.core.auth_dependency import AuthContext
from app.services.ai.ai_query_service import _clamp_pagination, _to_int

logger = logging.getLogger(__name__)

PHASE3_ENTITIES = frozenset({
    "customer_club_ledger",
    "price_list",
    "activity_log",
})

PHASE3_ENTITY_PERMISSIONS: Dict[str, List[str]] = {
    "customer_club_ledger": ["customer_club.view"],
    "price_list": ["price_lists.view", "inventory.read"],
    "activity_log": ["activity_logs.view"],
}


def search_activity_logs(
    db: Session,
    business_id: int,
    filters: Dict[str, Any],
) -> Dict[str, Any]:
    from adapters.db.repositories.activity_log_repo import ActivityLogRepository

    q = _clamp_pagination(filters, default_take=50, max_take=200)
    page = max(1, _to_int(filters.get("page"), 1) or 1)
    limit = q["take"]
    offset = q["skip"] if filters.get("skip") is not None else (page - 1) * limit

    category = filters.get("category")
    entity_type = filters.get("entity_type")
    start_date = end_date = None
    if filters.get("from_date"):
        try:
            start_date = datetime.fromisoformat(str(filters["from_date"]).replace("Z", "+00:00"))
        except ValueError:
            pass
    if filters.get("to_date"):
        try:
            end_date = datetime.fromisoformat(str(filters["to_date"]).replace("Z", "+00:00"))
        except ValueError:
            pass

    repo = ActivityLogRepository(db)
    logs = repo.get_by_business(
        business_id=business_id,
        category=category,
        entity_type=entity_type,
        start_date=start_date,
        end_date=end_date,
        limit=limit,
        offset=offset,
    )
    total = repo.count_by_business(
        business_id=business_id,
        category=category,
        entity_type=entity_type,
        start_date=start_date,
        end_date=end_date,
    )
    items = [
        {
            "id": log.id,
            "user_id": log.user_id,
            "category": log.category,
            "action": log.action,
            "entity_type": log.entity_type,
            "entity_id": log.entity_id,
            "description": log.description,
            "created_at": log.created_at.isoformat() if log.created_at else None,
        }
        for log in logs
    ]
    search = (filters.get("search") or "").strip().lower()
    if search:
        items = [
            i
            for i in items
            if search in (i.get("description") or "").lower()
            or search in (i.get("action") or "").lower()
        ]
        total = len(items)

    return {
        "items": items,
        "pagination": {
            "total": total,
            "page": (offset // max(1, limit)) + 1,
            "per_page": limit,
            "has_next": offset + limit < total,
            "has_prev": offset > 0,
        },
    }


def list_customer_club_ledger(
    db: Session,
    business_id: int,
    filters: Dict[str, Any],
) -> Dict[str, Any]:
    from app.services.customer_club_service import list_ledger

    q = _clamp_pagination(filters)
    rows, total = list_ledger(
        db,
        business_id,
        person_id=_to_int(filters.get("person_id")),
        limit=q["take"],
        skip=q["skip"],
    )
    return {
        "items": rows,
        "pagination": {
            "total": total,
            "page": (q["skip"] // max(1, q["take"])) + 1,
            "per_page": q["take"],
        },
    }


def _safe_integration_call(fn, *args, **kwargs) -> Dict[str, Any]:
    try:
        result = fn(*args, **kwargs)
        if isinstance(result, dict):
            return result
        return {"data": result}
    except Exception as exc:
        logger.warning("AI integration call failed: %s", exc)
        return {"error": str(exc), "items": []}


def phase3_entity_search(
    db: Session,
    business_id: int,
    entity: str,
    filters: Dict[str, Any],
    user_context: Optional[AuthContext] = None,
) -> Any:
    if entity == "activity_log":
        return search_activity_logs(db, business_id, filters)
    if entity == "customer_club_ledger":
        return list_customer_club_ledger(db, business_id, filters)
    if entity == "price_list":
        from app.services.price_list_service import list_price_lists

        return list_price_lists(db, business_id, _clamp_pagination(filters))
    raise ValueError(f"entity فاز۳ ناشناخته: {entity}")


def phase3_entity_get(
    db: Session,
    business_id: int,
    entity: str,
    record_id: Optional[int],
    filters: Dict[str, Any],
    user_context: Optional[AuthContext] = None,
) -> Any:
    if entity == "price_list":
        from app.services.price_list_service import get_price_list

        pid = record_id or _to_int(filters.get("price_list_id"))
        if pid is None:
            raise ValueError("price_list_id الزامی است")
        data = get_price_list(db, business_id, pid)
        if not data:
            raise ValueError(f"لیست قیمت {pid} یافت نشد")
        return data
    raise ValueError(f"get برای entity «{entity}» در فاز۳ پشتیبانی نمی‌شود")
