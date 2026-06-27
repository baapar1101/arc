# Removed __future__ annotations to fix OpenAPI schema generation

from typing import List
from fastapi import APIRouter, Depends, HTTPException, status, Request
from adapters.api.v1.support.dependencies import require_end_user_support_open
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from adapters.db.repositories.support.ticket_repository import TicketRepository
from adapters.db.repositories.support.message_repository import MessageRepository
from adapters.api.v1.schemas import QueryInfo, PaginatedResponse, SuccessResponse
from adapters.api.v1.support.schemas import (
    CreateTicketRequest,
    CreateMessageRequest,
    TicketResponse,
    MessageResponse,
    SubmitCsatRequest,
)
from app.core.auth_dependency import get_current_user, AuthContext
from app.services.support.support_attachment_service import SupportAttachmentService
from adapters.api.v1.support.message_helpers import serialize_message, serialize_messages
from adapters.api.v1.support.ticket_serialize import ticket_to_dict, ticket_response_dict
from adapters.db.repositories.support.attachment_repository import AttachmentRepository
from app.core.responses import success_response, format_datetime_fields, ApiError
from app.services.notification_service import NotificationService
from app.services.support.ticket_access_service import TicketAccessService
from app.services.support.ticket_lifecycle_service import TicketLifecycleService
from app.services.support.ticket_event_service import TicketEventService
from app.services.support.notification_helpers import (
    support_notification_context,
    support_operator_notification_context,
)
from app.core.cache import get_cache
from app.services.support.ticket_engagement_service import mark_user_read, submit_csat
import logging

router = APIRouter()


