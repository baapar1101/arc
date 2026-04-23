from __future__ import annotations

from datetime import datetime

from sqlalchemy import String, DateTime
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class Captcha(Base):
	__tablename__ = "captchas"

	id: Mapped[str] = mapped_column(String(40), primary_key=True)
	code_hash: Mapped[str] = mapped_column(String(128), nullable=False)
	expires_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
	attempts: Mapped[int] = mapped_column(default=0, nullable=False)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	client_ip: Mapped[str | None] = mapped_column(String(45), nullable=True)


