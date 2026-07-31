# noqa: D100
"""سرویس برچسب‌های CRM: CRUD و تخصیص برچسب به سرنخ/فرصت فروش."""
from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, List, Optional

from sqlalchemy import and_
from sqlalchemy.orm import Session

from adapters.db.models.crm import (
    CrmTag,
    CrmLeadTagLink,
    CrmDealTagLink,
    Lead,
    Deal,
)
from app.core.responses import ApiError

# برچسب‌های پیش‌فرض فارسی که هنگام اولین بار seed می‌شوند
DEFAULT_TAGS: List[Dict[str, Optional[str]]] = [
    {"name": "VIP", "color": "#f59e0b"},
    {"name": "داغ", "color": "#ef4444"},
    {"name": "سرد", "color": "#3b82f6"},
    {"name": "نیازمند پیگیری", "color": "#8b5cf6"},
    {"name": "از دست رفته بالقوه", "color": "#6b7280"},
]


def tag_to_dict(t: CrmTag) -> Dict[str, Any]:
    return {
        "id": t.id,
        "business_id": t.business_id,
        "name": t.name,
        "color": t.color,
        "is_active": bool(t.is_active),
        "sort_order": t.sort_order,
        "created_at": t.created_at.isoformat() if t.created_at else None,
    }


def ensure_default_tags(db: Session, business_id: int) -> None:
    """در صورت نبود هیچ برچسبی، برچسب‌های پیش‌فرض را ایجاد می‌کند."""
    exists = db.query(CrmTag.id).filter(CrmTag.business_id == business_id).first()
    if exists:
        return
    for i, t in enumerate(DEFAULT_TAGS):
        db.add(
            CrmTag(
                business_id=business_id,
                name=t["name"],
                color=t.get("color"),
                is_active=True,
                sort_order=i,
            )
        )
    db.flush()


def list_tags(db: Session, business_id: int, *, seed_defaults: bool = True) -> List[Dict[str, Any]]:
    if seed_defaults:
        ensure_default_tags(db, business_id)
    rows = (
        db.query(CrmTag)
        .filter(CrmTag.business_id == business_id)
        .order_by(CrmTag.sort_order, CrmTag.name)
        .all()
    )
    return [tag_to_dict(t) for t in rows]


def create_tag(
    db: Session,
    business_id: int,
    *,
    name: str,
    color: Optional[str] = None,
    sort_order: int = 0,
) -> CrmTag:
    name = (name or "").strip()
    if not name:
        raise ApiError("CRM_TAG_NAME_REQUIRED", "نام برچسب الزامی است.", http_status=400)
    existing = (
        db.query(CrmTag)
        .filter(and_(CrmTag.business_id == business_id, CrmTag.name == name))
        .first()
    )
    if existing:
        raise ApiError("CRM_TAG_EXISTS", f"برچسب «{name}» از قبل وجود دارد.", http_status=400)
    tag = CrmTag(
        business_id=business_id,
        name=name,
        color=color,
        is_active=True,
        sort_order=sort_order,
    )
    db.add(tag)
    db.flush()
    return tag


def update_tag(
    db: Session,
    business_id: int,
    tag_id: int,
    *,
    name: Optional[str] = None,
    color: Optional[str] = None,
    is_active: Optional[bool] = None,
    sort_order: Optional[int] = None,
) -> CrmTag:
    tag = (
        db.query(CrmTag)
        .filter(and_(CrmTag.id == tag_id, CrmTag.business_id == business_id))
        .first()
    )
    if not tag:
        raise ApiError("NOT_FOUND", "برچسب یافت نشد.", http_status=404)
    if name is not None:
        new_name = name.strip()
        if not new_name:
            raise ApiError("CRM_TAG_NAME_REQUIRED", "نام برچسب الزامی است.", http_status=400)
        dup = (
            db.query(CrmTag)
            .filter(
                CrmTag.business_id == business_id,
                CrmTag.name == new_name,
                CrmTag.id != tag_id,
            )
            .first()
        )
        if dup:
            raise ApiError("CRM_TAG_EXISTS", f"برچسب «{new_name}» از قبل وجود دارد.", http_status=400)
        tag.name = new_name
    if color is not None:
        tag.color = color
    if is_active is not None:
        tag.is_active = is_active
    if sort_order is not None:
        tag.sort_order = sort_order
    db.flush()
    return tag


