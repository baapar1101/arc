from __future__ import annotations

from datetime import datetime
from sqlalchemy import String, Integer, DateTime, ForeignKey, Text, Enum as SQLEnum
from sqlalchemy.orm import Mapped, mapped_column, relationship
from adapters.db.session import Base
import enum


class MessageRole(str, enum.Enum):
    USER = "user"
    ASSISTANT = "assistant"
    SYSTEM = "system"
    FUNCTION = "function"


class AIChatMessage(Base):
    __tablename__ = "ai_chat_messages"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    
    # جلسه چت
    session_id: Mapped[int] = mapped_column(Integer, ForeignKey("ai_chat_sessions.id", ondelete="CASCADE"), nullable=False, index=True)
    
    # نقش پیام
    role: Mapped[str] = mapped_column(
        String(50),
        nullable=False
    )
    
    # محتوا
    content: Mapped[str] = mapped_column(Text, nullable=False)
    
    # Function calling (JSON)
    function_calls: Mapped[str | None] = mapped_column(Text, nullable=True)  # JSON
    function_results: Mapped[str | None] = mapped_column(Text, nullable=True)  # JSON
    
    # استفاده از توکن
    tokens_used: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    
    # زمان‌بندی
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False, index=True)
    
    # Relationships
    session = relationship("AIChatSession", back_populates="messages")

