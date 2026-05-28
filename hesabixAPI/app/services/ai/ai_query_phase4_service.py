"""
Queryهای فاز ۴ AI — دسته‌بندی، گروه اشخاص، ارز، ویژگی کالا، اعلان، …
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

from app.core.auth_dependency import AuthContext
from app.services.ai.ai_query_service import _clamp_pagination, _to_int

PHASE4_ENTITIES = frozenset({
    "category",
    "person_group",
    "currency",
    "product_attribute",
})

PHASE4_ENTITY_PERMISSIONS: Dict[str, List[str]] = {
    "category": ["categories.view"],
    "person_group": ["people.view"],
    "currency": ["invoices.view"],
    "product_attribute": ["product_attributes.view"],
}


def _search_categories(db: Session, business_id: int, filters: Dict[str, Any]) -> Dict[str, Any]:
    from adapters.db.repositories.category_repository import CategoryRepository

    q = (filters.get("search") or filters.get("query") or "").strip()
    if not q:
        return {"items": [], "pagination": {"total": 0, "skip": 0, "take": 0}}
    flt = _clamp_pagination(filters, default_take=50, max_take=100)
    limit = flt["take"]
    repo = CategoryRepository(db)
    items = repo.search_with_paths(business_id=business_id, query=q, limit=limit)
    mapped = [
        {
            "id": it.get("id"),
            "parent_id": it.get("parent_id"),
            "label": it.get("title") or "",
            "path": it.get("path") or [],
        }
        for it in items
    ]
    return {
        "items": mapped,
        "pagination": {"total": len(mapped), "skip": flt["skip"], "take": limit},
    }


def _get_category(db: Session, business_id: int, record_id: int) -> Dict[str, Any]:
    from adapters.db.models.category import BusinessCategory

    cat = (
        db.query(BusinessCategory)
        .filter(BusinessCategory.id == record_id, BusinessCategory.business_id == business_id)
        .first()
    )
    if not cat:
        raise ValueError(f"دسته‌بندی {record_id} یافت نشد")
    tr = cat.title_translations or {}
    return {
        "id": cat.id,
        "parent_id": cat.parent_id,
        "label": tr.get("fa") or tr.get("en") or "",
        "description": cat.description,
    }


def _search_person_groups(db: Session, business_id: int, filters: Dict[str, Any]) -> Dict[str, Any]:
    from app.services.person_group_service import list_person_groups

    flt = _clamp_pagination(filters, default_take=50, max_take=100)
    return list_person_groups(
        db,
        business_id,
        skip=flt["skip"],
        take=flt["take"],
        active_only=bool(filters.get("active_only", False)),
        root_only=bool(filters.get("root_only", True)),
    )


def _get_person_group(db: Session, business_id: int, record_id: int) -> Dict[str, Any]:
    from adapters.db.models.person_group import PersonGroup

    row = (
        db.query(PersonGroup)
        .filter(PersonGroup.id == record_id, PersonGroup.business_id == business_id)
        .first()
    )
    if not row:
        raise ValueError(f"گروه اشخاص {record_id} یافت نشد")
    from app.services.person_group_service import serialize_person_group

    return serialize_person_group(row)


def _list_currencies(db: Session, business_id: int, filters: Dict[str, Any]) -> Dict[str, Any]:
    from adapters.db.models.currency import Currency

    rows = db.query(Currency).order_by(Currency.id.asc()).all()
    mapped = [
        {
            "id": c.id,
            "code": c.code,
            "name": getattr(c, "name", None) or getattr(c, "title", None),
            "symbol": getattr(c, "symbol", None),
        }
        for c in rows
    ]
    search = (filters.get("search") or "").strip().lower()
    if search:
        mapped = [
            x
            for x in mapped
            if search in (x.get("code") or "").lower()
            or search in (x.get("name") or "").lower()
        ]
    return {"items": mapped, "pagination": {"total": len(mapped), "skip": 0, "take": len(mapped)}}


def _search_product_attributes(db: Session, business_id: int, filters: Dict[str, Any]) -> Dict[str, Any]:
    from adapters.db.repositories.product_attribute_repository import ProductAttributeRepository

    flt = _clamp_pagination(filters, default_take=50, max_take=100)
    repo = ProductAttributeRepository(db)
    search = (filters.get("search") or "").strip() or None
    return repo.search(
        business_id=business_id,
        search=search,
        skip=flt["skip"],
        take=flt["take"],
    )


def phase4_entity_search(
    db: Session,
    business_id: int,
    entity: str,
    filters: Dict[str, Any],
    user_context: Optional[AuthContext] = None,
) -> Any:
    if entity == "category":
        return _search_categories(db, business_id, filters)
    if entity == "person_group":
        return _search_person_groups(db, business_id, filters)
    if entity == "currency":
        return _list_currencies(db, business_id, filters)
    if entity == "product_attribute":
        return _search_product_attributes(db, business_id, filters)
    raise ValueError(f"entity فاز ۴ نامعتبر: {entity}")


def phase4_entity_get(
    db: Session,
    business_id: int,
    entity: str,
    record_id: Optional[int],
    filters: Dict[str, Any],
    user_context: Optional[AuthContext] = None,
) -> Any:
    rid = record_id or _to_int(filters.get("id"))
    if rid is None:
        raise ValueError("record_id یا id الزامی است")
    if entity == "category":
        return _get_category(db, business_id, rid)
    if entity == "person_group":
        return _get_person_group(db, business_id, rid)
    raise ValueError(f"get برای entity {entity} پشتیبانی نمی‌شود")
