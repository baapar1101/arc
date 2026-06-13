from __future__ import annotations

from datetime import datetime
from sqlalchemy import String, Integer, DateTime, Boolean, Enum as SQLEnum, ForeignKey, Numeric
from sqlalchemy.orm import Mapped, mapped_column, relationship
from adapters.db.session import Base
import enum


class SubscriptionType(str, enum.Enum):
    FREE = "free"
    SUBSCRIPTION = "subscription"
    PAY_AS_GO = "pay_as_go"


class UserAISubscription(Base):
    __tablename__ = "user_ai_subscriptions"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    
    # کاربر و کسب‌وکار
    user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    business_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=True, index=True)
    
    # پلن
    plan_id: Mapped[int] = mapped_column(Integer, ForeignKey("ai_plans.id", ondelete="RESTRICT"), nullable=False, index=True)
    subscription_type: Mapped[str] = mapped_column(
        String(50),
        nullable=False
    )
    
    # استفاده
    tokens_used: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    tokens_limit: Mapped[int | None] = mapped_column(Integer, nullable=True)  # برای subscription
    
    # دوره زمانی
    period_start: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    period_end: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)  # برای subscription
    expires_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)  # تاریخ انقضای اشتراک
    
    # تنظیمات
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    auto_renew: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)  # برای subscription
    last_reset_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)  # آخرین زمان reset سهمیه
    
    # مدل ترجیحی کاربر (کد از ai_models.code)
    preferred_model_code: Mapped[str | None] = mapped_column(String(80), nullable=True, index=True)

    # حداقل موجودی کیف پول (برای pay_as_go)
    wallet_balance_required: Mapped[float | None] = mapped_column(Numeric(18, 2), nullable=True)
    
    # زمان‌بندی
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
    
    # Relationships
    user = relationship("User", backref="ai_subscriptions")
    business = relationship("Business", backref="ai_subscriptions")
    plan = relationship("AIPlan", back_populates="subscriptions")
    usage_logs = relationship("AIUsageLog", back_populates="subscription")
    invoices = relationship("AIInvoice", back_populates="subscription")

