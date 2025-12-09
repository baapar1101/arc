from typing import List
from fastapi import APIRouter, Depends, HTTPException, status, Request, Body
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from adapters.db.repositories.support.ticket_repository import TicketRepository
from adapters.db.repositories.support.message_repository import MessageRepository
from adapters.api.v1.schemas import QueryInfo, PaginatedResponse, SuccessResponse
from adapters.api.v1.support.schemas import (
    CreateMessageRequest,
    UpdateStatusRequest,
    AssignTicketRequest,
    TicketResponse,
    MessageResponse
)
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_app_permission
from app.core.responses import success_response, format_datetime_fields
from app.services.notification_service import NotificationService
import logging

router = APIRouter()


@router.post("/tickets/search", response_model=SuccessResponse)
@require_app_permission("support_operator")
async def search_operator_tickets(
    request: Request,
    query_info: QueryInfo = Body(...),
    current_user: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """جستجو در تمام تیکت‌ها برای اپراتور"""
    ticket_repo = TicketRepository(db)
    
    # تنظیم فیلدهای قابل جستجو
    if not query_info.search_fields:
        query_info.search_fields = ["title", "description", "user_email", "user_name"]
    
    tickets, total = ticket_repo.get_operator_tickets(query_info)
    
    # تبدیل به dict
    ticket_dicts = []
    for ticket in tickets:
        ticket_dict = {
            "id": ticket.id,
            "title": ticket.title,
            "description": ticket.description,
            "user_id": ticket.user_id,
            "category_id": ticket.category_id,
            "priority_id": ticket.priority_id,
            "status_id": ticket.status_id,
            "assigned_operator_id": ticket.assigned_operator_id,
            "is_internal": ticket.is_internal,
            "closed_at": ticket.closed_at,
            "created_at": ticket.created_at,
            "updated_at": ticket.updated_at,
            "user": {
                "id": ticket.user.id,
                "first_name": ticket.user.first_name,
                "last_name": ticket.user.last_name,
                "email": ticket.user.email
            } if ticket.user else None,
            "assigned_operator": {
                "id": ticket.assigned_operator.id,
                "first_name": ticket.assigned_operator.first_name,
                "last_name": ticket.assigned_operator.last_name,
                "email": ticket.assigned_operator.email
            } if ticket.assigned_operator else None,
            "category": {
                "id": ticket.category.id,
                "name": ticket.category.name,
                "description": ticket.category.description,
                "is_active": ticket.category.is_active,
                "created_at": ticket.category.created_at,
                "updated_at": ticket.category.updated_at
            } if ticket.category else None,
            "priority": {
                "id": ticket.priority.id,
                "name": ticket.priority.name,
                "description": ticket.priority.description,
                "color": ticket.priority.color,
                "order": ticket.priority.order,
                "created_at": ticket.priority.created_at,
                "updated_at": ticket.priority.updated_at
            } if ticket.priority else None,
            "status": {
                "id": ticket.status.id,
                "name": ticket.status.name,
                "description": ticket.status.description,
                "color": ticket.status.color,
                "is_final": ticket.status.is_final,
                "created_at": ticket.status.created_at,
                "updated_at": ticket.status.updated_at
            } if ticket.status else None
        }
        ticket_dicts.append(ticket_dict)
    
    paginated_data = PaginatedResponse.create(
        items=ticket_dicts,
        total=total,
        page=(query_info.skip // query_info.take) + 1,
        limit=query_info.take
    )
    
    # Format datetime fields based on calendar type
    formatted_data = format_datetime_fields(paginated_data.dict(), request)
    
    return success_response(formatted_data, request)


@router.get("/tickets/{ticket_id}", response_model=SuccessResponse)
@require_app_permission("support_operator")
async def get_operator_ticket(
    request: Request,
    ticket_id: int,
    current_user: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """مشاهده تیکت برای اپراتور"""
    ticket_repo = TicketRepository(db)
    
    ticket = ticket_repo.get_operator_ticket_with_details(ticket_id)
    if not ticket:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="تیکت یافت نشد"
        )
    
    # Format datetime fields based on calendar type
    ticket_data = TicketResponse.from_orm(ticket).dict()
    formatted_data = format_datetime_fields(ticket_data, request)
    
    return success_response(formatted_data, request)


@router.put("/tickets/{ticket_id}/status", response_model=SuccessResponse)
@require_app_permission("support_operator")
async def update_ticket_status(
    request: Request,
    ticket_id: int,
    status_request: UpdateStatusRequest,
    current_user: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """تغییر وضعیت تیکت"""
    ticket_repo = TicketRepository(db)
    
    # دریافت وضعیت قبلی تیکت
    old_ticket = ticket_repo.get_operator_ticket_with_details(ticket_id)
    if not old_ticket:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="تیکت یافت نشد"
        )
    
    old_status_id = old_ticket.status_id
    old_status_name = old_ticket.status.name if old_ticket.status else "نامشخص"
    
    ticket = ticket_repo.update_ticket_status(
        ticket_id=ticket_id,
        status_id=status_request.status_id,
        operator_id=status_request.assigned_operator_id or current_user.get_user_id()
    )
    
    if not ticket:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="تیکت یافت نشد"
        )
    
    db.commit()
    
    # دریافت تیکت با جزئیات جدید
    ticket_with_details = ticket_repo.get_operator_ticket_with_details(ticket_id)
    new_status_name = ticket_with_details.status.name if ticket_with_details.status else "نامشخص"
    
    # ارسال ناتیفیکیشن به کاربر صاحب تیکت (اگر وضعیت تغییر کرده باشد)
    if old_status_id != status_request.status_id and ticket_with_details.user_id:
        try:
            notification_service = NotificationService(db)
            operator_name = f"{current_user.user.first_name or ''} {current_user.user.last_name or ''}".strip() or "اپراتور پشتیبانی"
            
            context = {
                "subject": f"وضعیت تیکت #{ticket_id} تغییر کرد",
                "message": f"وضعیت تیکت شما (#{ticket_id}: {ticket.title}) از '{old_status_name}' به '{new_status_name}' تغییر کرد.",
                "ticket_id": ticket_id,
                "ticket_title": ticket.title,
                "operator_name": operator_name,
                "old_status": old_status_name,
                "new_status": new_status_name,
                "user_id": ticket_with_details.user_id  # برای audience_filters
            }
            
            notification_service.send(
                user_id=ticket_with_details.user_id,
                event_key="support.ticket_status_changed",
                context=context,
                preferred_channels=["inapp", "email", "telegram"],
                broadcast_mode=False
            )
        except Exception as e:
            logger = logging.getLogger(__name__)
            logger.error(f"خطا در ارسال ناتیفیکیشن برای تغییر وضعیت تیکت {ticket_id}: {e}")
    
    # Format datetime fields based on calendar type
    ticket_data = TicketResponse.from_orm(ticket_with_details).dict()
    formatted_data = format_datetime_fields(ticket_data, request)
    
    return success_response(formatted_data, request)


@router.post("/tickets/{ticket_id}/assign", response_model=SuccessResponse)
@require_app_permission("support_operator")
async def assign_ticket(
    request: Request,
    ticket_id: int,
    assign_request: AssignTicketRequest,
    current_user: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """تخصیص تیکت به اپراتور"""
    from adapters.db.repositories.user_repo import UserRepository
    
    ticket_repo = TicketRepository(db)
    user_repo = UserRepository(db)
    
    # بررسی اینکه operator_id واقعاً یک اپراتور است
    if assign_request.operator_id:
        if not user_repo.is_support_operator(assign_request.operator_id):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="کاربر مشخص شده یک اپراتور پشتیبانی نیست"
            )
    
    # بررسی وجود تیکت
    ticket = ticket_repo.get_operator_ticket_with_details(ticket_id)
    if not ticket:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="تیکت یافت نشد"
        )
    
    old_operator_id = ticket.assigned_operator_id
    new_operator_id = assign_request.operator_id
    
    # تخصیص تیکت
    ticket = ticket_repo.assign_ticket(ticket_id, assign_request.operator_id)
    if not ticket:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="تیکت یافت نشد"
        )
    
    db.commit()
    
    # دریافت تیکت با جزئیات
    ticket_with_details = ticket_repo.get_operator_ticket_with_details(ticket_id)
    
    # ارسال ناتیفیکیشن به اپراتور جدید (اگر تغییر کرده باشد)
    if new_operator_id and new_operator_id != old_operator_id:
        try:
            notification_service = NotificationService(db)
            operator = user_repo.get_by_id(new_operator_id)
            operator_name = f"{operator.first_name or ''} {operator.last_name or ''}".strip() if operator else "اپراتور پشتیبانی"
            
            context = {
                "subject": f"تیکت جدید به شما تخصیص داده شد: #{ticket_id}",
                "message": f"تیکت #{ticket_id}: {ticket.title} به شما تخصیص داده شد.",
                "ticket_id": ticket_id,
                "ticket_title": ticket.title,
                "operator_name": operator_name,
                "user_id": ticket_with_details.user_id  # برای audience_filters (اگر نیاز باشد)
            }
            
            notification_service.send(
                user_id=new_operator_id,
                event_key="support.ticket_assigned",
                context=context,
                preferred_channels=["inapp", "email", "telegram"],
                broadcast_mode=False
            )
        except Exception as e:
            logger = logging.getLogger(__name__)
            logger.error(f"خطا در ارسال ناتیفیکیشن برای تخصیص تیکت {ticket_id}: {e}")
    
    # Format datetime fields based on calendar type
    ticket_data = TicketResponse.from_orm(ticket_with_details).dict()
    formatted_data = format_datetime_fields(ticket_data, request)
    
    return success_response(formatted_data, request)


