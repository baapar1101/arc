from __future__ import annotations

from datetime import datetime

from sqlalchemy import BigInteger, Boolean, DateTime, Index, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class FirewallRatePolicy(Base):
	"""محدودیت نرخ درخواست (به‌ازای IP) بر اساس پیشوند مسیر — زیرنظار فایروال مرکزی."""

	__tablename__ = "firewall_rate_policies"
	__table_args__ = (Index("ix_firewall_rate_enabled_prio", "enabled", "priority"),)

	id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
	enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	"""کمتر = زودتر سنجش می‌شود پس از طول path_prefix"""
	priority: Mapped[int] = mapped_column(Integer, nullable=False, default=100)
	"""مثال /api/v1/public/crm-chat (باید با / شروع شود)"""
	path_prefix: Mapped[str] = mapped_column(String(512), nullable=False)
	"""خالی = همه متدها؛ وگرنه CSV مثل GET,POST"""
	http_methods: Mapped[str | None] = mapped_column(String(128), nullable=True)
	max_requests: Mapped[int] = mapped_column(Integer, nullable=False)
	window_seconds: Mapped[int] = mapped_column(Integer, nullable=False)
	note: Mapped[str | None] = mapped_column(Text, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
