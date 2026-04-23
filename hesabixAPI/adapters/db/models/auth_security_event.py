from __future__ import annotations

from datetime import datetime

from sqlalchemy import String, DateTime, Text, BigInteger
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class AuthSecurityEvent(Base):
	__tablename__ = "auth_security_events"

	id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False, index=True)
	event_type: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
	client_ip: Mapped[str | None] = mapped_column(String(45), nullable=True, index=True)
	account_key: Mapped[str | None] = mapped_column(String(32), nullable=True, index=True)
	detail_json: Mapped[str | None] = mapped_column(Text, nullable=True)
