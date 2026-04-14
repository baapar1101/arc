from __future__ import annotations

from datetime import datetime
from typing import Optional

from sqlalchemy import Integer, ForeignKey, String, Text, DateTime, Boolean, JSON, UniqueConstraint, Index
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class Announcement(Base):
	__tablename__ = "announcements"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	title: Mapped[str] = mapped_column(String(200), nullable=False, index=True)
	body: Mapped[str] = mapped_column(Text, nullable=False)
	level: Mapped[str] = mapped_column(String(16), default="info", index=True)  # info | warning | critical
	is_pinned: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
	is_active: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
	starts_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True, index=True)
	ends_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True, index=True)
	audience_filters: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)

	created_by: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	__table_args__ = (
		Index("ix_ann_active_schedule", "is_active", "starts_at", "ends_at"),
		Index("ix_ann_pinned_updated", "is_pinned", "updated_at"),
	)


class UserAnnouncement(Base):
	__tablename__ = "user_announcements"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
	announcement_id: Mapped[int] = mapped_column(Integer, ForeignKey("announcements.id", ondelete="CASCADE"), nullable=False, index=True)
	first_seen_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	read_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	dismissed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	__table_args__ = (
		UniqueConstraint("user_id", "announcement_id", name="uq_user_announcement"),
	)


