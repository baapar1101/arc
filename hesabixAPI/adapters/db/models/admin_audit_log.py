"""لاگ کارهای مدیر سیستم."""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import BigInteger, DateTime, Index, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class AdminAuditLog(Base):
	__tablename__ = "admin_audit_logs"
	__table_args__ = (
		Index("ix_admin_audit_logs_created", "created_at"),
		Index("ix_admin_audit_logs_action_created", "action", "created_at"),
		Index("ix_admin_audit_logs_actor", "actor_user_id"),
	)

	id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	actor_user_id: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
	action: Mapped[str] = mapped_column(String(64), nullable=False)
	target_type: Mapped[str | None] = mapped_column(String(64), nullable=True)
	target_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
	summary: Mapped[str] = mapped_column(String(500), nullable=False)
	metadata_json: Mapped[str | None] = mapped_column(Text, nullable=True)
	client_ip: Mapped[str | None] = mapped_column(String(64), nullable=True)
