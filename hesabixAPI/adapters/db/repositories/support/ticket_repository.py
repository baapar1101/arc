from __future__ import annotations

from typing import Optional, List, Dict, Any
from sqlalchemy.orm import Session, joinedload
from sqlalchemy import select, func, and_, or_

from adapters.db.repositories.base_repo import BaseRepository
from adapters.db.models.support.ticket import Ticket
from adapters.db.models.support.message import Message
from adapters.api.v1.schemas import QueryInfo


class TicketRepository(BaseRepository[Ticket]):
    def __init__(self, db: Session):
        super().__init__(db, Ticket)
    
    def create(self, ticket_data: Dict[str, Any]) -> Ticket:
        """ایجاد تیکت جدید"""
        ticket = Ticket(**ticket_data)
        self.db.add(ticket)
        self.db.commit()
        self.db.refresh(ticket)
        return ticket
    
    def get_ticket_with_details(self, ticket_id: int, user_id: int) -> Optional[Ticket]:
        """دریافت تیکت با جزئیات کامل"""
        return self.db.query(Ticket)\
            .options(
                joinedload(Ticket.user),
                joinedload(Ticket.assigned_operator),
                joinedload(Ticket.category),
                joinedload(Ticket.priority),
                joinedload(Ticket.status),
                joinedload(Ticket.messages).joinedload(Message.sender)
            )\
            .filter(Ticket.id == ticket_id, Ticket.user_id == user_id)\
            .first()
    
    def get_operator_ticket_with_details(self, ticket_id: int) -> Optional[Ticket]:
        """دریافت تیکت برای اپراتور با جزئیات کامل"""
        return self.db.query(Ticket)\
            .options(
                joinedload(Ticket.user),
                joinedload(Ticket.assigned_operator),
                joinedload(Ticket.category),
                joinedload(Ticket.priority),
                joinedload(Ticket.status),
                joinedload(Ticket.messages).joinedload(Message.sender)
            )\
            .filter(Ticket.id == ticket_id)\
            .first()
    
    def get_user_tickets(self, user_id: int, query_info: QueryInfo) -> tuple[List[Ticket], int]:
        """دریافت تیکت‌های کاربر با فیلتر و صفحه‌بندی"""
        query = self.db.query(Ticket)\
            .options(
                joinedload(Ticket.category),
                joinedload(Ticket.priority),
                joinedload(Ticket.status)
            )\
            .filter(Ticket.user_id == user_id)
        
        # اعمال فیلترها
        if query_info.filters:
            for filter_item in query_info.filters:
                if filter_item.property == "title" and hasattr(Ticket, "title"):
                    if filter_item.operator == "*":
                        query = query.filter(Ticket.title.ilike(f"%{filter_item.value}%"))
                    elif filter_item.operator == "*?":
                        query = query.filter(Ticket.title.ilike(f"{filter_item.value}%"))
                    elif filter_item.operator == "?*":
                        query = query.filter(Ticket.title.ilike(f"%{filter_item.value}"))
                    elif filter_item.operator == "=":
                        query = query.filter(Ticket.title == filter_item.value)
                elif filter_item.property == "category.name":
                    query = query.join(Ticket.category)
                    if filter_item.operator == "in":
                        from adapters.db.models.support.category import Category
                        query = query.filter(Category.name.in_(filter_item.value))
                    else:
                        query = query.filter(Ticket.category.has(name=filter_item.value))
                elif filter_item.property == "priority.name":
                    query = query.join(Ticket.priority)
                    if filter_item.operator == "in":
                        from adapters.db.models.support.priority import Priority
                        query = query.filter(Priority.name.in_(filter_item.value))
                    else:
                        query = query.filter(Ticket.priority.has(name=filter_item.value))
                elif filter_item.property == "status.name":
                    query = query.join(Ticket.status)
                    if filter_item.operator == "in":
                        from adapters.db.models.support.status import Status
                        query = query.filter(Status.name.in_(filter_item.value))
                    else:
                        query = query.filter(Ticket.status.has(name=filter_item.value))
                elif filter_item.property == "description" and hasattr(Ticket, "description"):
                    if filter_item.operator == "*":
                        query = query.filter(Ticket.description.ilike(f"%{filter_item.value}%"))
                    elif filter_item.operator == "*?":
                        query = query.filter(Ticket.description.ilike(f"{filter_item.value}%"))
                    elif filter_item.operator == "?*":
                        query = query.filter(Ticket.description.ilike(f"%{filter_item.value}"))
                    elif filter_item.operator == "=":
                        query = query.filter(Ticket.description == filter_item.value)
        
        # اعمال جستجو
        if query_info.search and query_info.search_fields:
            search_conditions = []
            for field in query_info.search_fields:
                if hasattr(Ticket, field):
                    search_conditions.append(getattr(Ticket, field).ilike(f"%{query_info.search}%"))
            if search_conditions:
                query = query.filter(or_(*search_conditions))
        
        # شمارش کل
        total = query.count()
        
        # اعمال مرتب‌سازی
        if query_info.sort_by and hasattr(Ticket, query_info.sort_by):
            sort_column = getattr(Ticket, query_info.sort_by)
            if query_info.sort_desc:
                query = query.order_by(sort_column.desc())
            else:
                query = query.order_by(sort_column.asc())
        else:
            query = query.order_by(Ticket.created_at.desc())
        
        # اعمال صفحه‌بندی
        query = query.offset(query_info.skip).limit(query_info.take)
        
        return query.all(), total
    
    def get_operator_tickets(self, query_info: QueryInfo) -> tuple[List[Ticket], int]:
        """دریافت تمام تیکت‌ها برای اپراتور با فیلتر و صفحه‌بندی"""
        query = self.db.query(Ticket)\
            .options(
                joinedload(Ticket.user),
                joinedload(Ticket.assigned_operator),
                joinedload(Ticket.category),
                joinedload(Ticket.priority),
                joinedload(Ticket.status)
            )
        
        # اعمال فیلترها
        if query_info.filters:
            for filter_item in query_info.filters:
                if filter_item.property == "title" and hasattr(Ticket, "title"):
                    if filter_item.operator == "*":
                        query = query.filter(Ticket.title.ilike(f"%{filter_item.value}%"))
                    elif filter_item.operator == "*?":
                        query = query.filter(Ticket.title.ilike(f"{filter_item.value}%"))
                    elif filter_item.operator == "?*":
                        query = query.filter(Ticket.title.ilike(f"%{filter_item.value}"))
                    elif filter_item.operator == "=":
                        query = query.filter(Ticket.title == filter_item.value)
                elif filter_item.property == "category.name":
                    query = query.join(Ticket.category)
                    if filter_item.operator == "in":
                        from adapters.db.models.support.category import Category
                        query = query.filter(Category.name.in_(filter_item.value))
                    else:
                        query = query.filter(Ticket.category.has(name=filter_item.value))
                elif filter_item.property == "priority.name":
                    query = query.join(Ticket.priority)
                    if filter_item.operator == "in":
                        from adapters.db.models.support.priority import Priority
                        query = query.filter(Priority.name.in_(filter_item.value))
                    else:
                        query = query.filter(Ticket.priority.has(name=filter_item.value))
                elif filter_item.property == "status.name":
                    query = query.join(Ticket.status)
                    if filter_item.operator == "in":
                        from adapters.db.models.support.status import Status
                        query = query.filter(Status.name.in_(filter_item.value))
                    else:
                        query = query.filter(Ticket.status.has(name=filter_item.value))
                elif filter_item.property == "description" and hasattr(Ticket, "description"):
                    if filter_item.operator == "*":
                        query = query.filter(Ticket.description.ilike(f"%{filter_item.value}%"))
                    elif filter_item.operator == "*?":
                        query = query.filter(Ticket.description.ilike(f"{filter_item.value}%"))
                    elif filter_item.operator == "?*":
                        query = query.filter(Ticket.description.ilike(f"%{filter_item.value}"))
                    elif filter_item.operator == "=":
                        query = query.filter(Ticket.description == filter_item.value)
                elif filter_item.property == "user_email":
                    query = query.join(Ticket.user).filter(Ticket.user.has(email=filter_item.value))
                elif filter_item.property == "user_name":
                    query = query.join(Ticket.user).filter(
                        or_(
                            Ticket.user.has(first_name=filter_item.value),
                            Ticket.user.has(last_name=filter_item.value)
                        )
                    )
        
        # اعمال جستجو
        if query_info.search and query_info.search_fields:
            search_conditions = []
            for field in query_info.search_fields:
                if hasattr(Ticket, field):
                    search_conditions.append(getattr(Ticket, field).ilike(f"%{query_info.search}%"))
                elif field == "user_email" and hasattr(Ticket.user, "email"):
                    search_conditions.append(Ticket.user.email.ilike(f"%{query_info.search}%"))
                elif field == "user_name":
                    search_conditions.append(
                        or_(
                            Ticket.user.first_name.ilike(f"%{query_info.search}%"),
                            Ticket.user.last_name.ilike(f"%{query_info.search}%")
                        )
                    )
            if search_conditions:
                query = query.filter(or_(*search_conditions))
        
        # شمارش کل
        total = query.count()
        
        # اعمال مرتب‌سازی
        if query_info.sort_by and hasattr(Ticket, query_info.sort_by):
            sort_column = getattr(Ticket, query_info.sort_by)
            if query_info.sort_desc:
                query = query.order_by(sort_column.desc())
            else:
                query = query.order_by(sort_column.asc())
        else:
            query = query.order_by(Ticket.created_at.desc())
        
        # اعمال صفحه‌بندی
        query = query.offset(query_info.skip).limit(query_info.take)
        
        return query.all(), total
    
    def update_ticket_status(self, ticket_id: int, status_id: int, operator_id: Optional[int] = None) -> Optional[Ticket]:
        """تغییر وضعیت تیکت"""
        ticket = self.get_by_id(ticket_id)
        if not ticket:
            return None
        
        ticket.status_id = status_id
        if operator_id:
            ticket.assigned_operator_id = operator_id
        
        # اگر وضعیت نهایی است، تاریخ بسته شدن را تنظیم کن
        from adapters.db.models.support.status import Status
        status = self.db.query(Status).filter(Status.id == status_id).first()
        if status and status.is_final:
            from datetime import datetime
            ticket.closed_at = datetime.utcnow()
        
        self.db.commit()
        self.db.refresh(ticket)
        return ticket
    
    def assign_ticket(self, ticket_id: int, operator_id: int) -> Optional[Ticket]:
        """تخصیص تیکت به اپراتور"""
        ticket = self.get_by_id(ticket_id)
        if not ticket:
            return None
        
        ticket.assigned_operator_id = operator_id
        self.db.commit()
        self.db.refresh(ticket)
        return ticket
    
    def delete_ticket(self, ticket_id: int) -> bool:
        """
        حذف تیکت و تمام پیام‌های مرتبط
        
        Args:
            ticket_id: شناسه تیکت
            
        Returns:
            True اگر تیکت حذف شد، False اگر تیکت یافت نشد
        """
        ticket = self.get_by_id(ticket_id)
        if not ticket:
            return False
        
        # حذف تیکت (پیام‌ها به صورت CASCADE حذف می‌شوند)
        self.db.delete(ticket)
        self.db.commit()
        return True