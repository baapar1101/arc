"""
API Endpoints برای مدیریت قالب‌های نوتیفیکیشن کسب‌وکارها
"""
from typing import Optional, Dict, Any
from fastapi import APIRouter, Depends, Request, Query, Body
from sqlalchemy.orm import Session
from pydantic import BaseModel, Field

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError
from adapters.db.repositories.business_notification_repo import (
    NotificationEventTypeRepository,
    BusinessNotificationTemplateRepository,
    NotificationModerationQueueRepository,
    NotificationSendLogRepository
)
from app.services.business_notification_service import (
    BusinessNotificationService,
    TemplateRenderService
)

router = APIRouter(prefix="/business-notifications", tags=["Business Notifications"])


# ========== Schema Models ==========

class TemplateCreate(BaseModel):
    """ایجاد قالب جدید"""
    code: str = Field(..., max_length=100, description="کد یکتا قالب")
    name: str = Field(..., max_length=200, description="نام قالب")
    description: Optional[str] = None
    event_type: str = Field(..., description="نوع رویداد (مثلاً invoice.created)")
    channel: str = Field(..., description="کانال: sms یا email")
    recipient_type: str = Field(default="customer", description="نوع گیرنده")
    subject: Optional[str] = Field(None, max_length=200, description="موضوع (برای email)")
    body: str = Field(..., description="محتوای قالب")
    daily_limit: int = Field(default=100, ge=1, le=10000, description="حداکثر ارسال روزانه")
    is_automated: bool = Field(default=False, description="ارسال خودکار")


class TemplateUpdate(BaseModel):
    """به‌روزرسانی قالب"""
    name: Optional[str] = Field(None, max_length=200)
    description: Optional[str] = None
    subject: Optional[str] = Field(None, max_length=200)
    body: Optional[str] = None
    daily_limit: Optional[int] = Field(None, ge=1, le=10000)
    is_automated: Optional[bool] = None
    is_active: Optional[bool] = None


class SendNotificationRequest(BaseModel):
    """درخواست ارسال نوتیفیکیشن"""
    person_id: int = Field(..., description="شناسه Person")
    event_type: str = Field(..., description="نوع رویداد")
    context: Dict[str, Any] = Field(..., description="داده‌های متغیرها")
    channel: Optional[str] = Field(None, description="کانال (None = همه)")
    recipient_mobile: Optional[str] = Field(None, description="شماره موبایل مقصد (اختیاری؛ در صورت ارسال برای SMS به این شماره ارسال می‌شود)")


class PreviewTemplateRequest(BaseModel):
    """درخواست پیش‌نمایش قالب"""
    sample_context: Dict[str, Any] = Field(..., description="Context نمونه")


# ========== Event Types (لیست رویدادهای قابل استفاده) ==========

