from __future__ import annotations

from typing import Optional, List
from sqlalchemy.orm import Session, joinedload
from sqlalchemy import select, func, and_, or_

from adapters.db.repositories.base_repo import BaseRepository
from adapters.db.models.support.message import Message, SenderType
from adapters.api.v1.schemas import QueryInfo


class MessageRepository(BaseRepository[Message]):
    def __init__(self, db: Session):
        super().__init__(db, Message)
    
    def get_ticket_messages(self, ticket_id: int, query_info: QueryInfo) -> tuple[List[Message], int]:
        """دریافت پیام‌های تیکت با فیلتر و صفحه‌بندی"""
        query = self.db.query(Message)\
            .options(joinedload(Message.sender))\
            .filter(Message.ticket_id == ticket_id)
        
        # اعمال جستجو
        if query_info.search and query_info.search_fields:
            search_conditions = []
            for field in query_info.search_fields:
                if hasattr(Message, field):
                    search_conditions.append(getattr(Message, field).ilike(f"%{query_info.search}%"))
            if search_conditions:
                query = query.filter(or_(*search_conditions))
        
        # شمارش کل
        total = query.count()
        
        # اعمال مرتب‌سازی
        if query_info.sort_by and hasattr(Message, query_info.sort_by):
            sort_column = getattr(Message, query_info.sort_by)
            if query_info.sort_desc:
                query = query.order_by(sort_column.desc())
            else:
                query = query.order_by(sort_column.asc())
        else:
            query = query.order_by(Message.created_at.asc())
        
        # اعمال صفحه‌بندی
        query = query.offset(query_info.skip).limit(query_info.take)
        
        return query.all(), total
    
    def create_message(
        self, 
        ticket_id: int, 
        sender_id: int, 
        sender_type: SenderType, 
        content: str, 
        is_internal: bool = False
    ) -> Message:
        """ایجاد پیام جدید"""
        from datetime import datetime
        from adapters.db.models.support.ticket import Ticket
        
        message = Message(
            ticket_id=ticket_id,
            sender_id=sender_id,
            sender_type=sender_type,
            content=content,
            is_internal=is_internal
        )
        
        self.db.add(message)
        
        # Update ticket's updated_at field
        ticket = self.db.query(Ticket).filter(Ticket.id == ticket_id).first()
        if ticket:
            ticket.updated_at = datetime.utcnow()
        
        self.db.commit()
        self.db.refresh(message)
        return message
