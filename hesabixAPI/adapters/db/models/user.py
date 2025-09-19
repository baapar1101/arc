from __future__ import annotations

from datetime import datetime

from sqlalchemy import String, DateTime, Boolean, Integer, ForeignKey, JSON
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class User(Base):
	__tablename__ = "users"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	email: Mapped[str | None] = mapped_column(String(255), unique=True, index=True, nullable=True)
	mobile: Mapped[str | None] = mapped_column(String(32), unique=True, index=True, nullable=True)
	first_name: Mapped[str | None] = mapped_column(String(100), nullable=True)
	last_name: Mapped[str | None] = mapped_column(String(100), nullable=True)
	password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
	is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
	# Marketing/Referral fields
	referral_code: Mapped[str] = mapped_column(String(32), unique=True, index=True, nullable=False)
	referred_by_user_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
	# App permissions
	app_permissions: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)