@router.get("/event-types")
def list_event_types(
    request: Request,
    category: Optional[str] = Query(None),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    لیست انواع رویدادهای قابل استفاده
    
    هر کسب‌وکار می‌تواند برای این رویدادها قالب تعریف کند
    """
    repo = NotificationEventTypeRepository(db)
    event_types = repo.list_all(category=category, is_active=True)
    
    items = []
    for et in event_types:
        items.append({
            "id": et.id,
            "code": et.code,
            "name": et.name,
            "description": et.description,
            "category": et.category,
            "available_variables": et.available_variables or [],
            "default_sms_template": et.default_sms_template,
            "default_email_template": et.default_email_template,
            "requires_approval": et.requires_approval
        })
    
    return success_response({"items": items, "total": len(items)}, request)


# ========== Templates Management (برای کسب‌وکار) ==========

@router.get("/businesses/{business_id}/templates")
def list_templates(
    request: Request,
    business_id: int,
    status: Optional[str] = Query(None),
    channel: Optional[str] = Query(None),
    event_type: Optional[str] = Query(None),
    offset: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=200),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """لیست قالب‌های یک کسب‌وکار"""
    if not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
    
    filters = {
        "status": status,
        "channel": channel,
        "event_type": event_type
    }
    
    repo = BusinessNotificationTemplateRepository(db)
    templates, total = repo.list_by_business(business_id, filters, offset, limit)
    
    items = []
    for t in templates:
        items.append({
            "id": t.id,
            "code": t.code,
            "name": t.name,
            "description": t.description,
            "event_type": t.event_type,
            "channel": t.channel,
            "status": t.status,
            "is_active": t.is_active,
            "approval_status": t.approval_status,
            "approved_by_ai": t.approved_by_ai,
            "ai_confidence_score": float(t.ai_confidence_score) if t.ai_confidence_score else None,
            "admin_review_notes": t.admin_review_notes,
            "rejection_reason": t.rejection_reason,
            "daily_limit": t.daily_limit,
            "is_automated": t.is_automated,
            "created_at": t.created_at.isoformat(),
            "updated_at": t.updated_at.isoformat()
        })
    
    return success_response({
        "items": items,
        "total": total,
        "offset": offset,
        "limit": limit
    }, request)


@router.get("/businesses/{business_id}/templates/{template_id}")
def get_template(
    request: Request,
    business_id: int,
    template_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """دریافت جزئیات یک قالب"""
    if not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
    
    repo = BusinessNotificationTemplateRepository(db)
    template = repo.get_by_id(template_id, business_id)
    
    if not template:
        raise ApiError("TEMPLATE_NOT_FOUND", "قالب یافت نشد", http_status=404)
    
    data = {
        "id": template.id,
        "code": template.code,
        "name": template.name,
        "description": template.description,
        "event_type": template.event_type,
        "channel": template.channel,
        "recipient_type": template.recipient_type,
        "subject": template.subject,
        "body": template.body,
        "available_variables": template.available_variables or [],
        "status": template.status,
        "is_active": template.is_active,
        "approval_status": template.approval_status,
        "approved_by_ai": template.approved_by_ai,
        "ai_confidence_score": float(template.ai_confidence_score) if template.ai_confidence_score else None,
        "ai_review_notes": template.ai_review_notes,
        "admin_review_notes": template.admin_review_notes,
        "rejection_reason": template.rejection_reason,
        "daily_limit": template.daily_limit,
        "is_automated": template.is_automated,
        "created_at": template.created_at.isoformat(),
        "updated_at": template.updated_at.isoformat()
    }
    
    return success_response(data, request)


@router.post("/businesses/{business_id}/templates")
def create_template(
    request: Request,
    business_id: int,
    data: TemplateCreate,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    ایجاد قالب جدید
    
    قالب با وضعیت 'draft' ایجاد می‌شود و باید برای تایید ارسال شود
    """
    if not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
    
    if not ctx.has_business_permission("notifications", "write"):
        raise ApiError("FORBIDDEN", "دسترسی ایجاد قالب ندارید", http_status=403)
    
    repo = BusinessNotificationTemplateRepository(db)
    
    # بررسی تکراری بودن code
    existing = repo.get_by_code(business_id, data.code)
    if existing:
        raise ApiError("CODE_EXISTS", "کد قالب تکراری است", http_status=409)
    
    # بررسی event_type معتبر باشد
    event_repo = NotificationEventTypeRepository(db)
    event_type = event_repo.get_by_code(data.event_type)
    if not event_type:
        raise ApiError("INVALID_EVENT_TYPE", "نوع رویداد نامعتبر است", http_status=400)
    
    # اعتبارسنجی قالب
    renderer = TemplateRenderService()
    validation = renderer.validate_template(
        data.body,
        [var['key'] for var in (event_type.available_variables or [])]
    )
    
    if not validation['is_valid']:
        raise ApiError(
            "INVALID_TEMPLATE",
            f"قالب نامعتبر است: {', '.join(validation['errors'])}",
            http_status=400
        )
    
    # ایجاد قالب
    template_data = data.dict()
    template_data.update({
        "business_id": business_id,
        "created_by_user_id": ctx.user.id,
        "available_variables": event_type.available_variables,
        "status": "draft",
        "is_active": False,
        "approval_status": "pending"
    })
    
    template = repo.create(template_data)
    db.commit()
    
    return success_response({
        "id": template.id,
        "code": template.code,
        "status": template.status,
        "message": "قالب ایجاد شد. برای فعال‌سازی باید آن را برای تایید ارسال کنید."
    }, request)


@router.put("/businesses/{business_id}/templates/{template_id}")
def update_template(
    request: Request,
    business_id: int,
    template_id: int,
    data: TemplateUpdate,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """به‌روزرسانی قالب"""
    if not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
    
    if not ctx.has_business_permission("notifications", "write"):
        raise ApiError("FORBIDDEN", "دسترسی ویرایش قالب ندارید", http_status=403)
    
    repo = BusinessNotificationTemplateRepository(db)
    template = repo.get_by_id(template_id, business_id)
    
    if not template:
        raise ApiError("TEMPLATE_NOT_FOUND", "قالب یافت نشد", http_status=404)
    
    # قالب‌های تایید شده را نمی‌توان ویرایش کرد
    if template.status == "approved":
        raise ApiError(
            "CANNOT_EDIT_APPROVED",
            "قالب تایید شده قابل ویرایش نیست. باید قالب جدید ایجاد کنید.",
            http_status=400
        )
    
    # اعتبارسنجی body در صورت تغییر
    if data.body:
        event_repo = NotificationEventTypeRepository(db)
        event_type = event_repo.get_by_code(template.event_type)
        
        renderer = TemplateRenderService()
        validation = renderer.validate_template(
            data.body,
            [var['key'] for var in (event_type.available_variables or [])]
        )
        
        if not validation['is_valid']:
            raise ApiError(
                "INVALID_TEMPLATE",
                f"قالب نامعتبر است: {', '.join(validation['errors'])}",
                http_status=400
            )
    
    # به‌روزرسانی
    update_data = data.dict(exclude_unset=True)
    template = repo.update(template, update_data)
    db.commit()
    
    return success_response({
        "id": template.id,
        "message": "قالب به‌روزرسانی شد"
    }, request)


@router.post("/businesses/{business_id}/templates/{template_id}/submit-for-approval")
def submit_for_approval(
    request: Request,
    business_id: int,
    template_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    ارسال قالب برای تایید
    
    قالب وارد صف بررسی می‌شود و ابتدا توسط AI بررسی می‌شود
    """
    if not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
    
    template_repo = BusinessNotificationTemplateRepository(db)
    template = template_repo.get_by_id(template_id, business_id)
    
    if not template:
        raise ApiError("TEMPLATE_NOT_FOUND", "قالب یافت نشد", http_status=404)
    
    if template.status not in ["draft", "rejected"]:
        raise ApiError(
            "INVALID_STATUS",
            f"قالب در وضعیت {template.status} قابل ارسال برای تایید نیست",
            http_status=400
        )
    
    # بررسی اینکه قبلاً در صف نباشد
    queue_repo = NotificationModerationQueueRepository(db)
    existing = queue_repo.get_by_template(template_id)
    
    if existing:
        raise ApiError(
            "ALREADY_IN_QUEUE",
            "این قالب در حال حاضر در صف بررسی است",
            http_status=409
        )
    
    # ایجاد آیتم در صف
    queue_data = {
        "template_id": template_id,
        "business_id": business_id,
        "status": "pending",
        "priority": 0
    }
    queue_repo.create(queue_data)
    
    # به‌روزرسانی وضعیت قالب
    template_repo.update(template, {
        "status": "pending_approval"
    })
    
    db.commit()
    
    return success_response({
        "message": "قالب برای تایید ارسال شد و به زودی بررسی خواهد شد",
        "estimated_time": "معمولاً کمتر از 5 دقیقه"
    }, request)


@router.post("/businesses/{business_id}/templates/{template_id}/preview")
def preview_template(
    request: Request,
    business_id: int,
    template_id: int,
    data: PreviewTemplateRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """پیش‌نمایش قالب با context نمونه"""
    if not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
    
    service = BusinessNotificationService(db)
    result = service.preview_template(business_id, template_id, data.sample_context)
    
    return success_response(result, request)


@router.post("/businesses/{business_id}/send")
def send_notification(
    request: Request,
    business_id: int,
    data: SendNotificationRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    ارسال نوتیفیکیشن به یک Person
    
    از قالب فعال مرتبط با event_type استفاده می‌کند
    """
    if not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
    
    if not ctx.has_business_permission("notifications", "send"):
        raise ApiError("FORBIDDEN", "دسترسی ارسال نوتیفیکیشن ندارید", http_status=403)
    
    service = BusinessNotificationService(db)
    result = service.send_to_person(
        business_id=business_id,
        person_id=data.person_id,
        event_type=data.event_type,
        context=data.context,
        channel=data.channel,
        recipient_mobile_override=(data.recipient_mobile.strip() or None) if data.recipient_mobile else None,
        triggered_by_user_id=ctx.user.id
    )
    
    return success_response(result, request)


@router.get("/businesses/{business_id}/logs")
def list_send_logs(
    request: Request,
    business_id: int,
    channel: Optional[str] = Query(None),
    status: Optional[str] = Query(None),
    template_id: Optional[int] = Query(None),
    offset: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=200),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """لیست لاگ‌های ارسال"""
    if not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "دسترسی به این کسب‌وکار ندارید", http_status=403)
    
    filters = {
        "channel": channel,
        "status": status,
        "template_id": template_id
    }
    
    repo = NotificationSendLogRepository(db)
    logs, total = repo.list_by_business(business_id, filters, offset, limit)
    
    items = []
    for log in logs:
        items.append({
            "id": log.id,
            "template_id": log.template_id,
            "recipient_type": log.recipient_type,
            "recipient_id": log.recipient_id,
            "recipient_identifier": log.recipient_identifier,
            "channel": log.channel,
            "status": log.status,
            "event_type": log.event_type,
            "sent_at": log.sent_at.isoformat() if log.sent_at else None,
            "failed_at": log.failed_at.isoformat() if log.failed_at else None,
            "failure_reason": log.failure_reason,
            "cost": float(log.cost) if log.cost else None,
            "created_at": log.created_at.isoformat()
        })
    
    return success_response({
        "items": items,
        "total": total,
        "offset": offset,
        "limit": limit
    }, request)

