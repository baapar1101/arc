from __future__ import annotations

from datetime import datetime
from sqlalchemy import String, Integer, DateTime, ForeignKey, Text, Boolean, Enum as SQLEnum
from sqlalchemy.orm import Mapped, mapped_column, relationship
from adapters.db.session import Base
import enum


class PromptRole(str, enum.Enum):
    OPERATOR = "operator"
    USER = "user"
    ADMIN = "admin"


class PromptType(str, enum.Enum):
    SYSTEM = "system"
    USER = "user"


class AIPrompt(Base):
    __tablename__ = "ai_prompts"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    
    # نوع prompt
    role: Mapped[str] = mapped_column(
        String(50),
        nullable=False,
        index=True
    )
    prompt_type: Mapped[str] = mapped_column(
        String(50),
        nullable=False
    )
    
    # محتوا
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    
    # شخصی‌سازی
    user_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=True, index=True)
    is_default: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    
    # زمان‌بندی
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
    
    # Relationships
    user = relationship("User", backref="ai_prompts")

