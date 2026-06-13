"""مدیریت قالب‌های پیش‌فرض رویدادهای نوتیفیکیشن کسب‌وکار (notification_event_types)."""
from __future__ import annotations

from typing import Any, Dict, Optional

from fastapi import APIRouter, Body, Depends, HTTPException, Query, Request
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from adapters.db.repositories.business_notification_repo import NotificationEventTypeRepository
from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.permissions import require_app_permission
from app.core.responses import success_response
from app.services.business_notification_service import TemplateRenderService

router = APIRouter(
    prefix="/admin/notification-event-types",
    tags=["admin.notification_event_types"],
)


class EventTypeDefaultsPayload(BaseModel):
    default_sms_template: Optional[str] = None
    default_email_template: Optional[str] = None
    default_email_subject: Optional[str] = Field(default=None, max_length=200)


class PreviewPayload(BaseModel):
    channel: str = Field(..., description="sms یا email")
    default_sms_template: Optional[str] = None
    default_email_template: Optional[str] = None
    default_email_subject: Optional[str] = None
    context: Dict[str, Any] = Field(default_factory=dict)


def _serialize_event_type(et) -> Dict[str, Any]:
    return {
        "id": et.id,
        "code": et.code,
        "name": et.name,
        "description": et.description,
        "category": et.category,
        "available_variables": et.available_variables or [],
        "default_sms_template": et.default_sms_template,
        "default_email_template": et.default_email_template,
        "default_email_subject": et.default_email_subject,
        "is_active": et.is_active,
        "requires_approval": et.requires_approval,
        "has_sms_default": bool((et.default_sms_template or "").strip()),
        "has_email_default": bool((et.default_email_template or "").strip()),
        "updated_at": et.updated_at,
    }


@router.get("", summary="لیست رویدادها و قالب‌های پیش‌فرض سیستم")
@require_app_permission("system_settings")
def list_event_types(
    request: Request,
    category: Optional[str] = Query(None),
    search: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    repo = NotificationEventTypeRepository(db)
    items = repo.list_all(category=category, is_active=None)

    if search:
        q = search.strip().lower()
        items = [
            et
            for et in items
            if q in (et.code or "").lower()
            or q in (et.name or "").lower()
            or q in (et.description or "").lower()
        ]

    return success_response(
        {"items": [_serialize_event_type(et) for et in items]},
        request,
    )


@router.get("/{code}", summary="جزئیات یک رویداد")
@require_app_permission("system_settings")
def get_event_type(
    code: str,
    request: Request,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    repo = NotificationEventTypeRepository(db)
    et = repo.get_by_code(code)
    if not et:
        raise HTTPException(status_code=404, detail="نوع رویداد یافت نشد")
    return success_response(_serialize_event_type(et), request)


@router.put("/{code}", summary="ویرایش قالب‌های پیش‌فرض یک رویداد")
@require_app_permission("system_settings")
def update_event_type_defaults(
    code: str,
    request: Request,
    payload: EventTypeDefaultsPayload = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    repo = NotificationEventTypeRepository(db)
    et = repo.get_by_code(code)
    if not et:
        raise HTTPException(status_code=404, detail="نوع رویداد یافت نشد")

    update_data: Dict[str, Any] = {}
    if payload.default_sms_template is not None:
        update_data["default_sms_template"] = payload.default_sms_template
    if payload.default_email_template is not None:
        update_data["default_email_template"] = payload.default_email_template
    if payload.default_email_subject is not None:
        update_data["default_email_subject"] = payload.default_email_subject

    if not update_data:
        raise HTTPException(status_code=400, detail="حداقل یک فیلد برای به‌روزرسانی لازم است")

    renderer = TemplateRenderService()
    for field_name, text in (
        ("default_sms_template", payload.default_sms_template),
        ("default_email_template", payload.default_email_template),
        ("default_email_subject", payload.default_email_subject),
    ):
        if text:
            validation = renderer.validate_template(text, [])
            if not validation["is_valid"]:
                raise HTTPException(
                    status_code=400,
                    detail=f"خطا در {field_name}: {'; '.join(validation['errors'])}",
                )

    et = repo.update(et, update_data)
    db.commit()
    return success_response(_serialize_event_type(et), request)


@router.post("/{code}/preview", summary="پیش‌نمایش قالب پیش‌فرض")
@require_app_permission("system_settings")
def preview_event_type_defaults(
    code: str,
    request: Request,
    payload: PreviewPayload = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
) -> Dict[str, Any]:
    repo = NotificationEventTypeRepository(db)
    et = repo.get_by_code(code)
    if not et:
        raise HTTPException(status_code=404, detail="نوع رویداد یافت نشد")

    channel = payload.channel.strip().lower()
    if channel not in ("sms", "email"):
        raise HTTPException(status_code=400, detail="کانال باید sms یا email باشد")

    renderer = TemplateRenderService()
    context = dict(payload.context)

    if channel == "sms":
        body_tpl = payload.default_sms_template if payload.default_sms_template is not None else et.default_sms_template
        if not body_tpl:
            raise HTTPException(status_code=400, detail="قالب پیش‌فرض پیامک تعریف نشده")
        rendered_body = renderer.render(body_tpl, context)
        return success_response(
            {"channel": "sms", "subject": None, "body": rendered_body},
            request,
        )

    body_tpl = (
        payload.default_email_template
        if payload.default_email_template is not None
        else et.default_email_template
    )
    subject_tpl = (
        payload.default_email_subject
        if payload.default_email_subject is not None
        else et.default_email_subject
    )
    if not body_tpl:
        raise HTTPException(status_code=400, detail="قالب پیش‌فرض ایمیل تعریف نشده")

    rendered_body = renderer.render(body_tpl, context)
    rendered_subject = renderer.render(subject_tpl or "پیام", context) if subject_tpl else None
    return success_response(
        {"channel": "email", "subject": rendered_subject, "body": rendered_body},
        request,
    )
