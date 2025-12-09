from __future__ import annotations

from datetime import datetime

from sqlalchemy import String, DateTime, Integer, ForeignKey, Text, Boolean
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class Ticket(Base):
    """تیکت‌های پشتیبانی"""
    __tablename__ = "support_tickets"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    title: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    
    # Foreign Keys
    user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    category_id: Mapped[int] = mapped_column(Integer, ForeignKey("support_categories.id", ondelete="RESTRICT"), nullable=False, index=True)
    priority_id: Mapped[int] = mapped_column(Integer, ForeignKey("support_priorities.id", ondelete="RESTRICT"), nullable=False, index=True)
    status_id: Mapped[int] = mapped_column(Integer, ForeignKey("support_statuses.id", ondelete="RESTRICT"), nullable=False, index=True)
    assigned_operator_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)
    
    # Additional fields
    is_internal: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)  # آیا تیکت داخلی است؟
    closed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    
    # Timestamps
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
    
    # Relationships
    user = relationship("User", foreign_keys=[user_id], back_populates="tickets")
    assigned_operator = relationship("User", foreign_keys=[assigned_operator_id])
    category = relationship("Category", back_populates="tickets")
    priority = relationship("Priority", back_populates="tickets")
    status = relationship("Status", back_populates="tickets")
    messages = relationship("Message", back_populates="ticket", cascade="all, delete-orphan", order_by="Message.created_at")
