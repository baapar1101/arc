"""
Repository برای مدیریت قالب‌های نوتیفیکیشن کسب‌وکارها
"""
from typing import Any, Dict, List, Optional, Tuple
from datetime import datetime, date
from decimal import Decimal

from sqlalchemy import and_, or_, desc, func, case
from sqlalchemy.orm import Session

from adapters.db.models.business_notification import (
    NotificationEventType,
    BusinessNotificationTemplate,
    NotificationModerationQueue,
    NotificationSendLog,
    NotificationDailyStat
)


class NotificationEventTypeRepository:
    """Repository برای مدیریت انواع رویدادها"""
    
    def __init__(self, db: Session):
        self.db = db
        self.model_class = NotificationEventType
    
    def get_by_id(self, event_type_id: int) -> Optional[NotificationEventType]:
        """دریافت نوع رویداد با ID"""
        return self.db.query(self.model_class).filter(
            self.model_class.id == event_type_id
        ).first()
    
    def get_by_code(self, code: str) -> Optional[NotificationEventType]:
        """دریافت نوع رویداد با کد"""
        return self.db.query(self.model_class).filter(
            self.model_class.code == code
        ).first()
    
    def list_all(
        self,
        category: Optional[str] = None,
        is_active: bool = True
    ) -> List[NotificationEventType]:
        """لیست تمام انواع رویدادها"""
        query = self.db.query(self.model_class)
        
        if is_active:
            query = query.filter(self.model_class.is_active == True)
        
        if category:
            query = query.filter(self.model_class.category == category)
        
        return query.order_by(self.model_class.category, self.model_class.name).all()
    
    def create(self, data: Dict[str, Any]) -> NotificationEventType:
        """ایجاد نوع رویداد جدید"""
        event_type = NotificationEventType(**data)
        self.db.add(event_type)
        self.db.flush()
        return event_type
    
    def update(self, event_type: NotificationEventType, data: Dict[str, Any]) -> NotificationEventType:
        """به‌روزرسانی نوع رویداد"""
        for key, value in data.items():
            if hasattr(event_type, key):
                setattr(event_type, key, value)
        event_type.updated_at = datetime.utcnow()
        self.db.flush()
        return event_type


class BusinessNotificationTemplateRepository:
    """Repository برای مدیریت قالب‌های نوتیفیکیشن"""
    
    def __init__(self, db: Session):
        self.db = db
        self.model_class = BusinessNotificationTemplate
    
    def get_by_id(
        self,
        template_id: int,
        business_id: Optional[int] = None
    ) -> Optional[BusinessNotificationTemplate]:
        """دریافت قالب با ID"""
        query = self.db.query(self.model_class).filter(
            self.model_class.id == template_id
        )
        
        if business_id:
            query = query.filter(self.model_class.business_id == business_id)
        
        return query.first()
    
    def get_by_code(
        self,
        business_id: int,
        code: str
    ) -> Optional[BusinessNotificationTemplate]:
        """دریافت قالب با کد"""
        return self.db.query(self.model_class).filter(
            and_(
                self.model_class.business_id == business_id,
                self.model_class.code == code
            )
        ).first()
    
    def find_active_template(
        self,
        business_id: int,
        event_type: str,
        channel: str
    ) -> Optional[BusinessNotificationTemplate]:
        """
        یافتن قالب فعال برای یک رویداد و کانال خاص
        
        فقط قالب‌های تایید شده و فعال برگردانده می‌شود
        """
        return self.db.query(self.model_class).filter(
            and_(
                self.model_class.business_id == business_id,
                self.model_class.event_type == event_type,
                self.model_class.channel == channel,
                self.model_class.is_active == True,
                self.model_class.status == 'approved'
            )
        ).first()
    
    def list_by_business(
        self,
        business_id: int,
        filters: Optional[Dict[str, Any]] = None,
        offset: int = 0,
        limit: int = 50
    ) -> Tuple[List[BusinessNotificationTemplate], int]:
        """لیست قالب‌های یک کسب‌وکار"""
        query = self.db.query(self.model_class).filter(
            self.model_class.business_id == business_id
        )
        
        if filters:
            if filters.get("status"):
                query = query.filter(self.model_class.status == filters["status"])
            
            if filters.get("channel"):
                query = query.filter(self.model_class.channel == filters["channel"])
            
            if filters.get("event_type"):
                query = query.filter(self.model_class.event_type == filters["event_type"])
            
            if filters.get("is_active") is not None:
                query = query.filter(self.model_class.is_active == filters["is_active"])
            
            if filters.get("search"):
                search_term = f"%{filters['search']}%"
                query = query.filter(
                    or_(
                        self.model_class.name.like(search_term),
                        self.model_class.code.like(search_term),
                        self.model_class.description.like(search_term)
                    )
                )
        
        total = query.count()
        
        query = query.order_by(desc(self.model_class.created_at))
        query = query.offset(offset).limit(limit)
        
        return query.all(), total
    
    def create(self, data: Dict[str, Any]) -> BusinessNotificationTemplate:
        """ایجاد قالب جدید"""
        template = BusinessNotificationTemplate(**data)
        self.db.add(template)
        self.db.flush()
        return template
    
    def update(
        self,
        template: BusinessNotificationTemplate,
        data: Dict[str, Any]
    ) -> BusinessNotificationTemplate:
        """به‌روزرسانی قالب"""
        for key, value in data.items():
            if hasattr(template, key):
                setattr(template, key, value)
        template.updated_at = datetime.utcnow()
        self.db.flush()
        return template
    
    def delete(self, template: BusinessNotificationTemplate) -> None:
        """حذف قالب"""
        self.db.delete(template)
        self.db.flush()


