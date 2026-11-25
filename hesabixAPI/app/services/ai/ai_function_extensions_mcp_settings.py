"""MCP tools for business identity and document-numbering settings."""
from __future__ import annotations

from typing import Any, Dict

UPDATE_BUSINESS_INFO_SCHEMA: Dict[str, Any] = {}
UPDATE_DOCUMENT_NUMBERING_SCHEMA: Dict[str, Any] = {}

_DOC_TYPES = [
    "invoice_sales",
    "invoice_sales_return",
    "invoice_purchase",
    "invoice_purchase_return",
    "invoice_direct_consumption",
    "invoice_production",
    "invoice_waste",
    "receipt",
    "payment",
    "transfer",
    "expense",
    "income",
    "crm_lead",
    "crm_deal",
    "crm_activity",
    "warehouse_document",
    "manual",
    "opening_balance",
]


def _schema(properties: Dict[str, Any], required: list[str] | None = None) -> Dict[str, Any]:
    return {
        "type": "object",
        "properties": properties,
        "required": list(required or []),
        "additionalProperties": False,
    }


def _raise_service(exc: BaseException) -> None:
    from app.core.responses import ApiError

    if isinstance(exc, ApiError):
        raise ValueError(exc.message) from exc
    raise exc


UPDATE_BUSINESS_INFO_SCHEMA = _schema(
    {
        "name": {"type": "string", "minLength": 1, "maxLength": 255},
        "business_type": {"type": "string", "enum": ["شرکت", "مغازه", "فروشگاه", "اتحادیه", "باشگاه", "موسسه", "شخصی"]},
        "business_field": {"type": "string", "enum": ["تولیدی", "بازرگانی", "خدماتی", "سایر"]},
        "address": {"type": ["string", "null"], "maxLength": 1000},
        "phone": {"type": ["string", "null"], "maxLength": 20},
        "mobile": {"type": ["string", "null"], "maxLength": 20},
        "national_id": {"type": ["string", "null"], "maxLength": 20},
        "registration_number": {"type": ["string", "null"], "maxLength": 50},
        "economic_id": {"type": ["string", "null"], "maxLength": 50},
        "country": {"type": ["string", "null"], "maxLength": 100},
        "default_phone_region": {"type": "string", "minLength": 2, "maxLength": 2},
        "province": {"type": ["string", "null"], "maxLength": 100},
        "city": {"type": ["string", "null"], "maxLength": 100},
        "postal_code": {"type": ["string", "null"], "maxLength": 20},
    }
)
UPDATE_DOCUMENT_NUMBERING_SCHEMA = _schema(
    {
        "document_type": {"type": "string", "enum": _DOC_TYPES},
        "prefix": {"type": ["string", "null"], "maxLength": 20},
        "include_date": {"type": "boolean"},
        "calendar_type": {"type": "string", "enum": ["gregorian", "jalali"]},
        "date_format": {"type": ["string", "null"], "maxLength": 20},
        "separator": {"type": "string", "maxLength": 5},
        "start_number": {"type": "integer", "minimum": 1},
        "number_padding": {"type": "integer", "minimum": 1, "maximum": 10},
        "reset_period": {
            "anyOf": [
                {"type": "string", "enum": ["daily", "monthly", "yearly", "never"]},
                {"type": "null"},
            ]
        },
        "custom_format": {"type": ["string", "null"], "maxLength": 100},
        "is_active": {"type": "boolean"},
    },
    ["document_type"],
)


def update_business_info_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from adapters.api.v1.schemas import BusinessUpdateRequest
    from app.services.business_service import update_business

    bid = int(context["business_id"])
    uid = int(context["user_context"].get_user_id())
    try:
        payload = BusinessUpdateRequest(**dict(args))
        result = update_business(context["db"], bid, payload, uid)
    except Exception as exc:
        _raise_service(exc)
    if result is None:
        raise ValueError("ویرایش مشخصات کسب‌وکار فقط برای مالک کسب‌وکار متصل مجاز است.")
    return result


def update_document_numbering_settings_handler(args: Dict[str, Any], context: Dict[str, Any]) -> Any:
    from datetime import datetime

    from adapters.api.v1.schemas import DocumentNumberingSettingRequest, DocumentNumberingSettingResponse
    from adapters.db.models.document_numbering import BusinessDocumentNumberingSetting
    from sqlalchemy import and_

    db = context["db"]
    bid = int(context["business_id"])
    try:
        data = DocumentNumberingSettingRequest(**dict(args))
    except Exception as exc:
        raise ValueError(str(exc)) from exc
    existing = (
        db.query(BusinessDocumentNumberingSetting)
        .filter(
            and_(
                BusinessDocumentNumberingSetting.business_id == bid,
                BusinessDocumentNumberingSetting.document_type == data.document_type,
            )
        )
        .first()
    )
    if existing:
        for key, value in data.dict(exclude_unset=True).items():
            setattr(existing, key, value)
        existing.updated_at = datetime.utcnow()
        db.commit()
        db.refresh(existing)
        return DocumentNumberingSettingResponse.from_orm(existing).dict()
    row = BusinessDocumentNumberingSetting(business_id=bid, **data.dict())
    db.add(row)
    db.commit()
    db.refresh(row)
    return DocumentNumberingSettingResponse.from_orm(row).dict()


def register_mcp_settings_functions(registry) -> None:
    from app.services.ai.function_registry import AIFunction, AIRole

    roles = {AIRole.USER, AIRole.BUSINESS_OWNER, AIRole.OPERATOR, AIRole.ADMIN}
    registry.register(AIFunction(
        name="update_business_info",
        description="ویرایش نام، نوع، زمینه، آدرس و شناسه‌های کسب‌وکار متصل. فقط مالک کسب‌وکار. نیاز به تأیید.",
        parameters_schema=UPDATE_BUSINESS_INFO_SCHEMA,
        handler=update_business_info_handler,
        allowed_roles=roles,
        required_permissions=["settings.business"],
        category="business",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
    registry.register(AIFunction(
        name="update_document_numbering_settings",
        description="ایجاد یا به‌روزرسانی پیشوند و قالب شماره یک نوع سند. از get_document_numbering_settings بخوان. نیاز به تأیید.",
        parameters_schema=UPDATE_DOCUMENT_NUMBERING_SCHEMA,
        handler=update_document_numbering_settings_handler,
        allowed_roles=roles,
        required_permissions=["settings.join"],
        category="accounting",
        requires_approval=True,
        risk_level="high",
        is_readonly=False,
    ))
