from __future__ import annotations

from datetime import datetime

from sqlalchemy import DateTime, Integer, ForeignKey, String, BigInteger
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class SupportAttachment(Base):
    """پیوست‌های تیکت پشتیبانی"""
    __tablename__ = "support_attachments"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    ticket_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("support_tickets.id", ondelete="CASCADE"), nullable=False, index=True
    )
    message_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("support_messages.id", ondelete="SET NULL"), nullable=True, index=True
    )
    file_storage_id: Mapped[str] = mapped_column(String(36), nullable=False, index=True)
    original_name: Mapped[str] = mapped_column(String(512), nullable=False)
    mime_type: Mapped[str | None] = mapped_column(String(128), nullable=True)
    size_bytes: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)
    uploaded_by: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)

    ticket = relationship("Ticket", back_populates="attachments")
    message = relationship("Message", back_populates="attachments")
