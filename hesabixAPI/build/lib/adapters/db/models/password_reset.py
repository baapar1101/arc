from __future__ import annotations

from datetime import datetime

from sqlalchemy import String, DateTime, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class PasswordReset(Base):
	__tablename__ = "password_resets"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False)
	token_hash: Mapped[str] = mapped_column(String(128), unique=True, index=True, nullable=False)
	expires_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
	used_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


