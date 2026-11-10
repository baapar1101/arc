"""تأیید سروری عمل پرریسک MCP اتوماسیون اداری."""
from __future__ import annotations

from datetime import datetime
from typing import Optional

from sqlalchemy import DateTime, ForeignKey, Index, Integer, JSON, String
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class OaMcpConfirmation(Base):
	__tablename__ = "oa_mcp_confirmations"
	__table_args__ = (
		Index("ix_oa_mcp_confirmations_user", "business_id", "user_id", "status"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False)
	user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
	connection_id: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
	tool_name: Mapped[str] = mapped_column(String(80), nullable=False)
	arguments_hash: Mapped[str] = mapped_column(String(64), nullable=False)
	arguments_json: Mapped[dict] = mapped_column(JSON, nullable=False)
	summary: Mapped[str] = mapped_column(String(300), nullable=False)
	status: Mapped[str] = mapped_column(String(16), nullable=False, default="pending")
	created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
	expires_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
	decided_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	consumed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