class NotificationModerationQueueRepository:
    """Repository برای مدیریت صف بررسی قالب‌ها"""
    
    def __init__(self, db: Session):
        self.db = db
        self.model_class = NotificationModerationQueue
    
    def get_by_id(self, queue_id: int) -> Optional[NotificationModerationQueue]:
        """دریافت آیتم صف با ID"""
        return self.db.query(self.model_class).filter(
            self.model_class.id == queue_id
        ).first()
    
    def get_by_template(self, template_id: int) -> Optional[NotificationModerationQueue]:
        """دریافت آیتم صف برای یک قالب"""
        return self.db.query(self.model_class).filter(
            and_(
                self.model_class.template_id == template_id,
                self.model_class.status.in_(['pending', 'ai_reviewing', 'ai_reviewed', 'admin_reviewing'])
            )
        ).first()
    
    def get_pending(
        self,
        status: Optional[str] = 'pending',
        limit: int = 10
    ) -> List[NotificationModerationQueue]:
        """دریافت آیتم‌های در انتظار بررسی"""
        query = self.db.query(self.model_class)
        
        if status:
            query = query.filter(self.model_class.status == status)
        
        return query.order_by(
            desc(self.model_class.priority),
            self.model_class.created_at
        ).limit(limit).all()
    
    def list_for_admin(
        self,
        filters: Optional[Dict[str, Any]] = None,
        offset: int = 0,
        limit: int = 50
    ) -> Tuple[List[NotificationModerationQueue], int]:
        """لیست برای پنل مدیر"""
        query = self.db.query(self.model_class)
        
        if filters:
            if filters.get("status"):
                query = query.filter(self.model_class.status == filters["status"])
            
            if filters.get("ai_decision"):
                query = query.filter(self.model_class.ai_decision == filters["ai_decision"])
            
            if filters.get("business_id"):
                query = query.filter(self.model_class.business_id == filters["business_id"])
        
        total = query.count()
        
        # اولویت با آیتم‌های قابل اقدام (غیر completed) تا همهٔ قالب‌های در انتظار دیده شوند
        query = query.order_by(
            case((self.model_class.status == 'completed', 1), else_=0),
            desc(self.model_class.priority),
            self.model_class.created_at
        )
        query = query.offset(offset).limit(limit)
        
        return query.all(), total
    
    def create(self, data: Dict[str, Any]) -> NotificationModerationQueue:
        """ایجاد آیتم صف جدید"""
        queue_item = NotificationModerationQueue(**data)
        self.db.add(queue_item)
        self.db.flush()
        return queue_item
    
    def update(
        self,
        queue_item: NotificationModerationQueue,
        data: Dict[str, Any]
    ) -> NotificationModerationQueue:
        """به‌روزرسانی آیتم صف"""
        for key, value in data.items():
            if hasattr(queue_item, key):
                setattr(queue_item, key, value)
        self.db.flush()
        return queue_item


