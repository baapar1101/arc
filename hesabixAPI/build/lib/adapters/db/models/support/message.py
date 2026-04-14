from __future__ import annotations

from datetime import datetime
from enum import Enum

from sqlalchemy import String, DateTime, Integer, ForeignKey, Text, Boolean, Enum as SQLEnum
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class SenderType(str, Enum):
    """نوع فرستنده پیام"""
    USER = "user"
    OPERATOR = "operator"
    SYSTEM = "system"


class Message(Base):
    """پیام‌های تیکت‌های پشتیبانی"""
    __tablename__ = "support_messages"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    ticket_id: Mapped[int] = mapped_column(Integer, ForeignKey("support_tickets.id", ondelete="CASCADE"), nullable=False, index=True)
    sender_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    sender_type: Mapped[SenderType] = mapped_column(SQLEnum(SenderType), nullable=False, index=True)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    is_internal: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)  # آیا پیام داخلی است؟
    
    # Timestamps
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    
    # Relationships
    ticket = relationship("Ticket", back_populates="messages")
    sender = relationship("User")
