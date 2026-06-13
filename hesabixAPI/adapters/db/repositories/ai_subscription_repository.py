from typing import Optional, List
from sqlalchemy.orm import Session, joinedload
from sqlalchemy import and_, func
from datetime import datetime, timedelta
from adapters.db.models.ai_subscription import UserAISubscription
from adapters.db.repositories.base_repo import BaseRepository


class AISubscriptionRepository(BaseRepository[UserAISubscription]):
    def __init__(self, db: Session):
        super().__init__(db, UserAISubscription)

    def get_by_id_for_update(self, subscription_id: int) -> Optional[UserAISubscription]:
        """قفل سطح ردیف برای به‌روزرسانی اتمی سهمیه."""
        return (
            self.db.query(self.model_class)
            .options(joinedload(self.model_class.plan))
            .filter(self.model_class.id == subscription_id)
            .with_for_update()
            .first()
        )
    
    def get_active_subscription(
        self,
        user_id: int,
        business_id: Optional[int] = None
    ) -> Optional[UserAISubscription]:
        """دریافت اشتراک فعال کاربر"""
        query = self.db.query(self.model_class).filter(
            and_(
                self.model_class.user_id == user_id,
                self.model_class.is_active == True,  # noqa: E712
                self.model_class.period_start <= datetime.utcnow()
            )
        )
        
        if business_id:
            query = query.filter(self.model_class.business_id == business_id)
        else:
            query = query.filter(self.model_class.business_id == None)  # noqa: E711
        
        # بررسی انقضا
        query = query.filter(
            (self.model_class.period_end == None) |  # noqa: E711
            (self.model_class.period_end >= datetime.utcnow())
        )
        
        return query.first()
    
    def get_user_subscriptions(
        self,
        user_id: int,
        business_id: Optional[int] = None
    ) -> List[UserAISubscription]:
        """دریافت تمام اشتراک‌های کاربر"""
        query = self.db.query(self.model_class).filter(
            self.model_class.user_id == user_id
        )
        
        if business_id:
            query = query.filter(self.model_class.business_id == business_id)
        else:
            query = query.filter(self.model_class.business_id == None)  # noqa: E711
        
        return query.order_by(self.model_class.created_at.desc()).all()
    
    def get_subscriptions_needing_reset(self) -> List[UserAISubscription]:
        """دریافت اشتراک‌هایی که باید reset شوند (ماهانه)"""
        # اشتراک‌هایی که period_start بیش از 30 روز گذشته است
        # برای reset ماهانه، از period_start استفاده می‌کنیم
        cutoff_date = datetime.utcnow() - timedelta(days=30)
        
        query = self.db.query(self.model_class).filter(
            and_(
                self.model_class.is_active == True,  # noqa: E712
                self.model_class.period_start < cutoff_date
            )
        )
        
        return query.all()
    
    def get_subscriptions_expiring_soon(self, days: int = 7) -> List[UserAISubscription]:
        """دریافت اشتراک‌هایی که در حال انقضا هستند"""
        from datetime import timedelta
        now = datetime.utcnow()
        future_date = now + timedelta(days=days)
        
        query = self.db.query(self.model_class).filter(
            and_(
                self.model_class.is_active == True,  # noqa: E712
                self.model_class.period_end != None,  # noqa: E711
                self.model_class.period_end >= now,
                self.model_class.period_end <= future_date
            )
        )
        
        return query.all()
    
    def get_expired_subscriptions(self) -> List[UserAISubscription]:
        """دریافت اشتراک‌های منقضی شده"""
        query = self.db.query(self.model_class).filter(
            and_(
                self.model_class.is_active == True,  # noqa: E712
                self.model_class.period_end != None,  # noqa: E711
                self.model_class.period_end < datetime.utcnow()
            )
        )
        
        return query.all()

    def get_subscriptions_due_for_auto_renew(self) -> List[UserAISubscription]:
        """اشتراک‌های فعال با تمدید خودکار که دوره‌شان تمام شده."""
        now = datetime.utcnow()
        query = self.db.query(self.model_class).filter(
            and_(
                self.model_class.is_active == True,  # noqa: E712
                self.model_class.auto_renew == True,  # noqa: E712
                self.model_class.period_end != None,  # noqa: E711
                self.model_class.period_end <= now,
            )
        )
        return query.all()

