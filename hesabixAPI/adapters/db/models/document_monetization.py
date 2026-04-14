from __future__ import annotations

from datetime import datetime

from sqlalchemy import (
	String,
	Integer,
	DateTime,
	ForeignKey,
	Boolean,
	Numeric,
	Text,
	JSON,
	UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class DocumentSubscriptionPlan(Base):
	__tablename__ = "document_subscription_plans"
	__table_args__ = (
		UniqueConstraint("code", name="uq_document_subscription_plans_code"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	name: Mapped[str] = mapped_column(String(200), nullable=False)
	code: Mapped[str] = mapped_column(String(100), nullable=False, index=True)
	description: Mapped[str | None] = mapped_column(Text, nullable=True)
	period_months: Mapped[int] = mapped_column(Integer, nullable=False)
	price: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	currency_id: Mapped[int] = mapped_column(Integer, ForeignKey("currencies.id", ondelete="RESTRICT"), nullable=False)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	currency = relationship("Currency")
	subscriptions = relationship("BusinessDocumentSubscription", back_populates="plan", cascade="all, delete-orphan")


class BusinessDocumentSubscription(Base):
	__tablename__ = "business_document_subscriptions"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	plan_id: Mapped[int] = mapped_column(Integer, ForeignKey("document_subscription_plans.id", ondelete="RESTRICT"), nullable=False)
	status: Mapped[str] = mapped_column(String(20), nullable=False, default="active")  # active, expired, cancelled
	starts_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	ends_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
	auto_renew: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	created_by_user_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
	extra_data: Mapped[dict | None] = mapped_column(JSON, nullable=True)

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	business = relationship("Business", backref="document_subscriptions")
	plan = relationship("DocumentSubscriptionPlan", back_populates="subscriptions")


class DocumentUsagePolicy(Base):
	__tablename__ = "document_usage_policies"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	policy_type: Mapped[str] = mapped_column(String(30), nullable=False)  # free, subscription, per_document, volume, hybrid
	title: Mapped[str] = mapped_column(String(200), nullable=False)
	priority: Mapped[int] = mapped_column(Integer, nullable=False, default=100)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	config: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	starts_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	ends_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	created_by_user_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
	updated_by_user_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	business = relationship("Business", backref="document_usage_policies")
	created_by = relationship("User", foreign_keys=[created_by_user_id])
	updated_by = relationship("User", foreign_keys=[updated_by_user_id])


class DocumentUsageCharge(Base):
	__tablename__ = "document_usage_charges"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	policy_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("document_usage_policies.id", ondelete="SET NULL"), nullable=True, index=True)
	document_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("documents.id", ondelete="SET NULL"), nullable=True, index=True)
	charge_type: Mapped[str] = mapped_column(String(30), nullable=False)  # per_document, subscription_fee, volume_cycle, manual
	status: Mapped[str] = mapped_column(String(20), nullable=False, default="pending")  # pending, awaiting_payment, paid, canceled, failed
	amount: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	currency_id: Mapped[int] = mapped_column(Integer, ForeignKey("currencies.id", ondelete="RESTRICT"), nullable=False)
	wallet_transaction_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("wallet_transactions.id", ondelete="RESTRICT"), nullable=True, index=True)
	description: Mapped[str | None] = mapped_column(String(500), nullable=True)
	metrics: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	period_key: Mapped[str | None] = mapped_column(String(50), nullable=True, index=True)
	period_start: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	period_end: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	issued_by_user_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
	paid_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	business = relationship("Business", backref="document_usage_charges")
	policy = relationship("DocumentUsagePolicy", backref="charges")
	document = relationship("Document", backref="usage_charges")
	currency = relationship("Currency")
	wallet_transaction = relationship("WalletTransaction")
	issued_by = relationship("User", foreign_keys=[issued_by_user_id])


class DocumentUsagePeriod(Base):
	__tablename__ = "document_usage_periods"
	__table_args__ = (
		UniqueConstraint("policy_id", "period_key", name="uq_document_usage_period_policy_key"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	policy_id: Mapped[int] = mapped_column(Integer, ForeignKey("document_usage_policies.id", ondelete="CASCADE"), nullable=False, index=True)
	period_key: Mapped[str] = mapped_column(String(50), nullable=False)
	cycle: Mapped[str] = mapped_column(String(20), nullable=False)  # weekly, monthly, yearly
	period_start: Mapped[datetime] = mapped_column(DateTime, nullable=False)
	period_end: Mapped[datetime] = mapped_column(DateTime, nullable=False)
	documents_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
	total_amount: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	status: Mapped[str] = mapped_column(String(20), nullable=False, default="open")  # open, finalized, invoiced
	charge_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("document_usage_charges.id", ondelete="SET NULL"), nullable=True)
	extra_data: Mapped[dict | None] = mapped_column(JSON, nullable=True)

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	business = relationship("Business", backref="document_usage_periods")
	policy = relationship("DocumentUsagePolicy", backref="usage_periods")
	charge = relationship("DocumentUsageCharge", foreign_keys=[charge_id], backref="volume_period", uselist=False)


class DocumentUsageCursor(Base):
	__tablename__ = "document_usage_cursors"
	__table_args__ = (
		UniqueConstraint("scope", "business_id", name="uq_document_usage_cursor_scope_business"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	scope: Mapped[str] = mapped_column(String(20), nullable=False, default="global")
	business_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=True, index=True)
	last_document_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
	last_document_created_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	business = relationship("Business", backref="document_usage_cursor", uselist=False)


