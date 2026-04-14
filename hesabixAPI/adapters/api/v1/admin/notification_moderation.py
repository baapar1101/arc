"""
API Endpoints برای پنل مدیریت و تایید قالب‌های نوتیفیکیشن (Admin)
"""
from typing import Optional
from fastapi import APIRouter, Depends, Request, Query, Body
from sqlalchemy.orm import Session
from pydantic import BaseModel, Field

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_app_permission
from app.core.responses import success_response, ApiError
from adapters.db.repositories.business_notification_repo import (
    NotificationModerationQueueRepository,
    BusinessNotificationTemplateRepository
)
from adapters.db.models.business import Business

router = APIRouter(prefix="/admin/notification-moderation", tags=["Admin - Notification Moderation"])


def _build_ai_summary_for_owner(queue_item) -> str:
    """ساخت متن خلاصه نظر AI برای نمایش به مالک کسب‌وکار"""
    parts = []
    if queue_item.ai_decision:
        decision_label = {"approve": "تایید", "reject": "رد", "review_required": "نیاز به بررسی مدیر"}.get(
            queue_item.ai_decision, queue_item.ai_decision
        )
        parts.append(f"نظر هوش مصنوعی: {decision_label}")
    if queue_item.ai_confidence is not None:
        parts.append(f"اطمینان: {float(queue_item.ai_confidence):.0f}٪")
    if queue_item.ai_suggestions and str(queue_item.ai_suggestions).strip():
        parts.append(f"پیشنهادات: {queue_item.ai_suggestions.strip()}")
    if queue_item.ai_flags and isinstance(queue_item.ai_flags, list) and len(queue_item.ai_flags) > 0:
        parts.append("موارد: " + "؛ ".join(str(f) for f in queue_item.ai_flags))
    if not parts:
        return ""
    return "\n".join(parts)


class ApproveTemplateRequest(BaseModel):
    """درخواست تایید قالب"""
    notes: Optional[str] = Field(None, description="یادداشت مدیر")


class RejectTemplateRequest(BaseModel):
    """درخواست رد قالب"""
    reason: str = Field(..., description="دلیل رد")
    notes: Optional[str] = Field(None, description="یادداشت اضافی")


class AdminEditTemplateRequest(BaseModel):
    """ویرایش قالب توسط مدیر (فقط برای آیتم‌های در صف)"""
    subject: Optional[str] = Field(None, description="موضوع")
    body: Optional[str] = Field(None, description="متن قالب")


