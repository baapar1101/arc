from __future__ import annotations

from datetime import datetime
from sqlalchemy import String, Integer, DateTime, Text, Numeric, Boolean, Enum as SQLEnum
from sqlalchemy.orm import Mapped, mapped_column
from adapters.db.session import Base
import enum


class AIProvider(str, enum.Enum):
    OPENAI = "openai"
    ANTHROPIC = "anthropic"
    LOCAL = "local"
    CUSTOM = "custom"


class AIConfig(Base):
    __tablename__ = "ai_configs"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    
    # تنظیمات Provider
    # استفاده از String به جای Enum برای سازگاری با مقادیر موجود در دیتابیس
    provider: Mapped[str] = mapped_column(
        String(50),
        nullable=False,
        default=AIProvider.OPENAI.value
    )
    model_name: Mapped[str] = mapped_column(String(100), nullable=False, default="gpt-4")
    api_base_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    api_key: Mapped[str | None] = mapped_column(Text, nullable=True)  # رمزگذاری شده
    
    # تنظیمات Model
    max_tokens: Mapped[int] = mapped_column(Integer, nullable=False, default=4000)
    temperature: Mapped[float] = mapped_column(Numeric(3, 2), nullable=False, default=0.7)
    # اگر False باشد، tools به provider ارسال نمی‌شود (برای vLLM بدون --enable-auto-tool-choice)
    function_calling_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    
    # وضعیت
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    
    # زمان‌بندی
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

