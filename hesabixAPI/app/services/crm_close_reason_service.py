# noqa: D100
"""سرویس دلایل بستن معامله (برد/باخت): CRUD و ایجاد دلایل پیش‌فرض فارسی."""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from sqlalchemy import and_
from sqlalchemy.orm import Session

from adapters.db.models.crm import CrmCloseReason
from app.core.responses import ApiError

VALID_REASON_TYPES = {"won", "lost"}

DEFAULT_WON_REASONS: List[Dict[str, str]] = [
    {"code": "best_price", "name": "بهترین قیمت"},
    {"code": "product_quality", "name": "کیفیت محصول"},
    {"code": "relationship", "name": "ارتباط و اعتماد"},
    {"code": "fast_delivery", "name": "تحویل سریع"},
    {"code": "after_sales", "name": "خدمات پس از فروش"},
]

DEFAULT_LOST_REASONS: List[Dict[str, str]] = [
    {"code": "price_too_high", "name": "قیمت بالا"},
    {"code": "chose_competitor", "name": "انتخاب رقیب"},
    {"code": "no_budget", "name": "نبود بودجه"},
    {"code": "no_response", "name": "عدم پاسخ‌گویی مشتری"},
    {"code": "feature_gap", "name": "نبود امکانات موردنیاز"},
    {"code": "bad_timing", "name": "زمان نامناسب"},
]


def reason_to_dict(r: CrmCloseReason) -> Dict[str, Any]:
    return {
        "id": r.id,
        "business_id": r.business_id,
        "reason_type": r.reason_type,
        "code": r.code,
        "name": r.name,
        "is_active": bool(r.is_active),
        "sort_order": r.sort_order,
        "created_at": r.created_at.isoformat() if r.created_at else None,
    }


def ensure_default_reasons(db: Session, business_id: int) -> None:
    """در صورت نبود دلیل، دلایل پیش‌فرض برد و باخت را ایجاد می‌کند."""
    exists = db.query(CrmCloseReason.id).filter(CrmCloseReason.business_id == business_id).first()
    if exists:
        return
    for i, r in enumerate(DEFAULT_WON_REASONS):
        db.add(
            CrmCloseReason(
                business_id=business_id,
                reason_type="won",
                code=r["code"],
                name=r["name"],
                is_active=True,
                sort_order=i,
            )
        )
    for i, r in enumerate(DEFAULT_LOST_REASONS):
        db.add(
            CrmCloseReason(
                business_id=business_id,
                reason_type="lost",
                code=r["code"],
                name=r["name"],
                is_active=True,
                sort_order=i,
            )
        )
    db.flush()


def list_reasons(
    db: Session,
    business_id: int,
    *,
    reason_type: Optional[str] = None,
    active_only: bool = False,
    seed_defaults: bool = True,
) -> List[Dict[str, Any]]:
    if seed_defaults:
        ensure_default_reasons(db, business_id)
    q = db.query(CrmCloseReason).filter(CrmCloseReason.business_id == business_id)
    if reason_type:
        q = q.filter(CrmCloseReason.reason_type == reason_type)
    if active_only:
        q = q.filter(CrmCloseReason.is_active.is_(True))
    rows = q.order_by(CrmCloseReason.reason_type, CrmCloseReason.sort_order, CrmCloseReason.name).all()
    return [reason_to_dict(r) for r in rows]


def create_reason(
    db: Session,
    business_id: int,
    *,
    reason_type: str,
    code: str,
    name: str,
    sort_order: int = 0,
) -> CrmCloseReason:
    if reason_type not in VALID_REASON_TYPES:
        raise ApiError("CRM_CLOSE_REASON_INVALID_TYPE", "نوع دلیل باید won یا lost باشد.", http_status=400)
    code = (code or "").strip()
    name = (name or "").strip()
    if not code or not name:
        raise ApiError("CRM_CLOSE_REASON_INVALID", "کد و نام دلیل الزامی است.", http_status=400)
    dup = (
        db.query(CrmCloseReason)
        .filter(
            and_(
                CrmCloseReason.business_id == business_id,
                CrmCloseReason.reason_type == reason_type,
                CrmCloseReason.code == code,
            )
        )
        .first()
    )
    if dup:
        raise ApiError("CRM_CLOSE_REASON_EXISTS", f"دلیل با کد «{code}» از قبل وجود دارد.", http_status=400)
    r = CrmCloseReason(
        business_id=business_id,
        reason_type=reason_type,
        code=code,
        name=name,
        is_active=True,
        sort_order=sort_order,
    )
    db.add(r)
    db.flush()
    return r


def update_reason(
    db: Session,
    business_id: int,
    reason_id: int,
    *,
    name: Optional[str] = None,
    is_active: Optional[bool] = None,
    sort_order: Optional[int] = None,
) -> CrmCloseReason:
    r = (
        db.query(CrmCloseReason)
        .filter(and_(CrmCloseReason.id == reason_id, CrmCloseReason.business_id == business_id))
        .first()
    )
    if not r:
        raise ApiError("NOT_FOUND", "دلیل یافت نشد.", http_status=404)
    if name is not None:
        r.name = name.strip()
    if is_active is not None:
        r.is_active = is_active
    if sort_order is not None:
        r.sort_order = sort_order
    db.flush()
    return r


def delete_reason(db: Session, business_id: int, reason_id: int) -> None:
    r = (
        db.query(CrmCloseReason)
        .filter(and_(CrmCloseReason.id == reason_id, CrmCloseReason.business_id == business_id))
        .first()
    )
    if not r:
        raise ApiError("NOT_FOUND", "دلیل یافت نشد.", http_status=404)
    db.delete(r)
    db.flush()


def is_valid_reason_code(db: Session, business_id: int, reason_type: str, code: str) -> bool:
    """بررسی معتبر بودن کد دلیل برای نوع مشخص (برای اعتبارسنجی هنگام بستن معامله)."""
    if not code:
        return False
    ensure_default_reasons(db, business_id)
    r = (
        db.query(CrmCloseReason.id)
        .filter(
            CrmCloseReason.business_id == business_id,
            CrmCloseReason.reason_type == reason_type,
            CrmCloseReason.code == code,
            CrmCloseReason.is_active.is_(True),
        )
        .first()
    )
    return r is not None
