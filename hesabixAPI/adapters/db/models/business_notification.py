"""
مدل‌های دیتابیس برای سیستم نوتیفیکیشن جامع کسب‌وکارها
"""
from __future__ import annotations

from datetime import datetime, date
from typing import Optional
from decimal import Decimal

from sqlalchemy import (
    String, Integer, DateTime, Boolean, Text, Numeric, Date,
    ForeignKey, UniqueConstraint, Index, Enum as SAEnum, BigInteger
)
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.mysql import JSON

from adapters.db.session import Base


class NotificationEventType(Base):
    """
    تعریف انواع رویدادها و متغیرهای قابل استفاده در قالب‌ها
    
    مثال:
    - invoice.created: ثبت فاکتور جدید
    - repair_shop.received: دریافت کالا در تعمیرگاه
    - payment.received: دریافت پرداخت
    """
    __tablename__ = "notification_event_types"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    
    # شناسایی
    code: Mapped[str] = mapped_column(String(100), unique=True, nullable=False, index=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    category: Mapped[Optional[str]] = mapped_column(String(50), nullable=True, index=True)
    
    # متغیرهای قابل استفاده
    # مثال: [{"key": "invoice_number", "type": "string", "description": "شماره فاکتور"}, ...]
    available_variables: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)
    
    # قالب پیش‌فرض پیشنهادی
    default_sms_template: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    default_email_template: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    default_email_subject: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)
    
    # وضعیت
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    requires_approval: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, 
        default=datetime.utcnow, 
        onupdate=datetime.utcnow, 
        nullable=False
    )


class BusinessNotificationTemplate(Base):
    """
    قالب‌های نوتیفیکیشن هر کسب‌وکار
    
    هر کسب‌وکار می‌تواند برای رویدادهای مختلف، قالب‌های سفارشی تعریف کند.
    قالب‌ها قبل از فعال شدن، باید تایید شوند (توسط AI یا مدیر سیستم)
    """
    __tablename__ = "business_notification_templates"
    __table_args__ = (
        UniqueConstraint("business_id", "code", name="uk_business_template_code"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    
    # شناسایی قالب
    code: Mapped[str] = mapped_column(String(100), nullable=False)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    
    # نوع رویداد و کانال
    event_type: Mapped[str] = mapped_column(String(100), nullable=False, index=True)
    channel: Mapped[str] = mapped_column(
        SAEnum('sms', 'email', name='notification_channel'),
        nullable=False
    )
    recipient_type: Mapped[str] = mapped_column(
        SAEnum('customer', 'supplier', 'employee', name='recipient_type'),
        nullable=False,
        default='customer'
    )
    
    # محتوای قالب
    subject: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    
    # متغیرهای قابل استفاده (کپی شده از event_type برای راحتی)
    available_variables: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)
    
    # وضعیت و تایید
    status: Mapped[str] = mapped_column(
        SAEnum('draft', 'pending_approval', 'approved', 'rejected', 'suspended', name='template_status'),
        nullable=False,
        default='draft',
        index=True
    )
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, index=True)
    
    # اطلاعات تایید
    approval_status: Mapped[str] = mapped_column(
        SAEnum('pending', 'ai_approved', 'admin_approved', 'rejected', name='approval_status'),
        nullable=False,
        default='pending',
        index=True
    )
    approved_by_ai: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    approved_by_admin_id: Mapped[Optional[int]] = mapped_column(
        Integer,
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True
    )
    ai_confidence_score: Mapped[Optional[Decimal]] = mapped_column(Numeric(5, 2), nullable=True)
    ai_review_notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    admin_review_notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    approved_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    rejected_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    rejection_reason: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    
    # محدودیت‌ها
    daily_limit: Mapped[int] = mapped_column(Integer, nullable=False, default=100)
    is_automated: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    
    # متادیتا
    created_by_user_id: Mapped[int] = mapped_column(Integer, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
        nullable=False
    )
    
    # Relationships
    business: Mapped["Business"] = relationship("Business", foreign_keys=[business_id])
    approved_by_admin: Mapped[Optional["User"]] = relationship("User", foreign_keys=[approved_by_admin_id])


