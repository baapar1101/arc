from __future__ import annotations

from datetime import datetime
from typing import Optional

from sqlalchemy import (
	Integer,
	String,
	Boolean,
	DateTime,
	ForeignKey,
	Numeric,
	Text,
	UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class BusinessCreditSetting(Base):
	__tablename__ = "business_credit_settings"
	__table_args__ = (
		UniqueConstraint("business_id", name="uq_credit_settings_business"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)

	# High-level toggle
	is_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="0")
	# Default credit limit for persons/customers in this business
	default_limit: Mapped[float | None] = mapped_column(Numeric(14, 2), nullable=True)
	# Grace days before blocking or late fee
	grace_days: Mapped[int | None] = mapped_column(Integer, nullable=True)
	# Late fee rate percent over remaining amount (simple policy)
	late_fee_rate: Mapped[float | None] = mapped_column(Numeric(8, 4), nullable=True)
	# Auto-block account after X overdue days
	auto_block_after_days: Mapped[int | None] = mapped_column(Integer, nullable=True)
	# Strategy: single-default | by-group | per-user (string hint for UI)
	strategy: Mapped[str | None] = mapped_column(String(30), nullable=True)

	# Audit
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	business = relationship("Business", backref="credit_setting", uselist=False)


class InstallmentPlanTemplate(Base):
	__tablename__ = "installment_plan_templates"
	__table_args__ = (
		UniqueConstraint("business_id", "name", name="uq_installment_plan_name_per_business"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)

	name: Mapped[str] = mapped_column(String(120), nullable=False)
	method: Mapped[str] = mapped_column(String(20), nullable=False, default="flat")  # flat | amortized (future)
	num_installments: Mapped[int] = mapped_column(Integer, nullable=False)
	period_days: Mapped[int] = mapped_column(Integer, nullable=False, default=30)
	down_payment_percent: Mapped[float | None] = mapped_column(Numeric(8, 4), nullable=True)  # 0-100
	interest_rate: Mapped[float | None] = mapped_column(Numeric(8, 4), nullable=True)  # total flat rate percent
	late_fee_rate: Mapped[float | None] = mapped_column(Numeric(8, 4), nullable=True)
	issue_fee: Mapped[float | None] = mapped_column(Numeric(14, 2), nullable=True)
	description: Mapped[str | None] = mapped_column(Text, nullable=True)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="1")

	# Audit
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	business = relationship("Business", backref="installment_plan_templates")