def delete_tag(db: Session, business_id: int, tag_id: int) -> None:
    tag = (
        db.query(CrmTag)
        .filter(and_(CrmTag.id == tag_id, CrmTag.business_id == business_id))
        .first()
    )
    if not tag:
        raise ApiError("NOT_FOUND", "برچسب یافت نشد.", http_status=404)
    db.delete(tag)
    db.flush()


def _validate_tag_ids(db: Session, business_id: int, tag_ids: List[int]) -> List[int]:
    unique_ids = list({int(t) for t in (tag_ids or [])})
    if not unique_ids:
        return []
    valid = {
        t.id
        for t in db.query(CrmTag.id)
        .filter(CrmTag.business_id == business_id, CrmTag.id.in_(unique_ids))
        .all()
    }
    missing = [t for t in unique_ids if t not in valid]
    if missing:
        raise ApiError("CRM_TAG_NOT_FOUND", f"برچسب(های) نامعتبر: {missing}", http_status=400)
    return unique_ids


def set_lead_tags(db: Session, business_id: int, lead_id: int, tag_ids: List[int]) -> List[Dict[str, Any]]:
    lead = (
        db.query(Lead)
        .filter(and_(Lead.id == lead_id, Lead.business_id == business_id))
        .first()
    )
    if not lead:
        raise ApiError("NOT_FOUND", "سرنخ یافت نشد.", http_status=404)
    ids = _validate_tag_ids(db, business_id, tag_ids)
    db.query(CrmLeadTagLink).filter(CrmLeadTagLink.lead_id == lead_id).delete(synchronize_session=False)
    for tid in ids:
        db.add(CrmLeadTagLink(lead_id=lead_id, tag_id=tid))
    db.flush()
    return get_lead_tags(db, business_id, lead_id)


def set_deal_tags(db: Session, business_id: int, deal_id: int, tag_ids: List[int]) -> List[Dict[str, Any]]:
    deal = (
        db.query(Deal)
        .filter(and_(Deal.id == deal_id, Deal.business_id == business_id))
        .first()
    )
    if not deal:
        raise ApiError("NOT_FOUND", "فرصت فروش یافت نشد.", http_status=404)
    ids = _validate_tag_ids(db, business_id, tag_ids)
    db.query(CrmDealTagLink).filter(CrmDealTagLink.deal_id == deal_id).delete(synchronize_session=False)
    for tid in ids:
        db.add(CrmDealTagLink(deal_id=deal_id, tag_id=tid))
    db.flush()
    return get_deal_tags(db, business_id, deal_id)


def get_lead_tags(db: Session, business_id: int, lead_id: int) -> List[Dict[str, Any]]:
    rows = (
        db.query(CrmTag)
        .join(CrmLeadTagLink, CrmLeadTagLink.tag_id == CrmTag.id)
        .filter(CrmLeadTagLink.lead_id == lead_id, CrmTag.business_id == business_id)
        .order_by(CrmTag.sort_order, CrmTag.name)
        .all()
    )
    return [tag_to_dict(t) for t in rows]


def get_deal_tags(db: Session, business_id: int, deal_id: int) -> List[Dict[str, Any]]:
    rows = (
        db.query(CrmTag)
        .join(CrmDealTagLink, CrmDealTagLink.tag_id == CrmTag.id)
        .filter(CrmDealTagLink.deal_id == deal_id, CrmTag.business_id == business_id)
        .order_by(CrmTag.sort_order, CrmTag.name)
        .all()
    )
    return [tag_to_dict(t) for t in rows]
