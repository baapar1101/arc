from __future__ import annotations

from datetime import datetime

from sqlalchemy import Integer, String, DateTime, ForeignKey, Index
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class BaleLinkToken(Base):
	__tablename__ = "bale_link_tokens"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), index=True)
	token: Mapped[str] = mapped_column(String(128), unique=True, index=True)
	expires_at: Mapped[datetime] = mapped_column(DateTime, index=True)
	used_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	created_ip: Mapped[str | None] = mapped_column(String(64), nullable=True)
	user_agent: Mapped[str | None] = mapped_column(String(255), nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)

	__table_args__ = (
		Index("ix_bale_link_validity", "expires_at", "used_at"),
	)
