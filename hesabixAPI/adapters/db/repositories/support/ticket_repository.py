from __future__ import annotations

from typing import Optional, List, Dict, Any
from sqlalchemy.orm import Session, joinedload, selectinload, defer
from sqlalchemy import select, func, and_, or_

from adapters.db.repositories.base_repo import BaseRepository
from adapters.db.models.support.ticket import Ticket
from adapters.db.models.support.message import Message
from adapters.api.v1.schemas import QueryInfo
from adapters.db.models.user import User
from adapters.db.models.support.category import Category
from adapters.db.models.support.priority import Priority
from adapters.db.models.support.status import Status


class TicketRepository(BaseRepository[Ticket]):
    def __init__(self, db: Session):
        super().__init__(db, Ticket)

    def _last_public_message_subquery(self):
        return (
            self.db.query(
                Message.ticket_id,
                func.max(Message.created_at).label("max_created_at"),
            )
            .filter(Message.is_internal.is_(False))
            .group_by(Message.ticket_id)
            .subquery()
        )

    def _last_public_message_meta_subquery(self):
        last_sub = self._last_public_message_subquery()
        return (
            self.db.query(
                Message.ticket_id.label("ticket_id"),
                Message.sender_type.label("sender_type"),
                Message.created_at.label("created_at"),
            )
            .join(
                last_sub,
                and_(
                    Message.ticket_id == last_sub.c.ticket_id,
                    Message.created_at == last_sub.c.max_created_at,
                    Message.is_internal.is_(False),
                ),
            )
            .subquery("last_public_message")
        )

    def _apply_last_message_from_user_filter(self, query, filter_value: str):
        filter_value = str(filter_value).lower() if filter_value else ""
        last_msg = self._last_public_message_meta_subquery()
        query = query.join(last_msg, Ticket.id == last_msg.c.ticket_id)
        if filter_value in ("true", "1"):
            return query.filter(last_msg.c.sender_type == "user")
        if filter_value in ("false", "0"):
            return query.filter(last_msg.c.sender_type == "operator")
        return query

    def _apply_unread_filter(self, query, role: str):
        last_msg = self._last_public_message_meta_subquery()
        query = query.join(last_msg, Ticket.id == last_msg.c.ticket_id)
        if role == "operator":
            return query.filter(
                last_msg.c.sender_type == "user",
                or_(
                    Ticket.operator_last_read_at.is_(None),
                    last_msg.c.created_at > Ticket.operator_last_read_at,
                ),
            )
        return query.filter(
            last_msg.c.sender_type == "operator",
            or_(
                Ticket.user_last_read_at.is_(None),
                last_msg.c.created_at > Ticket.user_last_read_at,
            ),
        )
    
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
        """دریافت تیکت‌های کاربر با فیلتر و صفحه‌بندی - بهینه‌سازی شده"""
        query = self.db.query(Ticket)\
            .options(
                selectinload(Ticket.category).load_only(Category.id, Category.name, Category.description, Category.is_active),
                selectinload(Ticket.priority).load_only(Priority.id, Priority.name, Priority.description, Priority.color, Priority.order),
                selectinload(Ticket.status).load_only(Status.id, Status.name, Status.description, Status.color, Status.is_final),
                defer(Ticket.description)  # description فقط در جزئیات نیاز است
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
                        query = query.filter(Category.name.in_(filter_item.value))
                    else:
                        query = query.filter(Ticket.category.has(name=filter_item.value))
                elif filter_item.property == "category_id":
                    if filter_item.operator == "in":
                        query = query.filter(Ticket.category_id.in_(filter_item.value))
                    elif filter_item.operator == "==":
                        query = query.filter(Ticket.category_id == filter_item.value)
                    else:
                        query = query.filter(Ticket.category_id == filter_item.value)
                elif filter_item.property == "priority.name":
                    query = query.join(Ticket.priority)
                    if filter_item.operator == "in":
                        query = query.filter(Priority.name.in_(filter_item.value))
                    else:
                        query = query.filter(Ticket.priority.has(name=filter_item.value))
                elif filter_item.property == "priority_id":
                    if filter_item.operator == "in":
                        query = query.filter(Ticket.priority_id.in_(filter_item.value))
                    elif filter_item.operator == "==":
                        query = query.filter(Ticket.priority_id == filter_item.value)
                    else:
                        query = query.filter(Ticket.priority_id == filter_item.value)
                elif filter_item.property == "status.name":
                    query = query.join(Ticket.status)
                    if filter_item.operator == "in":
                        query = query.filter(Status.name.in_(filter_item.value))
                    else:
                        query = query.filter(Ticket.status.has(name=filter_item.value))
                elif filter_item.property == "status_id":
                    if filter_item.operator == "in":
                        query = query.filter(Ticket.status_id.in_(filter_item.value))
                    elif filter_item.operator == "==":
                        query = query.filter(Ticket.status_id == filter_item.value)
                    else:
                        query = query.filter(Ticket.status_id == filter_item.value)
                elif filter_item.property == "description" and hasattr(Ticket, "description"):
                    if filter_item.operator == "*":
                        query = query.filter(Ticket.description.ilike(f"%{filter_item.value}%"))
                    elif filter_item.operator == "*?":
                        query = query.filter(Ticket.description.ilike(f"{filter_item.value}%"))
                    elif filter_item.operator == "?*":
                        query = query.filter(Ticket.description.ilike(f"%{filter_item.value}"))
                    elif filter_item.operator == "=":
                        query = query.filter(Ticket.description == filter_item.value)
                elif filter_item.property == "last_message_from_user":
                    query = self._apply_last_message_from_user_filter(query, filter_item.value)
                elif filter_item.property == "is_unread_for_user":
                    if str(filter_item.value).lower() in ("true", "1"):
                        query = self._apply_unread_filter(query, "user")
        
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
        """دریافت تمام تیکت‌ها برای اپراتور با فیلتر و صفحه‌بندی - بهینه‌سازی شده"""
        # استفاده از selectinload برای relations
        # defer برای description که در لیست نیاز نیست
        query = self.db.query(Ticket)\
            .options(
                selectinload(Ticket.user).load_only(User.id, User.first_name, User.last_name, User.email),
                selectinload(Ticket.assigned_operator).load_only(User.id, User.first_name, User.last_name, User.email),
                selectinload(Ticket.category).load_only(Category.id, Category.name, Category.description, Category.is_active),
                selectinload(Ticket.priority).load_only(Priority.id, Priority.name, Priority.description, Priority.color, Priority.order),
                selectinload(Ticket.status).load_only(Status.id, Status.name, Status.description, Status.color, Status.is_final),
                defer(Ticket.description)  # description فقط در جزئیات نیاز است
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
                        query = query.filter(Category.name.in_(filter_item.value))
                    else:
                        query = query.filter(Ticket.category.has(name=filter_item.value))
                elif filter_item.property == "priority.name":
                    query = query.join(Ticket.priority)
                    if filter_item.operator == "in":
                        query = query.filter(Priority.name.in_(filter_item.value))
                    else:
                        query = query.filter(Ticket.priority.has(name=filter_item.value))
                elif filter_item.property == "priority_id":
                    if filter_item.operator == "in":
                        query = query.filter(Ticket.priority_id.in_(filter_item.value))
                    elif filter_item.operator == "==":
                        query = query.filter(Ticket.priority_id == filter_item.value)
                    else:
                        query = query.filter(Ticket.priority_id == filter_item.value)
                elif filter_item.property == "status.name":
                    query = query.join(Ticket.status)
                    if filter_item.operator == "in":
                        query = query.filter(Status.name.in_(filter_item.value))
                    else:
                        query = query.filter(Ticket.status.has(name=filter_item.value))
                elif filter_item.property == "status_id":
                    if filter_item.operator == "in":
                        query = query.filter(Ticket.status_id.in_(filter_item.value))
                    elif filter_item.operator == "==":
                        query = query.filter(Ticket.status_id == filter_item.value)
                    else:
                        query = query.filter(Ticket.status_id == filter_item.value)
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
                elif filter_item.property == "category_id":
                    if filter_item.operator == "in":
                        query = query.filter(Ticket.category_id.in_(filter_item.value))
                    else:
                        query = query.filter(Ticket.category_id == filter_item.value)
                elif filter_item.property == "assigned_operator_id":
                    if filter_item.operator in ("is_null", "==") and filter_item.value is None:
                        query = query.filter(Ticket.assigned_operator_id.is_(None))
                    elif filter_item.operator == "==":
                        query = query.filter(Ticket.assigned_operator_id == filter_item.value)
                elif filter_item.property == "last_message_from_user":
                    query = self._apply_last_message_from_user_filter(query, filter_item.value)
                elif filter_item.property == "is_unread_for_operator":
                    if str(filter_item.value).lower() in ("true", "1"):
                        query = self._apply_unread_filter(query, "operator")
                elif filter_item.property == "sla_breached":
                    if str(filter_item.value).lower() in ("true", "1"):
                        query = query.filter(Ticket.sla_breached.is_(True))
                    elif str(filter_item.value).lower() in ("false", "0"):
                        query = query.filter(Ticket.sla_breached.is_(False))
        
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
        
        status = self.db.query(Status).filter(Status.id == status_id).first()
        from datetime import datetime
        if status and status.is_final:
            ticket.closed_at = datetime.utcnow()
        else:
            ticket.closed_at = None
        
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
    
    def bulk_assign_tickets(self, ticket_ids: List[int], operator_id: int) -> int:
        """تخصیص گروهی تیکت‌ها به اپراتور"""
        updated = self.db.query(Ticket)\
            .filter(Ticket.id.in_(ticket_ids))\
            .update({Ticket.assigned_operator_id: operator_id}, synchronize_session=False)
        self.db.commit()
        return updated
    
    def bulk_update_status(self, ticket_ids: List[int], status_id: int, operator_id: Optional[int] = None) -> int:
        """تغییر وضعیت گروهی تیکت‌ها"""
        update_dict = {Ticket.status_id: status_id}
        if operator_id:
            update_dict[Ticket.assigned_operator_id] = operator_id
        
        status = self.db.query(Status).filter(Status.id == status_id).first()
        from datetime import datetime
        if status and status.is_final:
            update_dict[Ticket.closed_at] = datetime.utcnow()
        else:
            update_dict[Ticket.closed_at] = None
        
        updated = self.db.query(Ticket)\
            .filter(Ticket.id.in_(ticket_ids))\
            .update(update_dict, synchronize_session=False)
        self.db.commit()
        return updated
    
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