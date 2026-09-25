from __future__ import annotations

from datetime import datetime
from typing import Optional

from sqlalchemy import DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class AISubagentRunStatus:
    RUNNING = "running"
    COMPLETED = "completed"
    CANCELLED = "cancelled"
    FAILED = "failed"
    INTERRUPTED = "interrupted"

    ALL = frozenset(
        {
            RUNNING,
            COMPLETED,
            CANCELLED,
            FAILED,
            INTERRUPTED,
        }
    )


class AISubagentRun(Base):
    """وضعیت پایدار زیر-ایجنت برای بازیابی پنل پس از رفرش/ری‌استارت."""

    __tablename__ = "ai_subagent_runs"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    subagent_id: Mapped[str] = mapped_column(
        String(16), nullable=False, unique=True, index=True
    )
    session_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("ai_chat_sessions.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    business_id: Mapped[Optional[int]] = mapped_column(
        Integer,
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=True,
        index=True,
    )
    goal: Mapped[str] = mapped_column(Text, nullable=False, default="")
    status: Mapped[str] = mapped_column(
        String(32),
        nullable=False,
        default=AISubagentRunStatus.RUNNING,
        server_default=AISubagentRunStatus.RUNNING,
    )
    error: Mapped[Optional[str]] = mapped_column(String(128), nullable=True)
    result_json: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
        nullable=False,
    )
