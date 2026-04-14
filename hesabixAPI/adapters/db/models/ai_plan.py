from __future__ import annotations

from datetime import datetime
from sqlalchemy import String, Integer, DateTime, Text, Boolean, Enum as SQLEnum, ForeignKey, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship
from adapters.db.session import Base
import enum


class AIPlanType(str, enum.Enum):
    FREE = "free"
    SUBSCRIPTION = "subscription"
    PAY_AS_GO = "pay_as_go"
    HYBRID = "hybrid"


class AIPlan(Base):
    __tablename__ = "ai_plans"
    __table_args__ = (
        UniqueConstraint('code', name='uq_ai_plans_code'),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    
    # اطلاعات پایه
    code: Mapped[str] = mapped_column(String(50), nullable=False, unique=True, index=True)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    
    # نوع پلن
    plan_type: Mapped[str] = mapped_column(
        String(50),
        nullable=False
    )
    
    # تنظیمات قیمت‌گذاری (JSON)
    pricing_config: Mapped[str | None] = mapped_column(Text, nullable=True)  # JSON
    
    # محدودیت‌های استفاده (JSON)
    usage_limits: Mapped[str | None] = mapped_column(Text, nullable=True)  # JSON
    
    # امکانات (JSON)
    features: Mapped[str | None] = mapped_column(Text, nullable=True)  # JSON
    
    # محدودیت‌های توکن
    tokens_limit: Mapped[int | None] = mapped_column(Integer, nullable=True)
    monthly_tokens_limit: Mapped[int | None] = mapped_column(Integer, nullable=True)
    
    # وضعیت
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    auto_renew: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    
    # زمان‌بندی
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
    
    # Relationships
    subscriptions = relationship("UserAISubscription", back_populates="plan", cascade="all, delete-orphan")
    invoices = relationship("AIInvoice", back_populates="plan")

