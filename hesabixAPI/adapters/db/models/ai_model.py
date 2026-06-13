from __future__ import annotations

from datetime import datetime

from sqlalchemy import String, Integer, DateTime, Text, Numeric, Boolean, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class AIModel(Base):
    """کاتالوگ مدل‌های هوش مصنوعی قابل ارائه به کاربران."""

    __tablename__ = "ai_models"
    __table_args__ = (
        UniqueConstraint("code", name="uq_ai_models_code"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)

    code: Mapped[str] = mapped_column(String(80), nullable=False, unique=True, index=True)
    display_name: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)

    provider: Mapped[str] = mapped_column(String(50), nullable=False, default="openai")
    model_id: Mapped[str] = mapped_column(String(120), nullable=False)

    tier: Mapped[str | None] = mapped_column(String(50), nullable=True)

    supports_tools: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    max_tokens_default: Mapped[int] = mapped_column(Integer, nullable=False, default=4000)

    reference_input_cost_per_1k: Mapped[float | None] = mapped_column(Numeric(18, 4), nullable=True)
    reference_output_cost_per_1k: Mapped[float | None] = mapped_column(Numeric(18, 4), nullable=True)

    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)

    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
    )
