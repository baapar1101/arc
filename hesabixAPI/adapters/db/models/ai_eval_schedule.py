from __future__ import annotations

from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class AIEvalSchedule(Base):
    """تنظیمات زمان‌بندی ارزیابی خودکار (ردیف singleton با id=1)."""

    __tablename__ = "ai_eval_schedule"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    cron_expression: Mapped[str] = mapped_column(String(64), nullable=False, default="0 3 * * *")
    timezone: Mapped[str] = mapped_column(String(64), nullable=False, default="Asia/Tehran")
    business_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("businesses.id", ondelete="SET NULL"), nullable=True
    )
    min_pass_rate: Mapped[int] = mapped_column(Integer, nullable=False, default=70)
    last_run_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("ai_eval_runs.id", ondelete="SET NULL"), nullable=True
    )
    last_run_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    last_pass_rate: Mapped[int | None] = mapped_column(Integer, nullable=True)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
    )
