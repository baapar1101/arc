"""نمای ذخیره‌شده، جست‌وجوی CRM و فرصت‌های راکد."""
from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any

from sqlalchemy import or_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from adapters.db.models.business_crm_settings import BusinessCrmSettings
from adapters.db.models.crm import CrmSavedView, Deal, Lead
from adapters.db.models.person import Person
from app.core.responses import ApiError

ENTITY_TYPES = ("lead", "deal")
_MAX_VIEWS = 30
_LEAD_FILTERS = {"process_definition_id", "stage_id", "assigned_to_user_id", "search", "kanban"}
_DEAL_FILTERS = {"process_definition_id", "stage_id", "assigned_to_user_id", "person_id", "search", "kanban", "open_only"}
_INT_FILTERS = {"process_definition_id", "stage_id", "assigned_to_user_id", "person_id"}
_BOOL_FILTERS = {"kanban", "open_only"}


def normalize_search_query(raw: str | None) -> str | None:
    text = " ".join(str(raw or "").split())
    if len(text) < 2:
        return None
    return text[:80]


def like_pattern(text: str) -> str:
    escaped = text.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
    return f"%{escaped}%"


def clean_saved_filters(entity_type: str, raw: Any) -> dict[str, Any]:
    if entity_type not in ENTITY_TYPES:
        raise ApiError("CRM_SAVED_VIEW_ENTITY_INVALID", "نوع نما نامعتبر است.", http_status=400)
    if not isinstance(raw, dict):
        raise ApiError("CRM_SAVED_VIEW_FILTERS_INVALID", "فیلتر نما باید شیء باشد.", http_status=400)
    allowed = _LEAD_FILTERS if entity_type == "lead" else _DEAL_FILTERS
    cleaned: dict[str, Any] = {}
    for key, value in raw.items():
        if key not in allowed or value is None:
            continue
        if key in _INT_FILTERS:
            if isinstance(value, bool) or not isinstance(value, int):
                raise ApiError("CRM_SAVED_VIEW_FILTERS_INVALID", "شناسه فیلتر باید عدد باشد.", http_status=400)
            if value <= 0:
                continue
            cleaned[key] = int(value)
        elif key in _BOOL_FILTERS:
            if not isinstance(value, bool):
                raise ApiError("CRM_SAVED_VIEW_FILTERS_INVALID", "فیلتر منطقی نامعتبر است.", http_status=400)
            cleaned[key] = value
        elif key == "search":
            text = normalize_search_query(str(value))
            if text:
                cleaned[key] = text
    return cleaned


def _view_dict(row: CrmSavedView, user_id: int) -> dict[str, Any]:
    return {
        "id": int(row.id),
        "entity_type": row.entity_type,
        "name": row.name,
        "filters": row.filters or {},
        "is_shared": bool(row.is_shared),
        "is_owner": int(row.owner_user_id) == int(user_id),
        "owner_user_id": int(row.owner_user_id),
    }


def list_saved_views(db: Session, business_id: int, user_id: int, entity_type: str) -> list[dict[str, Any]]:
    if entity_type not in ENTITY_TYPES:
        raise ApiError("CRM_SAVED_VIEW_ENTITY_INVALID", "نوع نما نامعتبر است.", http_status=400)
    rows = (
        db.query(CrmSavedView)
        .filter(
            CrmSavedView.business_id == business_id,
            CrmSavedView.entity_type == entity_type,
            or_(CrmSavedView.owner_user_id == user_id, CrmSavedView.is_shared.is_(True)),
        )
        .order_by(CrmSavedView.name.asc())
        .all()
    )
    return [_view_dict(row, user_id) for row in rows]


def create_saved_view(
    db: Session,
    business_id: int,
    user_id: int,
    *,
    entity_type: str,
    name: str,
    filters: Any,
    is_shared: bool,
) -> dict[str, Any]:
    clean_name = " ".join(str(name or "").split())
    if not clean_name or len(clean_name) > 80:
        raise ApiError("CRM_SAVED_VIEW_NAME_INVALID", "نام نما باید بین ۱ و ۸۰ نویسه باشد.", http_status=400)
    owned = (
        db.query(CrmSavedView)
        .filter(
            CrmSavedView.business_id == business_id,
            CrmSavedView.owner_user_id == user_id,
            CrmSavedView.entity_type == entity_type,
        )
        .count()
    )
    if owned >= _MAX_VIEWS:
        raise ApiError("CRM_SAVED_VIEW_LIMIT", "سقف ۳۰ نما برای این فهرست پر شده است.", http_status=400)
    row = CrmSavedView(
        business_id=business_id,
        owner_user_id=user_id,
        entity_type=entity_type,
        name=clean_name,
        filters=clean_saved_filters(entity_type, filters),
        is_shared=bool(is_shared),
    )
    db.add(row)
    try:
        db.flush()
    except IntegrityError as exc:
        db.rollback()
        raise ApiError("CRM_SAVED_VIEW_EXISTS", "نمایی با این نام قبلاً ذخیره شده است.", http_status=409) from exc
    return _view_dict(row, user_id)


