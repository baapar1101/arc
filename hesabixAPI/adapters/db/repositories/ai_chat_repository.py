from typing import Optional, List
from sqlalchemy.orm import Session
from sqlalchemy import and_, func, select
from datetime import datetime
from adapters.db.models.ai_chat_session import AIChatSession
from adapters.db.models.ai_chat_message import AIChatMessage
from adapters.db.repositories.base_repo import BaseRepository


class AIChatSessionRepository(BaseRepository[AIChatSession]):
    def __init__(self, db: Session):
        super().__init__(db, AIChatSession)
    
    def get_user_sessions(
        self,
        user_id: int,
        business_id: Optional[int] = None,
        limit: int = 50,
        skip: int = 0
    ) -> List[AIChatSession]:
        """دریافت جلسات چت کاربر"""
        query = self.db.query(self.model_class).filter(
            self.model_class.user_id == user_id
        )
        
        if business_id:
            query = query.filter(self.model_class.business_id == business_id)
        else:
            query = query.filter(self.model_class.business_id == None)  # noqa: E711
        
        return query.order_by(self.model_class.updated_at.desc()).offset(skip).limit(limit).all()
    
    def get_session_with_messages(
        self,
        session_id: int,
        user_id: int
    ) -> Optional[AIChatSession]:
        """دریافت جلسه با پیام‌ها"""
        session = self.db.query(self.model_class).filter(
            and_(
                self.model_class.id == session_id,
                self.model_class.user_id == user_id
            )
        ).first()
        
        if session:
            # Load messages
            session.messages
        return session
    
    def delete_old_empty_sessions(self, cutoff_date: datetime) -> int:
        """حذف جلسات قدیمی که هیچ پیامی ندارند"""
        # پیدا کردن جلساتی که پیامی ندارند و قدیمی هستند
        subquery = self.db.query(
            AIChatSession.id
        ).outerjoin(
            AIChatMessage, AIChatSession.id == AIChatMessage.session_id
        ).filter(
            AIChatSession.updated_at < cutoff_date
        ).group_by(
            AIChatSession.id
        ).having(
            func.count(AIChatMessage.id) == 0
        ).subquery()
        
        deleted = self.db.query(AIChatSession).filter(
            AIChatSession.id.in_(select(subquery.c.id))
        ).delete(synchronize_session=False)
        
        return deleted
    
    def delete_old_sessions(self, cutoff_date: datetime) -> int:
        """حذف جلسات قدیمی (حتی با پیام)"""
        deleted = self.db.query(AIChatSession).filter(
            AIChatSession.updated_at < cutoff_date
        ).delete(synchronize_session=False)
        
        return deleted


class AIChatMessageRepository(BaseRepository[AIChatMessage]):
    def __init__(self, db: Session):
        super().__init__(db, AIChatMessage)
    
    def get_session_messages(
        self,
        session_id: int,
        limit: int = 100,
        skip: int = 0
    ) -> List[AIChatMessage]:
        """دریافت پیام‌های یک جلسه"""
        return self.db.query(self.model_class).filter(
            self.model_class.session_id == session_id
        ).order_by(self.model_class.created_at.asc()).offset(skip).limit(limit).all()

