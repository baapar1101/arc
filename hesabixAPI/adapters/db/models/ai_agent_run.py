from __future__ import annotations

from datetime import datetime
from typing import Optional

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class AIAgentRunStatus:
    RUNNING = "running"
    INTERRUPTED = "interrupted"
    BUDGET_EXHAUSTED = "budget_exhausted"
    AWAITING_APPROVAL = "awaiting_approval"
    COMPLETED = "completed"
    ERROR = "error"

    ALL = frozenset(
        {
            RUNNING,
            INTERRUPTED,
            BUDGET_EXHAUSTED,
            AWAITING_APPROVAL,
            COMPLETED,
            ERROR,
        }
    )
    RESUMABLE = frozenset({INTERRUPTED, BUDGET_EXHAUSTED})


class AIAgentRun(Base):
    """checkpoint پایدار یک اجرای agent برای ادامه پس از قطع/سقف بودجه."""

    __tablename__ = "ai_agent_runs"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    run_id: Mapped[str] = mapped_column(String(16), nullable=False, unique=True, index=True)
    session_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("ai_chat_sessions.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    user_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    business_id: Mapped[Optional[int]] = mapped_column(
        Integer,
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=True,
        index=True,
    )
    origin_message_id: Mapped[Optional[int]] = mapped_column(
        Integer,
        ForeignKey("ai_chat_messages.id", ondelete="SET NULL"),
        nullable=True,
    )
    status: Mapped[str] = mapped_column(
        String(32),
        nullable=False,
        default=AIAgentRunStatus.RUNNING,
        server_default=AIAgentRunStatus.RUNNING,
    )
    phase: Mapped[str] = mapped_column(String(32), nullable=False, default="gather_context")
    iteration: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    needs_tools: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    stop_reason: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    tools_called_json: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    budget_json: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    last_event_id: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )
    extra_json: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
        nullable=False,
    )

    session = relationship("AIChatSession", back_populates="agent_runs")
