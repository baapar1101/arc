"""مدل‌های اشتراک و صورتحساب پشتیبانی (سطح کاربر — بدون کسب‌وکار/کیف‌پول)."""

from __future__ import annotations

from datetime import datetime
from typing import Optional, Any

from sqlalchemy import (
	String,
	Integer,
	DateTime,
	ForeignKey,
	UniqueConstraint,
	Numeric,
	Boolean,
	Text,
	JSON,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


ALLOWED_PERIOD_MONTHS = (1, 3, 6, 12)


class SupportPlan(Base):
	__tablename__ = "support_plans"
	__table_args__ = (UniqueConstraint("code", name="uq_support_plans_code"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	name: Mapped[str] = mapped_column(String(200), nullable=False)
	code: Mapped[str] = mapped_column(String(100), nullable=False, index=True)
	period_months: Mapped[int] = mapped_column(Integer, nullable=False)
	price: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	currency_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("currencies.id", ondelete="RESTRICT"), nullable=False
	)
	is_free: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
	description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	features_json: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)
	max_open_tickets: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
	sla_policy_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("support_sla_policies.id", ondelete="SET NULL"), nullable=True, index=True
	)
	priority_weight: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
	includes_priority_support: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	trial_days: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)

	currency = relationship("Currency", backref="support_plans")
	subscriptions = relationship("SupportSubscription", back_populates="plan")
	invoices = relationship("SupportInvoice", back_populates="plan")


class SupportSubscription(Base):
	__tablename__ = "support_subscriptions"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	user_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
	)
	plan_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("support_plans.id", ondelete="RESTRICT"), nullable=False, index=True
	)
	# pending | active | grace | expired | cancelled | replaced
	status: Mapped[str] = mapped_column(String(20), nullable=False, default="pending", index=True)
	starts_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	ends_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True, index=True)
	grace_ends_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	auto_renew: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	source_invoice_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("support_invoices.id", ondelete="SET NULL"), nullable=True, index=True
	)
	cancelled_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	cancel_reason: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)

	plan = relationship("SupportPlan", back_populates="subscriptions")
	user = relationship("User", backref="support_subscriptions")
	source_invoice = relationship(
		"SupportInvoice",
		foreign_keys=[source_invoice_id],
		post_update=True,
	)


class SupportInvoice(Base):
	__tablename__ = "support_invoices"
	__table_args__ = (UniqueConstraint("code", name="uq_support_invoices_code"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	user_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
	)
	plan_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("support_plans.id", ondelete="RESTRICT"), nullable=False, index=True
	)
	code: Mapped[str] = mapped_column(String(50), nullable=False, index=True)
	# purchase | renewal | upgrade | trial
	invoice_type: Mapped[str] = mapped_column(String(20), nullable=False, default="purchase")
	amount: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	discount_amount: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	currency_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("currencies.id", ondelete="RESTRICT"), nullable=False
	)
	# draft | awaiting_payment | paid | failed | expired | void | refunded
	status: Mapped[str] = mapped_column(String(20), nullable=False, default="awaiting_payment", index=True)
	issued_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	due_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	paid_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	# اشاره‌گر denormalized به آخرین نشست؛ FK عمداً نیست تا چرخه با support_payment_sessions نداشته باشیم
	payment_session_id: Mapped[Optional[int]] = mapped_column(Integer, nullable=True, index=True)
	gateway_id: Mapped[Optional[int]] = mapped_column(
		Integer, ForeignKey("payment_gateways.id", ondelete="SET NULL"), nullable=True
	)
	gateway_provider: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
	gateway_ref: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)
	gateway_trace: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)
	period_months: Mapped[int] = mapped_column(Integer, nullable=False)
	coverage_starts_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	coverage_ends_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	extra_info: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)

	plan = relationship("SupportPlan", back_populates="invoices")
	user = relationship("User", backref="support_invoices")
	currency = relationship("Currency", backref="support_invoices")


class SupportPaymentSession(Base):
	__tablename__ = "support_payment_sessions"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	user_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
	)
	invoice_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("support_invoices.id", ondelete="CASCADE"), nullable=False, index=True
	)
	gateway_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("payment_gateways.id", ondelete="RESTRICT"), nullable=False, index=True
	)
	amount: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False)
	currency_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("currencies.id", ondelete="RESTRICT"), nullable=False
	)
	# created | redirected | verifying | paid | failed | cancelled | expired
	status: Mapped[str] = mapped_column(String(20), nullable=False, default="created", index=True)
	external_ref: Mapped[Optional[str]] = mapped_column(String(200), nullable=True, index=True)
	provider_payload: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)
	verify_payload: Mapped[Optional[Any]] = mapped_column(JSON, nullable=True)
	client_return_path: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
	expires_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
	paid_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)

	invoice = relationship(
		"SupportInvoice",
		foreign_keys=[invoice_id],
		backref="payment_sessions",
	)

class SupportUsageCounter(Base):
	__tablename__ = "support_usage_counters"
	__table_args__ = (
		UniqueConstraint("user_id", "period_key", name="uq_support_usage_user_period"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	user_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
	)
	period_key: Mapped[str] = mapped_column(String(20), nullable=False)
	tickets_created: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)