class NotificationModerationQueue(Base):
    """
    صف بررسی و تایید قالب‌های نوتیفیکیشن
    
    هر قالب جدید یا ویرایش شده، وارد این صف می‌شود تا توسط AI و/یا مدیر بررسی شود
    """
    __tablename__ = "notification_moderation_queue"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    
    template_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("business_notification_templates.id", ondelete="CASCADE"),
        nullable=False
    )
    business_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    
    # وضعیت بررسی
    status: Mapped[str] = mapped_column(
        SAEnum('pending', 'ai_reviewing', 'ai_reviewed', 'admin_reviewing', 'completed', name='moderation_status'),
        nullable=False,
        default='pending',
        index=True
    )
    
    # نتیجه بررسی AI
    ai_reviewed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    ai_decision: Mapped[Optional[str]] = mapped_column(
        SAEnum('approve', 'reject', 'review_required', name='ai_decision'),
        nullable=True
    )
    ai_confidence: Mapped[Optional[Decimal]] = mapped_column(Numeric(5, 2), nullable=True)
    ai_flags: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)
    ai_suggestions: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    
    # بررسی مدیر
    admin_reviewed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    reviewed_by_admin_id: Mapped[Optional[int]] = mapped_column(
        Integer,
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True
    )
    admin_decision: Mapped[Optional[str]] = mapped_column(
        SAEnum('approve', 'reject', name='admin_decision'),
        nullable=True
    )
    admin_notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    
    # اولویت
    priority: Mapped[int] = mapped_column(Integer, nullable=False, default=0, index=True)
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    completed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    
    # Relationships
    template: Mapped["BusinessNotificationTemplate"] = relationship(
        "BusinessNotificationTemplate",
        foreign_keys=[template_id]
    )
    business: Mapped["Business"] = relationship("Business", foreign_keys=[business_id])
    reviewed_by_admin: Mapped[Optional["User"]] = relationship("User", foreign_keys=[reviewed_by_admin_id])


class NotificationSendLog(Base):
    """
    لاگ کامل ارسال نوتیفیکیشن‌ها
    
    تمام ارسال‌های SMS و Email در این جدول ثبت می‌شود
    """
    __tablename__ = "notification_send_logs"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    
    # شناسایی
    business_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    template_id: Mapped[Optional[int]] = mapped_column(
        Integer,
        ForeignKey("business_notification_templates.id", ondelete="SET NULL"),
        nullable=True,
        index=True
    )
    
    # گیرنده
    recipient_type: Mapped[str] = mapped_column(
        SAEnum('person', 'user', name='recipient_type_enum'),
        nullable=False
    )
    recipient_id: Mapped[int] = mapped_column(Integer, nullable=False, index=True)
    recipient_identifier: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    
    # محتوا
    channel: Mapped[str] = mapped_column(
        SAEnum('sms', 'email', name='send_channel'),
        nullable=False
    )
    subject: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    
    # Context استفاده شده
    context_data: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)
    
    # وضعیت ارسال
    status: Mapped[str] = mapped_column(
        SAEnum('pending', 'sent', 'failed', 'rejected', name='send_status'),
        nullable=False,
        default='pending',
        index=True
    )
    sent_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    failed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    failure_reason: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    
    # اطلاعات ارسال
    provider_name: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    provider_message_id: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)
    cost: Mapped[Optional[Decimal]] = mapped_column(Numeric(10, 2), nullable=True)
    
    # متادیتا
    triggered_by_user_id: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    event_type: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    
    # Relationships
    business: Mapped["Business"] = relationship("Business", foreign_keys=[business_id])
    template: Mapped[Optional["BusinessNotificationTemplate"]] = relationship(
        "BusinessNotificationTemplate",
        foreign_keys=[template_id]
    )


class NotificationDailyStat(Base):
    """
    آمار روزانه ارسال نوتیفیکیشن‌ها
    
    برای Rate Limiting و گزارش‌گیری استفاده می‌شود
    """
    __tablename__ = "notification_daily_stats"
    __table_args__ = (
        UniqueConstraint("business_id", "template_id", "date", "channel", name="uk_daily_stats"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    
    business_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    template_id: Mapped[Optional[int]] = mapped_column(
        Integer,
        ForeignKey("business_notification_templates.id", ondelete="SET NULL"),
        nullable=True
    )
    date: Mapped[date] = mapped_column(Date, nullable=False)
    channel: Mapped[str] = mapped_column(
        SAEnum('sms', 'email', name='stats_channel'),
        nullable=False
    )
    
    # آمار
    total_sent: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    total_failed: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    total_cost: Mapped[Decimal] = mapped_column(Numeric(10, 2), nullable=False, default=0)
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
        nullable=False
    )
    
    # Relationships
    business: Mapped["Business"] = relationship("Business", foreign_keys=[business_id])
    template: Mapped[Optional["BusinessNotificationTemplate"]] = relationship(
        "BusinessNotificationTemplate",
        foreign_keys=[template_id]
    )