@router.get("/queue")
@require_app_permission("moderate_notifications")
def get_moderation_queue(
    request: Request,
    status: Optional[str] = Query(None, description="فیلتر وضعیت"),
    ai_decision: Optional[str] = Query(None, description="فیلتر تصمیم AI"),
    business_id: Optional[int] = Query(None, description="فیلتر کسب‌وکار"),
    offset: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=200),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    دریافت صف بررسی قالب‌ها
    
    فقط مدیران سیستم دسترسی دارند
    """
    filters = {
        "status": status,
        "ai_decision": ai_decision,
        "business_id": business_id
    }
    
    queue_repo = NotificationModerationQueueRepository(db)
    queue_items, total = queue_repo.list_for_admin(filters, offset, limit)
    
    template_repo = BusinessNotificationTemplateRepository(db)
    
    items = []
    for qi in queue_items:
        # دریافت قالب (با بررسی business_id برای امنیت)
        template = template_repo.get_by_id(qi.template_id, business_id=qi.business_id)
        if not template:
            continue
        
        # دریافت اطلاعات کسب‌وکار
        business = db.query(Business).filter(Business.id == qi.business_id).first()
        
        items.append({
            "id": qi.id,  # برای سازگاری با frontend
            "queue_id": qi.id,  # نام توصیفی‌تر
            "template": {
                "id": template.id,
                "code": template.code,
                "name": template.name,
                "event_type": template.event_type,
                "channel": template.channel,
                "subject": template.subject,
                "body": template.body[:200] + "..." if len(template.body) > 200 else template.body,
                "full_body": template.body,
                "daily_limit": template.daily_limit
            },
            "business": {
                "id": business.id if business else None,
                "name": business.name if business else "نامشخص"
            },
            "status": qi.status,
            "priority": qi.priority,
            "ai_review": {
                "decision": qi.ai_decision,
                "confidence": float(qi.ai_confidence) if qi.ai_confidence else None,
                "flags": qi.ai_flags or [],
                "suggestions": qi.ai_suggestions,
                "reviewed_at": qi.ai_reviewed_at.isoformat() if qi.ai_reviewed_at else None
            } if qi.ai_decision else None,
            "admin_review": {
                "decision": qi.admin_decision,
                "notes": qi.admin_notes,
                "reviewed_at": qi.admin_reviewed_at.isoformat() if qi.admin_reviewed_at else None,
                "reviewed_by": qi.reviewed_by_admin_id
            } if qi.admin_decision else None,
            "created_at": qi.created_at.isoformat(),
            "completed_at": qi.completed_at.isoformat() if qi.completed_at else None
        })
    
    return success_response({
        "items": items,
        "total": total,
        "offset": offset,
        "limit": limit
    }, request)


@router.get("/queue/stats")
@require_app_permission("moderate_notifications")
def get_queue_stats(
    request: Request,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """آمار کلی صف بررسی"""
    from datetime import datetime, timedelta
    
    queue_repo = NotificationModerationQueueRepository(db)
    
    # تعداد در هر وضعیت
    from sqlalchemy import func
    from adapters.db.models.business_notification import NotificationModerationQueue
    
    status_counts = db.query(
        NotificationModerationQueue.status,
        func.count(NotificationModerationQueue.id)
    ).filter(
        NotificationModerationQueue.status.in_(['pending', 'ai_reviewing', 'ai_reviewed', 'admin_reviewing'])
    ).group_by(NotificationModerationQueue.status).all()
    
    # آمار AI
    ai_stats = db.query(
        NotificationModerationQueue.ai_decision,
        func.count(NotificationModerationQueue.id)
    ).filter(
        NotificationModerationQueue.ai_decision.isnot(None)
    ).group_by(NotificationModerationQueue.ai_decision).all()
    
    # آمار امروز
    today = datetime.utcnow().date()
    today_approved = db.query(func.count(NotificationModerationQueue.id)).filter(
        NotificationModerationQueue.admin_decision == 'approve',
        func.date(NotificationModerationQueue.admin_reviewed_at) == today
    ).scalar() or 0
    
    today_rejected = db.query(func.count(NotificationModerationQueue.id)).filter(
        NotificationModerationQueue.admin_decision == 'reject',
        func.date(NotificationModerationQueue.admin_reviewed_at) == today
    ).scalar() or 0
    
    return success_response({
        "queue_status": {status: count for status, count in status_counts},
        "ai_decisions": {decision: count for decision, count in ai_stats},
        "today": {
            "approved": today_approved,
            "rejected": today_rejected
        },
        "pending_total": sum(count for status, count in status_counts)
    }, request)


@router.post("/queue/{queue_id}/approve")
@require_app_permission("moderate_notifications")
def approve_template(
    request: Request,
    queue_id: int,
    data: ApproveTemplateRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """تایید قالب توسط مدیر سیستم"""
    from datetime import datetime
    
    queue_repo = NotificationModerationQueueRepository(db)
    queue_item = queue_repo.get_by_id(queue_id)
    
    if not queue_item:
        raise ApiError("QUEUE_ITEM_NOT_FOUND", "آیتم صف یافت نشد", http_status=404)
    
    if queue_item.status == 'completed':
        raise ApiError("ALREADY_COMPLETED", "این آیتم قبلاً بررسی شده است", http_status=400)
    
    template_repo = BusinessNotificationTemplateRepository(db)
    template = template_repo.get_by_id(queue_item.template_id, business_id=queue_item.business_id)
    
    if not template:
        raise ApiError("TEMPLATE_NOT_FOUND", "قالب یافت نشد", http_status=404)
    
    # ادغام دلیل AI با یادداشت مدیر برای مالک
    ai_summary = _build_ai_summary_for_owner(queue_item)
    admin_notes_combined = ai_summary
    if data.notes and data.notes.strip():
        admin_notes_combined = (ai_summary + "\n\nیادداشت مدیر: " + data.notes.strip()) if ai_summary else data.notes.strip()

    # به‌روزرسانی صف
    queue_repo.update(queue_item, {
        "status": "completed",
        "admin_decision": "approve",
        "admin_notes": data.notes,
        "admin_reviewed_at": datetime.utcnow(),
        "reviewed_by_admin_id": ctx.user.id,
        "completed_at": datetime.utcnow()
    })
    
    # فعال‌سازی قالب
    template_repo.update(template, {
        "status": "approved",
        "approval_status": "admin_approved",
        "is_active": True,
        "approved_by_admin_id": ctx.user.id,
        "admin_review_notes": admin_notes_combined or None,
        "approved_at": datetime.utcnow()
    })
    
    db.commit()
    
    return success_response({
        "message": "قالب با موفقیت تایید و فعال شد",
        "template_id": template.id
    }, request)


@router.post("/queue/{queue_id}/reject")
@require_app_permission("moderate_notifications")
def reject_template(
    request: Request,
    queue_id: int,
    data: RejectTemplateRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """رد قالب توسط مدیر سیستم"""
    from datetime import datetime
    
    queue_repo = NotificationModerationQueueRepository(db)
    queue_item = queue_repo.get_by_id(queue_id)
    
    if not queue_item:
        raise ApiError("QUEUE_ITEM_NOT_FOUND", "آیتم صف یافت نشد", http_status=404)
    
    if queue_item.status == 'completed':
        raise ApiError("ALREADY_COMPLETED", "این آیتم قبلاً بررسی شده است", http_status=400)
    
    template_repo = BusinessNotificationTemplateRepository(db)
    template = template_repo.get_by_id(queue_item.template_id, business_id=queue_item.business_id)
    
    if not template:
        raise ApiError("TEMPLATE_NOT_FOUND", "قالب یافت نشد", http_status=404)
    
    # ادغام دلیل AI با دلیل رد و یادداشت برای مالک
    ai_summary = _build_ai_summary_for_owner(queue_item)
    rejection_display = data.reason.strip()
    admin_notes_combined = ai_summary
    if data.notes and data.notes.strip():
        admin_notes_combined = (ai_summary + "\n\nیادداشت مدیر: " + data.notes.strip()) if ai_summary else data.notes.strip()
    if ai_summary:
        rejection_display = f"دلیل AI: {ai_summary}\n\nدلیل رد: {data.reason.strip()}"

    # به‌روزرسانی صف
    queue_repo.update(queue_item, {
        "status": "completed",
        "admin_decision": "reject",
        "admin_notes": data.notes,
        "admin_reviewed_at": datetime.utcnow(),
        "reviewed_by_admin_id": ctx.user.id,
        "completed_at": datetime.utcnow()
    })
    
    # رد قالب
    template_repo.update(template, {
        "status": "rejected",
        "approval_status": "rejected",
        "is_active": False,
        "rejection_reason": rejection_display,
        "admin_review_notes": admin_notes_combined or None,
        "rejected_at": datetime.utcnow()
    })
    
    db.commit()
    
    return success_response({
        "message": "قالب رد شد",
        "template_id": template.id
    }, request)


@router.patch("/queue/{queue_id}/template")
@require_app_permission("moderate_notifications")
def admin_edit_queue_template(
    request: Request,
    queue_id: int,
    data: AdminEditTemplateRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """ویرایش محتوای قالب توسط مدیر (فقط برای آیتم‌های در وضعیت قابل بررسی)"""
    queue_repo = NotificationModerationQueueRepository(db)
    queue_item = queue_repo.get_by_id(queue_id)
    if not queue_item:
        raise ApiError("QUEUE_ITEM_NOT_FOUND", "آیتم صف یافت نشد", http_status=404)
    if queue_item.status not in ("admin_reviewing", "ai_reviewed"):
        raise ApiError(
            "INVALID_STATUS",
            "فقط برای آیتم‌های در وضعیت «بررسی شده AI» یا «در بررسی مدیر» امکان ویرایش وجود دارد",
            http_status=400
        )
    template_repo = BusinessNotificationTemplateRepository(db)
    template = template_repo.get_by_id(queue_item.template_id, business_id=queue_item.business_id)
    if not template:
        raise ApiError("TEMPLATE_NOT_FOUND", "قالب یافت نشد", http_status=404)
    update_data = {}
    if data.subject is not None:
        update_data["subject"] = data.subject
    if data.body is not None:
        update_data["body"] = data.body
    if not update_data:
        return success_response({"message": "چیزی برای به‌روزرسانی ارسال نشده", "template_id": template.id}, request)
    template_repo.update(template, update_data)
    db.commit()
    return success_response({
        "message": "قالب به‌روزرسانی شد",
        "template_id": template.id
    }, request)


# Endpointهای جایگزین برای سازگاری با URLهای بدون /queue/
@router.post("/{queue_id}/approve")
@require_app_permission("moderate_notifications")
def approve_template_alt(
    request: Request,
    queue_id: int,
    data: Optional[ApproveTemplateRequest] = Body(default=None),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """تایید قالب توسط مدیر سیستم (endpoint جایگزین بدون /queue/)"""
    if data is None:
        data = ApproveTemplateRequest()
    return approve_template(request, queue_id, data, ctx, db)


@router.post("/{queue_id}/reject")
@require_app_permission("moderate_notifications")
def reject_template_alt(
    request: Request,
    queue_id: int,
    data: Optional[dict] = Body(default=None),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """رد قالب توسط مدیر سیستم (endpoint جایگزین بدون /queue/)"""
    # تبدیل داده‌های ورودی به RejectTemplateRequest
    if data is None:
        data = {}
    
    # پشتیبانی از فیلدهای مختلف: reason, rejection_reason
    reason = data.get('reason') or data.get('rejection_reason') or 'دلیل مشخص نشده'
    notes = data.get('notes')
    
    reject_data = RejectTemplateRequest(reason=reason, notes=notes)
    return reject_template(request, queue_id, reject_data, ctx, db)


@router.get("/templates/{template_id}")
@require_app_permission("moderate_notifications")
def get_template_for_review(
    request: Request,
    template_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """دریافت جزئیات کامل قالب برای بررسی"""
    template_repo = BusinessNotificationTemplateRepository(db)
    # برای admin، business_id اختیاری است (می‌تواند همه قالب‌ها را ببیند)
    template = template_repo.get_by_id(template_id, business_id=None)
    
    if not template:
        raise ApiError("TEMPLATE_NOT_FOUND", "قالب یافت نشد", http_status=404)
    
    # دریافت اطلاعات کسب‌وکار
    business = db.query(Business).filter(Business.id == template.business_id).first()
    
    # دریافت تاریخچه قالب‌های رد شده این کسب‌وکار
    from sqlalchemy import func, and_
    from adapters.db.models.business_notification import BusinessNotificationTemplate
    
    rejected_count = db.query(func.count(BusinessNotificationTemplate.id)).filter(
        and_(
            BusinessNotificationTemplate.business_id == template.business_id,
            BusinessNotificationTemplate.status == 'rejected'
        )
    ).scalar() or 0
    
    approved_count = db.query(func.count(BusinessNotificationTemplate.id)).filter(
        and_(
            BusinessNotificationTemplate.business_id == template.business_id,
            BusinessNotificationTemplate.status == 'approved'
        )
    ).scalar() or 0
    
    data = {
        "template": {
            "id": template.id,
            "code": template.code,
            "name": template.name,
            "description": template.description,
            "event_type": template.event_type,
            "channel": template.channel,
            "recipient_type": template.recipient_type,
            "subject": template.subject,
            "body": template.body,
            "daily_limit": template.daily_limit,
            "is_automated": template.is_automated,
            "created_at": template.created_at.isoformat()
        },
        "business": {
            "id": business.id if business else None,
            "name": business.name if business else "نامشخص",
            "rejected_templates_count": rejected_count,
            "approved_templates_count": approved_count
        },
        "ai_review": {
            "approved_by_ai": template.approved_by_ai,
            "confidence_score": float(template.ai_confidence_score) if template.ai_confidence_score else None,
            "notes": template.ai_review_notes
        }
    }
    
    return success_response(data, request)