@router.post("/tickets/{ticket_id}/messages", response_model=SuccessResponse)
@require_app_permission("support_operator")
async def send_operator_message(
    request: Request,
    ticket_id: int,
    message_request: CreateMessageRequest,
    current_user: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """ارسال پیام اپراتور به تیکت"""
    ticket_repo = TicketRepository(db)
    message_repo = MessageRepository(db)
    
    # بررسی وجود تیکت
    ticket = ticket_repo.get_operator_ticket_with_details(ticket_id)
    if not ticket:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="تیکت یافت نشد"
        )
    
    # بررسی تخصیص: اگر تیکت به اپراتور دیگری تخصیص شده، فقط هشدار می‌دهیم اما اجازه پاسخ می‌دهیم
    # (ممکن است اپراتورها بخواهند به تیکت‌های یکدیگر کمک کنند)
    if ticket.assigned_operator_id and ticket.assigned_operator_id != current_user.get_user_id():
        logger = logging.getLogger(__name__)
        logger.info(f"اپراتور {current_user.get_user_id()} به تیکت {ticket_id} که به اپراتور {ticket.assigned_operator_id} تخصیص شده پاسخ می‌دهد")
    
    # ایجاد پیام
    message = message_repo.create_message(
        ticket_id=ticket_id,
        sender_id=current_user.get_user_id(),
        sender_type="operator",
        content=message_request.content,
        is_internal=message_request.is_internal
    )
    
    # اگر تیکت هنوز به اپراتور تخصیص نشده، آن را تخصیص ده
    if not ticket.assigned_operator_id:
        ticket_repo.assign_ticket(ticket_id, current_user.get_user_id())
        db.commit()
    
    # ارسال ناتیفیکیشن به کاربر (فقط برای پیام‌های غیرداخلی)
    if not message_request.is_internal and ticket.user_id:
        try:
            notification_service = NotificationService(db)
            operator_name = f"{current_user.user.first_name or ''} {current_user.user.last_name or ''}".strip() or "اپراتور پشتیبانی"
            message_preview = message_request.content[:200] + ("..." if len(message_request.content) > 200 else "")
            
            context = {
                "subject": f"پاسخ جدید به تیکت #{ticket_id}",
                "message": f"اپراتور {operator_name} به تیکت شما پاسخ داد:\n\n{message_preview}",
                "ticket_id": ticket_id,
                "ticket_title": ticket.title,
                "operator_name": operator_name,
                "message_preview": message_preview
            }
            
            notification_service.send(
                user_id=ticket.user_id,
                event_key="support.operator_reply",
                context=context,
                preferred_channels=["inapp", "email", "telegram", "sms"],
                broadcast_mode=False
            )
        except Exception as e:
            # در صورت خطا، لاگ می‌کنیم اما فرآیند اصلی ادامه می‌یابد
            logger = logging.getLogger(__name__)
            logger.error(f"خطا در ارسال ناتیفیکیشن برای پاسخ اپراتور به تیکت {ticket_id}: {e}")
    
    # Format datetime fields based on calendar type
    message_data = MessageResponse.from_orm(message).dict()
    formatted_data = format_datetime_fields(message_data, request)
    
    return success_response(formatted_data, request)