class NotificationSendLogRepository:
    """Repository برای مدیریت لاگ‌های ارسال"""
    
    def __init__(self, db: Session):
        self.db = db
        self.model_class = NotificationSendLog
    
    def create(self, data: Dict[str, Any]) -> NotificationSendLog:
        """ثبت لاگ ارسال جدید"""
        log = NotificationSendLog(**data)
        self.db.add(log)
        self.db.flush()
        return log
    
    def update(self, log: NotificationSendLog, data: Dict[str, Any]) -> NotificationSendLog:
        """به‌روزرسانی لاگ"""
        for key, value in data.items():
            if hasattr(log, key):
                setattr(log, key, value)
        self.db.flush()
        return log
    
    def list_by_business(
        self,
        business_id: int,
        filters: Optional[Dict[str, Any]] = None,
        offset: int = 0,
        limit: int = 50
    ) -> Tuple[List[NotificationSendLog], int]:
        """لیست لاگ‌های یک کسب‌وکار"""
        query = self.db.query(self.model_class).filter(
            self.model_class.business_id == business_id
        )
        
        if filters:
            if filters.get("channel"):
                query = query.filter(self.model_class.channel == filters["channel"])
            
            if filters.get("status"):
                query = query.filter(self.model_class.status == filters["status"])
            
            if filters.get("template_id"):
                query = query.filter(self.model_class.template_id == filters["template_id"])
            
            if filters.get("from_date"):
                query = query.filter(self.model_class.created_at >= filters["from_date"])
            
            if filters.get("to_date"):
                query = query.filter(self.model_class.created_at <= filters["to_date"])
        
        total = query.count()
        
        query = query.order_by(desc(self.model_class.created_at))
        query = query.offset(offset).limit(limit)
        
        return query.all(), total
    
    def get_daily_count(
        self,
        business_id: int,
        template_id: int,
        channel: str,
        target_date: date
    ) -> int:
        """دریافت تعداد ارسال‌های امروز برای یک قالب"""
        return self.db.query(func.count(self.model_class.id)).filter(
            and_(
                self.model_class.business_id == business_id,
                self.model_class.template_id == template_id,
                self.model_class.channel == channel,
                func.date(self.model_class.created_at) == target_date,
                self.model_class.status == 'sent'
            )
        ).scalar() or 0


class NotificationDailyStatRepository:
    """Repository برای مدیریت آمار روزانه"""
    
    def __init__(self, db: Session):
        self.db = db
        self.model_class = NotificationDailyStat
    
    def get_or_create(
        self,
        business_id: int,
        template_id: Optional[int],
        target_date: date,
        channel: str
    ) -> NotificationDailyStat:
        """دریافت یا ایجاد آمار روزانه"""
        stat = self.db.query(self.model_class).filter(
            and_(
                self.model_class.business_id == business_id,
                self.model_class.template_id == template_id,
                self.model_class.date == target_date,
                self.model_class.channel == channel
            )
        ).first()
        
        if not stat:
            stat = NotificationDailyStat(
                business_id=business_id,
                template_id=template_id,
                date=target_date,
                channel=channel,
                total_sent=0,
                total_failed=0,
                total_cost=Decimal('0')
            )
            self.db.add(stat)
            self.db.flush()
        
        return stat
    
    def increment_sent(
        self,
        business_id: int,
        template_id: Optional[int],
        target_date: date,
        channel: str,
        cost: Decimal = Decimal('0')
    ) -> None:
        """افزایش شمارنده ارسال موفق"""
        stat = self.get_or_create(business_id, template_id, target_date, channel)
        stat.total_sent += 1
        stat.total_cost += cost
        stat.updated_at = datetime.utcnow()
        self.db.flush()
    
    def increment_failed(
        self,
        business_id: int,
        template_id: Optional[int],
        target_date: date,
        channel: str
    ) -> None:
        """افزایش شمارنده ارسال ناموفق"""
        stat = self.get_or_create(business_id, template_id, target_date, channel)
        stat.total_failed += 1
        stat.updated_at = datetime.utcnow()
        self.db.flush()
    
    def get_stats(
        self,
        business_id: int,
        from_date: date,
        to_date: date,
        template_id: Optional[int] = None
    ) -> List[NotificationDailyStat]:
        """دریافت آمار یک بازه زمانی"""
        query = self.db.query(self.model_class).filter(
            and_(
                self.model_class.business_id == business_id,
                self.model_class.date >= from_date,
                self.model_class.date <= to_date
            )
        )
        
        if template_id:
            query = query.filter(self.model_class.template_id == template_id)
        
        return query.order_by(self.model_class.date).all()


