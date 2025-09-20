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

router = APIRouter()


@router.post("/tickets/search", response_model=SuccessResponse)
@require_app_permission("support_operator")
async def search_operator_tickets(
    query_info: QueryInfo = Body(...),
    current_user: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    request: Request = None
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
    ticket_id: int,
    current_user: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    request: Request = None
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
    ticket_id: int,
    status_request: UpdateStatusRequest,
    current_user: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    request: Request = None
):
    """تغییر وضعیت تیکت"""
    ticket_repo = TicketRepository(db)
    
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
    
    # دریافت تیکت با جزئیات
    ticket_with_details = ticket_repo.get_operator_ticket_with_details(ticket_id)
    
    # Format datetime fields based on calendar type
    ticket_data = TicketResponse.from_orm(ticket_with_details).dict()
    formatted_data = format_datetime_fields(ticket_data, request)
    
    return success_response(formatted_data, request)


@router.post("/tickets/{ticket_id}/assign", response_model=SuccessResponse)
@require_app_permission("support_operator")
async def assign_ticket(
    ticket_id: int,
    assign_request: AssignTicketRequest,
    current_user: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    request: Request = None
):
    """تخصیص تیکت به اپراتور"""
    ticket_repo = TicketRepository(db)
    
    ticket = ticket_repo.assign_ticket(ticket_id, assign_request.operator_id)
    if not ticket:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="تیکت یافت نشد"
        )
    
    # دریافت تیکت با جزئیات
    ticket_with_details = ticket_repo.get_operator_ticket_with_details(ticket_id)
    
    # Format datetime fields based on calendar type
    ticket_data = TicketResponse.from_orm(ticket_with_details).dict()
    formatted_data = format_datetime_fields(ticket_data, request)
    
    return success_response(formatted_data, request)


@router.post("/tickets/{ticket_id}/messages", response_model=SuccessResponse)
@require_app_permission("support_operator")
async def send_operator_message(
    ticket_id: int,
    message_request: CreateMessageRequest,
    current_user: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    request: Request = None
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
    
    # ایجاد پیام
    message = message_repo.create_message(
        ticket_id=ticket_id,
        sender_id=current_user.get_user_id(),
        sender_type="operator",
        content=message_request.content,
        is_internal=message_request.is_internal
    )
    
    # Format datetime fields based on calendar type
    message_data = MessageResponse.from_orm(message).dict()
    formatted_data = format_datetime_fields(message_data, request)
    
    return success_response(formatted_data, request)


@router.post("/tickets/{ticket_id}/messages/search", response_model=SuccessResponse)
@require_app_permission("support_operator")
async def search_operator_ticket_messages(
    ticket_id: int,
    query_info: QueryInfo = Body(...),
    current_user: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    request: Request = None
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