@router.post("/tickets/{ticket_id}/messages/search", response_model=SuccessResponse)
@require_app_permission("support_operator")
async def search_operator_ticket_messages(
    request: Request,
    ticket_id: int,
    query_info: QueryInfo = Body(...),
    current_user: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """جستجو در پیام‌های تیکت برای اپراتور"""
    ticket_repo = TicketRepository(db)
    message_repo = MessageRepository(db)
    
    # بررسی وجود تیکت
    ticket = ticket_repo.get_operator_ticket_with_details(ticket_id)
    if not ticket:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="تیکت یافت نشد"
        )
    
    # تنظیم فیلدهای قابل جستجو
    if not query_info.search_fields:
        query_info.search_fields = ["content"]
    
    messages, total = message_repo.get_ticket_messages(ticket_id, query_info)
    
    # تبدیل به dict
    message_dicts = []
    for message in messages:
        message_dict = {
            "id": message.id,
            "ticket_id": message.ticket_id,
            "sender_id": message.sender_id,
            "sender_type": message.sender_type,
            "content": message.content,
            "is_internal": message.is_internal,
            "created_at": message.created_at,
            "sender": {
                "id": message.sender.id,
                "first_name": message.sender.first_name,
                "last_name": message.sender.last_name,
                "email": message.sender.email
            } if message.sender else None
        }
        message_dicts.append(message_dict)
    
    paginated_data = PaginatedResponse.create(
        items=message_dicts,
        total=total,
        page=(query_info.skip // query_info.take) + 1,
        limit=query_info.take
    )
    
    # Format datetime fields based on calendar type
    formatted_data = format_datetime_fields(paginated_data.dict(), request)
    
    return success_response(formatted_data, request)


@router.delete("/tickets/{ticket_id}", response_model=SuccessResponse)
@require_app_permission("superadmin")
async def delete_ticket(
    request: Request,
    ticket_id: int,
    current_user: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """حذف تیکت (فقط برای مدیر سیستم)"""
    ticket_repo = TicketRepository(db)
    
    # حذف تیکت
    deleted = ticket_repo.delete_ticket(ticket_id)
    
    if not deleted:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="تیکت یافت نشد یا قبلاً حذف شده است"
        )
    
    return success_response(
        {"message": "تیکت با موفقیت حذف شد", "ticket_id": ticket_id},
        request
    )
