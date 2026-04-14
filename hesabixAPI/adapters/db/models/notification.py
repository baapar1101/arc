from __future__ import annotations

from datetime import datetime
from typing import Optional

from sqlalchemy import Integer, String, Text, DateTime, Boolean, JSON, ForeignKey, Index
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class NotificationOutbox(Base):
	__tablename__ = "notification_outbox"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), index=True)
	channel: Mapped[str] = mapped_column(String(32), index=True)  # telegram | email | sms | inapp
	event_key: Mapped[str] = mapped_column(String(100), index=True)
	payload: Mapped[dict] = mapped_column(JSON)
	locale: Mapped[Optional[str]] = mapped_column(String(10), nullable=True)
	status: Mapped[str] = mapped_column(String(16), default="pending", index=True)  # pending|sent|failed
	error_message: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	retry_count: Mapped[int] = mapped_column(Integer, default=0)
	next_attempt_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True, index=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	__table_args__ = (
		Index("ix_outbox_pending_next", "status", "next_attempt_at"),
	)


class NotificationDeliveryAttempt(Base):
	__tablename__ = "notification_delivery_attempts"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	outbox_id: Mapped[int] = mapped_column(Integer, ForeignKey("notification_outbox.id", ondelete="CASCADE"), index=True)
	channel: Mapped[str] = mapped_column(String(32), index=True)
	success: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
	error_message: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	performed_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False, index=True)


