# noqa: D100
"""نشست اپراتور در پیام‌رسان (تلگرام/بله) برای فلوهایی مثل چت وب CRM."""
from __future__ import annotations

from datetime import datetime
from typing import Any

from sqlalchemy import DateTime, ForeignKey, Integer, JSON, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class MessengerOperatorSession(Base):
	"""
	یک نشست فعال به‌ازای هر (کاربر، پلتفرم).
	flow_key برای توسعهٔ فلوهای بعدی (مثلاً تیکت پشتیبانی)؛ پیش‌فرض crm_web_chat.
	"""

	__tablename__ = "messenger_operator_sessions"
	__table_args__ = (UniqueConstraint("user_id", "platform", name="uq_messenger_operator_session_user_platform"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
	platform: Mapped[str] = mapped_column(String(16), nullable=False, index=True)
	flow_key: Mapped[str] = mapped_column(String(64), nullable=False, default="crm_web_chat", server_default="crm_web_chat")
	mode: Mapped[str] = mapped_column(String(32), nullable=False, default="idle", server_default="idle")
	business_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="SET NULL"), nullable=True, index=True)
	active_conversation_id: Mapped[int | None] = mapped_column(
		Integer,
		ForeignKey("crm_chat_conversations.id", ondelete="SET NULL"),
		nullable=True,
		index=True,
	)
	context_json: Mapped[dict[str, Any] | None] = mapped_column(JSON, nullable=True)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
