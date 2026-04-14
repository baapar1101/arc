from __future__ import annotations

from datetime import datetime

from sqlalchemy import String, DateTime, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class ApiKey(Base):
	__tablename__ = "api_keys"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False)
	key_hash: Mapped[str] = mapped_column(String(128), unique=True, index=True, nullable=False)
	key_type: Mapped[str] = mapped_column(String(16), nullable=False)  # "session" | "personal"
	name: Mapped[str | None] = mapped_column(String(100), nullable=True)
	scopes: Mapped[str | None] = mapped_column(String(500), nullable=True)
	device_id: Mapped[str | None] = mapped_column(String(100), nullable=True)
	user_agent: Mapped[str | None] = mapped_column(String(255), nullable=True)
	ip: Mapped[str | None] = mapped_column(String(64), nullable=True)
	expires_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	last_used_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	revoked_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


