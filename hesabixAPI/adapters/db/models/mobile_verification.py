from __future__ import annotations

from datetime import datetime
from typing import Optional

from sqlalchemy import String, DateTime, ForeignKey, Integer, Index
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class MobileVerificationToken(Base):
	__tablename__ = "mobile_verification_tokens"
	
	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False)
	mobile: Mapped[str] = mapped_column(String(32), nullable=False, index=True)
	otp_code_hash: Mapped[str] = mapped_column(String(128), nullable=False, index=True)
	expires_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, index=True)
	verified_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	attempts: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	
	__table_args__ = (
		Index("ix_mobile_verification_validity", "expires_at", "verified_at"),
	)

