from __future__ import annotations

from datetime import datetime
from typing import Optional

from sqlalchemy import Integer, String, DateTime, Boolean, JSON, Text, UniqueConstraint, Index, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class NotificationTemplate(Base):
	__tablename__ = "notification_templates"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	event_key: Mapped[str] = mapped_column(String(100), index=True)
	channel: Mapped[str] = mapped_column(String(32), index=True)  # telegram|email|sms|inapp
	locale: Mapped[Optional[str]] = mapped_column(String(10), nullable=True, index=True)
	subject: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)
	body: Mapped[str] = mapped_column(Text, nullable=False)
	is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False, index=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	__table_args__ = (
		UniqueConstraint("event_key", "channel", "locale", name="uq_template_key_channel_locale"),
	)


class UserNotificationSetting(Base):
	__tablename__ = "user_notification_settings"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), index=True)
	channel: Mapped[str] = mapped_column(String(32), index=True)  # telegram|email|sms|inapp
	event_key: Mapped[Optional[str]] = mapped_column(String(100), nullable=True, index=True)  # null => global
	enabled: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False, index=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	__table_args__ = (
		UniqueConstraint("user_id", "channel", "event_key", name="uq_user_channel_event"),
		Index("ix_user_settings_user_channel", "user_id", "channel"),
	)


