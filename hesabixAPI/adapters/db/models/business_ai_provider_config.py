from __future__ import annotations

from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class BusinessAIProviderConfig(Base):
    """تنظیمات ارائه‌دهنده AI اختصاصی هر کسب‌وکار (پلن BYOK)."""

    __tablename__ = "business_ai_provider_configs"
    __table_args__ = (
        UniqueConstraint("business_id", name="uq_business_ai_provider_configs_business"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    provider: Mapped[str] = mapped_column(String(50), nullable=False, default="openai")
    display_name: Mapped[str | None] = mapped_column(String(120), nullable=True)
    api_base_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    api_key: Mapped[str | None] = mapped_column(Text, nullable=True)
    models_json: Mapped[str | None] = mapped_column(Text, nullable=True)  # JSON list
    default_model: Mapped[str | None] = mapped_column(String(120), nullable=True)
    function_calling_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    last_tested_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    last_test_ok: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    last_test_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
    )
