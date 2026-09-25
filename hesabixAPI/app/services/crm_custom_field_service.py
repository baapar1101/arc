# noqa: D100
"""سرویس فیلدهای سفارشی CRM: تعریف فیلدها و اعتبارسنجی/ادغام مقادیر در extra_info._custom."""
from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, List, Optional

from sqlalchemy import and_
from sqlalchemy.orm import Session

from adapters.db.models.crm import CrmCustomFieldDefinition
from app.core.responses import ApiError

VALID_ENTITY_TYPES = {"lead", "deal", "activity"}
VALID_FIELD_TYPES = {"text", "number", "date", "select", "boolean"}
CUSTOM_KEY = "_custom"


def definition_to_dict(d: CrmCustomFieldDefinition) -> Dict[str, Any]:
    return {
        "id": d.id,
        "business_id": d.business_id,
        "entity_type": d.entity_type,
        "field_key": d.field_key,
        "label": d.label,
        "field_type": d.field_type,
        "options": d.options,
        "is_required": bool(d.is_required),
        "sort_order": d.sort_order,
        "is_active": bool(d.is_active),
        "created_at": d.created_at.isoformat() if d.created_at else None,
    }


def list_definitions(
    db: Session,
    business_id: int,
    *,
    entity_type: Optional[str] = None,
    active_only: bool = False,
) -> List[Dict[str, Any]]:
    q = db.query(CrmCustomFieldDefinition).filter(CrmCustomFieldDefinition.business_id == business_id)
    if entity_type:
        q = q.filter(CrmCustomFieldDefinition.entity_type == entity_type)
    if active_only:
        q = q.filter(CrmCustomFieldDefinition.is_active.is_(True))
    rows = q.order_by(
        CrmCustomFieldDefinition.entity_type,
        CrmCustomFieldDefinition.sort_order,
        CrmCustomFieldDefinition.field_key,
    ).all()
    return [definition_to_dict(d) for d in rows]


def create_definition(
    db: Session,
    business_id: int,
    *,
    entity_type: str,
    field_key: str,
    label: str,
    field_type: str,
    options: Optional[list] = None,
    is_required: bool = False,
    sort_order: int = 0,
) -> CrmCustomFieldDefinition:
    if entity_type not in VALID_ENTITY_TYPES:
        raise ApiError("CRM_CF_INVALID_ENTITY", "نوع موجودیت نامعتبر است.", http_status=400)
    if field_type not in VALID_FIELD_TYPES:
        raise ApiError("CRM_CF_INVALID_TYPE", "نوع فیلد نامعتبر است.", http_status=400)
    field_key = (field_key or "").strip()
    if not field_key:
        raise ApiError("CRM_CF_KEY_REQUIRED", "کلید فیلد الزامی است.", http_status=400)
    if field_type == "select" and not options:
        raise ApiError("CRM_CF_OPTIONS_REQUIRED", "برای نوع select گزینه‌ها الزامی است.", http_status=400)
    dup = (
        db.query(CrmCustomFieldDefinition)
        .filter(
            and_(
                CrmCustomFieldDefinition.business_id == business_id,
                CrmCustomFieldDefinition.entity_type == entity_type,
                CrmCustomFieldDefinition.field_key == field_key,
            )
        )
        .first()
    )
    if dup:
        raise ApiError("CRM_CF_EXISTS", f"فیلد سفارشی «{field_key}» از قبل وجود دارد.", http_status=400)
    d = CrmCustomFieldDefinition(
        business_id=business_id,
        entity_type=entity_type,
        field_key=field_key,
        label=label,
        field_type=field_type,
        options={"choices": options} if options is not None else None,
        is_required=is_required,
        sort_order=sort_order,
        is_active=True,
    )
    db.add(d)
    db.flush()
    return d