@router.post("/search", response_model=SuccessResponse)
async def search_user_tickets(
    request: Request,
    query_info: QueryInfo,
    _require_support: None = Depends(require_end_user_support_open),
    current_user: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """جستجو در تیکت‌های کاربر"""
    ticket_repo = TicketRepository(db)
    
    # تنظیم فیلدهای قابل جستجو
    if not query_info.search_fields:
        query_info.search_fields = ["title", "description"]

    # کش نتایج جستجوی تیکت‌های کاربر
    cache = get_cache()
    cache_key = None

    if cache.enabled:
        import json, hashlib
        key_payload = {
            "user_id": current_user.get_user_id(),
            "take": query_info.take,
            "skip": query_info.skip,
            "sort_by": query_info.sort_by,
            "sort_desc": query_info.sort_desc,
            "search": query_info.search,
            "search_fields": query_info.search_fields,
            "filters": query_info.filters,
        }
        key_str = json.dumps(key_payload, sort_keys=True, ensure_ascii=False)
        key_hash = hashlib.sha256(key_str.encode("utf-8")).hexdigest()[:16]
        cache_key = f"support_tickets_search:{key_hash}"
        cached = cache.get(cache_key)
        if cached is not None:
            return success_response(cached, request)
    
    tickets, total = ticket_repo.get_user_tickets(current_user.get_user_id(), query_info)
    
    ticket_dicts = [ticket_to_dict(ticket, db) for ticket in tickets]
    
    paginated_data = PaginatedResponse.create(
        items=ticket_dicts,
        total=total,
        page=(query_info.skip // query_info.take) + 1,
        limit=query_info.take
    )
    
    # Format datetime fields based on calendar type
    formatted_data = format_datetime_fields(paginated_data.dict(), request)

    if cache.enabled and cache_key:
        cache.set(cache_key, formatted_data, ttl=30)
    
    return success_response(formatted_data, request)


@router.post("", response_model=SuccessResponse)
async def create_ticket(
    request: Request,
    ticket_request: CreateTicketRequest,
    _require_support: None = Depends(require_end_user_support_open),
    current_user: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """ایجاد تیکت جدید"""
    ticket_repo = TicketRepository(db)
    
    # ایجاد تیکت
    ticket_data = {
        "title": ticket_request.title,
        "description": ticket_request.description,
        "user_id": current_user.get_user_id(),
        "category_id": ticket_request.category_id,
        "priority_id": ticket_request.priority_id,
        "status_id": 1,  # وضعیت پیش‌فرض: باز
        "is_internal": False
    }
    
    ticket = ticket_repo.create(ticket_data)

    from app.services.support.support_sla_service import SupportSlaService
    from app.services.support.support_broadcast import broadcast_ticket_created

    SupportSlaService(db).apply_on_create(ticket)
    
    # ایجاد پیام اولیه
    message_repo = MessageRepository(db)
    message_repo.create_message(
        ticket_id=ticket.id,
        sender_id=current_user.get_user_id(),
        sender_type="user",
        content=ticket_request.description,
        is_internal=False
    )
    
    # دریافت تیکت با جزئیات
    ticket_with_details = ticket_repo.get_ticket_with_details(ticket.id, current_user.get_user_id())
    
    # ارسال ناتیفیکیشن به اپراتورها
    try:
        logger = logging.getLogger(__name__)
        logger.info(f"شروع ارسال ناتیفیکیشن برای تیکت جدید {ticket.id}")
        
        notification_service = NotificationService(db)
        user = current_user.user
        user_name = f"{user.first_name or ''} {user.last_name or ''}".strip() or user.email or "کاربر"
        message_preview = ticket_request.description[:200] + ("..." if len(ticket_request.description) > 200 else "")
        
        context = support_operator_notification_context({
            "subject": f"تیکت جدید #{ticket.id}: {ticket.title}",
            "message": f"کاربر {user_name} تیکت جدیدی ایجاد کرده است:\n\n{message_preview}",
            "ticket_id": ticket.id,
            "ticket_title": ticket.title,
            "user_name": user_name,
            "category": ticket_with_details.category.name if ticket_with_details.category else "نامشخص",
            "priority": ticket_with_details.priority.name if ticket_with_details.priority else "نامشخص"
        }, ticket.id)
        
        logger.info(f"فراخوانی notify_support_operators برای تیکت {ticket.id} با context: {list(context.keys())}")
        
        notification_service.notify_support_operators(
            event_key="support.ticket_created",
            context=context
        )
        
        logger.info(f"notify_support_operators برای تیکت {ticket.id} با موفقیت اجرا شد")
    except Exception as e:
        # در صورت خطا، لاگ می‌کنیم اما فرآیند اصلی ادامه می‌یابد
        logger = logging.getLogger(__name__)
        logger.error(f"خطا در ارسال ناتیفیکیشن برای تیکت جدید {ticket.id}: {e}", exc_info=True)

    try:
        broadcast_ticket_created(db, ticket)
    except Exception:
        pass
    
    # Format datetime fields based on calendar type
    ticket_data = ticket_response_dict(ticket_with_details, db)
    formatted_data = format_datetime_fields(ticket_data, request)
    
    return success_response(formatted_data, request)


@router.get("/{ticket_id}", response_model=SuccessResponse)
async def get_ticket(
    request: Request,
    ticket_id: int,
    _require_support: None = Depends(require_end_user_support_open),
    current_user: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """مشاهده تیکت"""
    ticket_repo = TicketRepository(db)
    
    ticket = ticket_repo.get_ticket_with_details(ticket_id, current_user.get_user_id())
    if not ticket:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="تیکت یافت نشد"
        )
    
    # Format datetime fields based on calendar type
    ticket_data = ticket_response_dict(ticket, db)
    formatted_data = format_datetime_fields(ticket_data, request)
    
    return success_response(formatted_data, request)


@router.put("/{ticket_id}/close", response_model=SuccessResponse)
async def close_ticket(
    request: Request,
    ticket_id: int,
    _require_support: None = Depends(require_end_user_support_open),
    current_user: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """بستن تیکت توسط کاربر"""
    lifecycle = TicketLifecycleService(db)
    ticket = lifecycle.close_by_user(ticket_id, current_user.get_user_id())
    ticket_data = ticket_response_dict(ticket, db)
    formatted_data = format_datetime_fields(ticket_data, request)
    return success_response(formatted_data, request)


@router.put("/{ticket_id}/reopen", response_model=SuccessResponse)
async def reopen_ticket(
    request: Request,
    ticket_id: int,
    _require_support: None = Depends(require_end_user_support_open),
    current_user: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """بازگشایی تیکت توسط کاربر"""
    lifecycle = TicketLifecycleService(db)
    ticket = lifecycle.reopen_by_user(ticket_id, current_user.get_user_id())
    ticket_data = ticket_response_dict(ticket, db)
    formatted_data = format_datetime_fields(ticket_data, request)
    return success_response(formatted_data, request)


@router.get("/{ticket_id}/events", response_model=SuccessResponse)
async def get_ticket_events(
    request: Request,
    ticket_id: int,
    _require_support: None = Depends(require_end_user_support_open),
    current_user: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """دریافت تاریخچه رویدادهای تیکت"""
    access = TicketAccessService(db)
    access.get_user_ticket(ticket_id, current_user.get_user_id())
    events = TicketEventService(db).list_for_ticket(ticket_id)
    items = [
        {
            "id": e.id,
            "ticket_id": e.ticket_id,
            "actor_id": e.actor_id,
            "event_type": e.event_type,
            "old_value": e.old_value,
            "new_value": e.new_value,
            "created_at": e.created_at,
        }
        for e in events
    ]
    formatted_data = format_datetime_fields(items, request)
    return success_response(formatted_data, request)


@router.post("/{ticket_id}/messages", response_model=SuccessResponse)
async def send_message(
    request: Request,
    ticket_id: int,
    message_request: CreateMessageRequest,
    _require_support: None = Depends(require_end_user_support_open),
    current_user: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """ارسال پیام به تیکت"""
    access = TicketAccessService(db)
    message_repo = MessageRepository(db)
    
    ticket = access.get_user_ticket(ticket_id, current_user.get_user_id())
    access.assert_ticket_open(ticket)

    content = (message_request.content or "").strip()
    if not content and not message_request.attachment_ids:
        raise ApiError("EMPTY_MESSAGE", "متن پیام یا پیوست الزامی است", http_status=400)
    if not content:
        content = "📎 پیوست فایل"

    message = message_repo.create_message(
        ticket_id=ticket_id,
        sender_id=current_user.get_user_id(),
        sender_type="user",
        content=content,
        is_internal=False,
    )

    attachment_service = SupportAttachmentService(db)
    if message_request.attachment_ids:
        attachment_service.attach_to_message(ticket_id, message.id, message_request.attachment_ids)

    try:
        from adapters.db.repositories.user_repo import UserRepository

        notification_service = NotificationService(db)
        user_repo = UserRepository(db)
        user = current_user.user
        user_name = f"{user.first_name or ''} {user.last_name or ''}".strip() or user.email or "کاربر"
        message_preview = content[:200] + ("..." if len(content) > 200 else "")

        context = support_operator_notification_context({
            "subject": f"پاسخ جدید به تیکت #{ticket.id}",
            "message": f"کاربر {user_name} به تیکت شما پاسخ داد:\n\n{message_preview}",
            "ticket_id": ticket.id,
            "ticket_title": ticket.title,
            "user_name": user_name,
            "message_preview": message_preview
        }, ticket.id)

        assigned_operator_id = getattr(ticket, 'assigned_operator_id', None)

        if assigned_operator_id and not user_repo.is_support_operator(assigned_operator_id):
            logger = logging.getLogger(__name__)
            logger.warning(
                f"assigned_operator_id {assigned_operator_id} برای تیکت {ticket.id} "
                "یک اپراتور معتبر نیست. ارسال به همه اپراتورها"
            )
            assigned_operator_id = None

        notification_service.notify_support_operators(
            event_key="support.user_reply",
            context=context,
            assigned_operator_id=assigned_operator_id
        )
    except Exception as e:
        logger = logging.getLogger(__name__)
        logger.error(f"خطا در ارسال ناتیفیکیشن برای پاسخ کاربر به تیکت {ticket_id}: {e}")

    try:
        from app.services.support.support_broadcast import broadcast_message_created

        broadcast_message_created(
            db, ticket, sender_type="user", message_id=message.id, preview=content
        )
    except Exception:
        pass
    
    # Format datetime fields based on calendar type
    attachment_repo = AttachmentRepository(db)
    message_data = serialize_message(message, attachment_repo)
    formatted_data = format_datetime_fields(message_data, request)
    
    return success_response(formatted_data, request)


@router.post("/{ticket_id}/messages/search", response_model=SuccessResponse)
async def search_ticket_messages(
    request: Request,
    ticket_id: int,
    query_info: QueryInfo,
    _require_support: None = Depends(require_end_user_support_open),
    current_user: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """جستجو در پیام‌های تیکت"""
    access = TicketAccessService(db)
    message_repo = MessageRepository(db)
    
    access.get_user_ticket(ticket_id, current_user.get_user_id())
    
    if not query_info.search_fields:
        query_info.search_fields = ["content"]
    
    messages, total = message_repo.get_ticket_messages(
        ticket_id, query_info, exclude_internal=True
    )
    
    attachment_repo = AttachmentRepository(db)
    message_dicts = serialize_messages(messages, attachment_repo)
    
    paginated_data = PaginatedResponse.create(
        items=message_dicts,
        total=total,
        page=(query_info.skip // query_info.take) + 1,
        limit=query_info.take
    )
    
    # Format datetime fields based on calendar type
    formatted_data = format_datetime_fields(paginated_data.dict(), request)
    
    return success_response(formatted_data, request)


@router.post("/{ticket_id}/read", response_model=SuccessResponse)
async def mark_ticket_read_user(
    request: Request,
    ticket_id: int,
    _require_support: None = Depends(require_end_user_support_open),
    current_user: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """علامت‌گذاری تیکت به‌عنوان خوانده‌شده توسط کاربر"""
    access = TicketAccessService(db)
    ticket = access.get_user_ticket(ticket_id, current_user.get_user_id())
    mark_user_read(db, ticket)
    data = ticket_to_dict(ticket, db)
    return success_response(format_datetime_fields(data, request), request)


@router.post("/{ticket_id}/csat", response_model=SuccessResponse)
async def submit_ticket_csat(
    request: Request,
    ticket_id: int,
    body: SubmitCsatRequest,
    _require_support: None = Depends(require_end_user_support_open),
    current_user: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """ثبت رضایت‌سنجی پس از بستن تیکت"""
    access = TicketAccessService(db)
    ticket = access.get_user_ticket(ticket_id, current_user.get_user_id())
    if not ticket.status or not ticket.status.is_final:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="CSAT فقط برای تیکت‌های بسته مجاز است")
    try:
        ticket = submit_csat(db, ticket, body.rating, body.comment)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    data = ticket_to_dict(ticket, db)
    return success_response(format_datetime_fields(data, request), request)
