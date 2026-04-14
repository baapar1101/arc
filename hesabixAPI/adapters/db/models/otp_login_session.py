from __future__ import annotations

from datetime import datetime
from typing import Optional

from sqlalchemy import String, DateTime, ForeignKey, Integer, Index
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class OtpLoginSession(Base):
	__tablename__ = "otp_login_sessions"
	
	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	session_id: Mapped[str] = mapped_column(String(128), unique=True, nullable=False, index=True)
	mobile: Mapped[Optional[str]] = mapped_column(String(32), nullable=True, index=True)
	email: Mapped[Optional[str]] = mapped_column(String(255), nullable=True, index=True)
	channel: Mapped[str] = mapped_column(String(20), nullable=False, default="sms")  # sms, email, telegram
	user_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=True, index=True)
	otp_code_hash: Mapped[str] = mapped_column(String(128), nullable=False)
	attempts: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
	expires_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, index=True)
	verified_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	ip_address: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
	user_agent: Mapped[Optional[str]] = mapped_column(String(255), nullable=True)
	last_otp_sent_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)  # برای rate limiting
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	
	__table_args__ = (
		Index("ix_otp_login_validity", "expires_at", "verified_at"),
	)