def update_definition(
    db: Session,
    business_id: int,
    field_id: int,
    *,
    label: Optional[str] = None,
    options: Optional[list] = None,
    is_required: Optional[bool] = None,
    sort_order: Optional[int] = None,
    is_active: Optional[bool] = None,
) -> CrmCustomFieldDefinition:
    d = (
        db.query(CrmCustomFieldDefinition)
        .filter(and_(CrmCustomFieldDefinition.id == field_id, CrmCustomFieldDefinition.business_id == business_id))
        .first()
    )
    if not d:
        raise ApiError("NOT_FOUND", "فیلد سفارشی یافت نشد.", http_status=404)
    if label is not None:
        d.label = label
    if options is not None:
        d.options = {"choices": options}
    if is_required is not None:
        d.is_required = is_required
    if sort_order is not None:
        d.sort_order = sort_order
    if is_active is not None:
        d.is_active = is_active
    db.flush()
    return d


def delete_definition(db: Session, business_id: int, field_id: int) -> None:
    d = (
        db.query(CrmCustomFieldDefinition)
        .filter(and_(CrmCustomFieldDefinition.id == field_id, CrmCustomFieldDefinition.business_id == business_id))
        .first()
    )
    if not d:
        raise ApiError("NOT_FOUND", "فیلد سفارشی یافت نشد.", http_status=404)
    db.delete(d)
    db.flush()


def _coerce_value(field_type: str, value: Any, options: Optional[dict]) -> Any:
    """تبدیل و اعتبارسنجی یک مقدار طبق نوع فیلد."""
    if value is None:
        return None
    if field_type == "number":
        try:
            return float(value)
        except (TypeError, ValueError):
            raise ApiError("CRM_CF_INVALID_VALUE", "مقدار عددی نامعتبر است.", http_status=400)
    if field_type == "boolean":
        return bool(value)
    if field_type == "date":
        s = str(value).strip()
        # نگه‌داری به‌صورت رشته ISO؛ فقط اعتبارسنجی ساده
        try:
            datetime.fromisoformat(s.replace("Z", "+00:00"))
        except ValueError:
            raise ApiError("CRM_CF_INVALID_VALUE", "تاریخ نامعتبر است.", http_status=400)
        return s
    if field_type == "select":
        choices = (options or {}).get("choices") or []
        if choices and value not in choices:
            raise ApiError("CRM_CF_INVALID_CHOICE", f"گزینه «{value}» مجاز نیست.", http_status=400)
        return value
    return str(value)


def validate_and_merge_custom_values(
    db: Session,
    business_id: int,
    entity_type: str,
    existing_extra_info: Optional[dict],
    custom_values: Optional[Dict[str, Any]],
) -> dict:
    """اعتبارسنجی مقادیر سفارشی و ادغام در extra_info زیر کلید `_custom`.

    اگر custom_values None باشد فقط بررسی فیلدهای الزامی روی مقادیر موجود انجام می‌شود.
    """
    extra = dict(existing_extra_info or {})
    defs = (
        db.query(CrmCustomFieldDefinition)
        .filter(
            CrmCustomFieldDefinition.business_id == business_id,
            CrmCustomFieldDefinition.entity_type == entity_type,
            CrmCustomFieldDefinition.is_active.is_(True),
        )
        .all()
    )
    if not defs:
        return extra
    def_by_key = {d.field_key: d for d in defs}
    current = dict(extra.get(CUSTOM_KEY) or {})

    if custom_values:
        for key, value in custom_values.items():
            d = def_by_key.get(key)
            if not d:
                # فیلدهای ناشناخته نادیده گرفته می‌شوند تا کلاینت‌های قدیمی خطا نگیرند
                continue
            current[key] = _coerce_value(d.field_type, value, d.options)

    # بررسی فیلدهای الزامی
    for d in defs:
        if d.is_required:
            val = current.get(d.field_key)
            if val is None or (isinstance(val, str) and not val.strip()):
                raise ApiError(
                    "CRM_CF_REQUIRED",
                    f"فیلد سفارشی «{d.label}» الزامی است.",
                    http_status=400,
                )

    extra[CUSTOM_KEY] = current
    return extra
