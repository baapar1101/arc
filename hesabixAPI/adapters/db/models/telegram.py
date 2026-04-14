from __future__ import annotations

from datetime import datetime

from sqlalchemy import Integer, String, DateTime, ForeignKey, Index, BigInteger, Boolean
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class TelegramLinkToken(Base):
	__tablename__ = "telegram_link_tokens"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), index=True)
	token: Mapped[str] = mapped_column(String(128), unique=True, index=True)
	expires_at: Mapped[datetime] = mapped_column(DateTime, index=True)
	used_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	created_ip: Mapped[str | None] = mapped_column(String(64), nullable=True)
	user_agent: Mapped[str | None] = mapped_column(String(255), nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)

	__table_args__ = (
		Index("ix_telegram_link_validity", "expires_at", "used_at"),
	)


class TelegramAISession(Base):
	"""جلسه چت AI از طریق تلگرام"""
	__tablename__ = "telegram_ai_sessions"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	
	# کاربر و چت تلگرام
	user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
	chat_id: Mapped[int] = mapped_column(BigInteger, nullable=False, index=True)
	
	# جلسه چت AI و کسب‌وکار
	session_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("ai_chat_sessions.id", ondelete="SET NULL"), nullable=True, index=True)
	business_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=True, index=True)
	
	# وضعیت
	is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
	
	# زمان‌بندی
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
	
	# Relationships
	user = relationship("User", backref="telegram_ai_sessions")
	session = relationship("AIChatSession", backref="telegram_sessions")
	business = relationship("Business", backref="telegram_ai_sessions")
	
	__table_args__ = (
		Index("ix_telegram_ai_sessions_user_chat_active", "user_id", "chat_id", "is_active"),
	)


