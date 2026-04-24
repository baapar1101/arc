from __future__ import annotations

from datetime import datetime

from sqlalchemy import BigInteger, Boolean, DateTime, Index, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class FirewallRule(Base):
	"""قانون فایروال نرم‌افزاری (اجازه / رد بر اساس IP یا CIDR و در صورت نیاز مسیر و متد)."""

	__tablename__ = "firewall_rules"
	__table_args__ = (
		Index("ix_firewall_rules_enabled_priority", "enabled", "priority"),
		Index("ix_firewall_rules_expires_at", "expires_at"),
	)

	id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
	enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	"""allow = عبور صریح؛ deny = مسدود"""
	action: Mapped[str] = mapped_column(String(8), nullable=False)
	"""مثال 192.168.1.10 یا 10.0.0.0/8"""
	ip_cidr: Mapped[str] = mapped_column(String(64), nullable=False)
	"""پیشوند مسیر؛ خالی یا NULL یعنی همه مسیرها"""
	path_prefix: Mapped[str | None] = mapped_column(String(512), nullable=True)
	"""خالی یعنی همه متدها؛ وگرنه CSV مثل GET,POST"""
	http_methods: Mapped[str | None] = mapped_column(String(128), nullable=True)
	"""عدد کمتر = اولویت بالاتر در ارزیابی"""
	priority: Mapped[int] = mapped_column(Integer, nullable=False, default=100)
	expires_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	note: Mapped[str | None] = mapped_column(Text, nullable=True)
	"""manual، api_ban، import، ..."""
	source: Mapped[str] = mapped_column(String(32), nullable=False, default="manual")
	created_by_user_id: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)


class FirewallRequestLog(Base):
	"""لاگ درخواست‌های رد شده توسط فایروال."""

	__tablename__ = "firewall_request_logs"
	__table_args__ = (
		Index("ix_firewall_req_logs_created", "created_at"),
		Index("ix_firewall_req_logs_ip_created", "client_ip", "created_at"),
	)

	id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	client_ip: Mapped[str] = mapped_column(String(45), nullable=False)
	method: Mapped[str] = mapped_column(String(16), nullable=False)
	path: Mapped[str] = mapped_column(String(1024), nullable=False)
	user_agent: Mapped[str | None] = mapped_column(String(512), nullable=True)
	rule_id: Mapped[int | None] = mapped_column(BigInteger, nullable=True)


class FirewallAuditLog(Base):
	"""رویدادهای مدیریتی فایروال (ایجاد/ویرایش قانون، بن، آنبن، ...)."""

	__tablename__ = "firewall_audit_logs"
	__table_args__ = (Index("ix_firewall_audit_created", "created_at"),)

	id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	event_type: Mapped[str] = mapped_column(String(64), nullable=False)
	actor_user_id: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
	ip_cidr: Mapped[str | None] = mapped_column(String(64), nullable=True)
	rule_id: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
	details: Mapped[str | None] = mapped_column(Text, nullable=True)