def delete_saved_view(db: Session, business_id: int, user_id: int, view_id: int) -> None:
    row = (
        db.query(CrmSavedView)
        .filter(CrmSavedView.id == view_id, CrmSavedView.business_id == business_id)
        .first()
    )
    if row is None:
        raise ApiError("CRM_SAVED_VIEW_NOT_FOUND", "نما پیدا نشد.", http_status=404)
    if int(row.owner_user_id) != int(user_id):
        raise ApiError("CRM_SAVED_VIEW_FORBIDDEN", "فقط سازنده نما می‌تواند آن را حذف کند.", http_status=403)
    db.delete(row)
    db.flush()


def search_crm(db: Session, business_id: int, raw_query: str, limit: int = 12, ctx: Any | None = None) -> dict[str, list[dict[str, Any]]]:
    query = normalize_search_query(raw_query)
    if query is None:
        return {"query": "", "leads": [], "deals": [], "persons": []}
    pattern = like_pattern(query)
    like = lambda column: column.ilike(pattern, escape="\\")  # noqa: E731
    lead_query = db.query(Lead).filter(
        Lead.business_id == business_id,
        or_(like(Lead.name), like(Lead.company_name), like(Lead.mobile), like(Lead.email), like(Lead.code)),
    )
    deal_query = (
        db.query(Deal)
        .options(selectinload(Deal.person))
        .filter(Deal.business_id == business_id, or_(like(Deal.title), like(Deal.code)))
    )
    if ctx is not None:
        from app.services.crm_enterprise_service import restrict_visibility_query

        lead_query = restrict_visibility_query(lead_query, db, business_id, ctx, Lead, "lead")
        deal_query = restrict_visibility_query(deal_query, db, business_id, ctx, Deal, "deal")
    leads = lead_query.order_by(Lead.updated_at.desc()).limit(limit).all()
    deals = deal_query.order_by(Deal.updated_at.desc()).limit(limit).all()
    persons = (
        db.query(Person)
        .filter(
            Person.business_id == business_id,
            or_(like(Person.alias_name), like(Person.first_name), like(Person.last_name), like(Person.mobile), like(Person.email)),
        )
        .order_by(Person.updated_at.desc())
        .limit(limit)
        .all()
    )
    return {
        "query": query,
        "leads": [
            {
                "id": int(row.id),
                "code": row.code,
                "name": row.name,
                "subtitle": row.company_name or row.mobile or row.email,
            }
            for row in leads
        ],
        "deals": [
            {
                "id": int(row.id),
                "code": row.code,
                "title": row.title,
                "subtitle": row.person.alias_name if row.person is not None else None,
            }
            for row in deals
        ],
        "persons": [
            {
                "id": int(row.id),
                "code": row.code,
                "name": row.alias_name,
                "subtitle": row.mobile or row.email,
            }
            for row in persons
        ],
    }


def list_stale_deals(db: Session, business_id: int, limit: int = 20, ctx: Any | None = None) -> dict[str, Any]:
    settings = db.query(BusinessCrmSettings).filter(BusinessCrmSettings.business_id == business_id).first()
    days = int(settings.stale_deal_days) if settings is not None else 14
    if days <= 0:
        return {"stale_deal_days": days, "items": []}
    cutoff = datetime.utcnow() - timedelta(days=days)
    deal_query = (
        db.query(Deal)
        .options(selectinload(Deal.person), selectinload(Deal.stage))
        .filter(
            Deal.business_id == business_id,
            Deal.closed_at.is_(None),
            Deal.stage_entered_at.isnot(None),
            Deal.stage_entered_at <= cutoff,
        )
    )
    if ctx is not None:
        from app.services.crm_enterprise_service import restrict_visibility_query

        deal_query = restrict_visibility_query(deal_query, db, business_id, ctx, Deal, "deal")
    rows = deal_query.order_by(Deal.stage_entered_at.asc()).limit(limit).all()
    return {
        "stale_deal_days": days,
        "items": [
            {
                "id": int(row.id),
                "code": row.code,
                "title": row.title,
                "person_name": row.person.alias_name if row.person is not None else None,
                "stage_name": row.stage.name if row.stage is not None else None,
                "stage_entered_at": row.stage_entered_at.isoformat() if row.stage_entered_at else None,
                "amount": float(row.amount or 0),
            }
            for row in rows
        ],
    }
