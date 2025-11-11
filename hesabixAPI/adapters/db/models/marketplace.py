from __future__ import annotations

from datetime import datetime, timedelta
from typing import Optional

from sqlalchemy import (
	String,
	Integer,
	DateTime,
	ForeignKey,
	UniqueConstraint,
	Numeric,
	Boolean,
	Text,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class MarketplacePlugin(Base):
	__tablename__ = "marketplace_plugins"
	__table_args__ = (
		UniqueConstraint("code", name="uq_marketplace_plugins_code"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	code: Mapped[str] = mapped_column(String(100), nullable=False)
	name: Mapped[str] = mapped_column(String(200), nullable=False)
	description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	category: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
	icon_url: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	plans = relationship("MarketplacePluginPlan", back_populates="plugin", cascade="all, delete-orphan")


class MarketplacePluginPlan(Base):
	__tablename__ = "marketplace_plugin_plans"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	plugin_id: Mapped[int] = mapped_column(Integer, ForeignKey("marketplace_plugins.id", ondelete="CASCADE"), index=True, nullable=False)
	period: Mapped[str] = mapped_column(String(20), nullable=False)  # monthly | yearly | lifetime
	price: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	currency_id: Mapped[int] = mapped_column(Integer, ForeignKey("currencies.id", ondelete="RESTRICT"), nullable=False)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	plugin = relationship("MarketplacePlugin", back_populates="plans")
	# currency relationship is optional to avoid circular imports in model layer


class MarketplaceOrder(Base):
	__tablename__ = "marketplace_orders"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), index=True, nullable=False)
	plugin_id: Mapped[int] = mapped_column(Integer, ForeignKey("marketplace_plugins.id", ondelete="RESTRICT"), index=True, nullable=False)
	plan_id: Mapped[int] = mapped_column(Integer, ForeignKey("marketplace_plugin_plans.id", ondelete="RESTRICT"), index=True, nullable=False)
	quantity: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
	unit_price: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	total_price: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	currency_id: Mapped[int] = mapped_column(Integer, ForeignKey("currencies.id", ondelete="RESTRICT"), nullable=False)
	status: Mapped[str] = mapped_column(String(20), nullable=False, default="pending")  # pending | paid | failed | cancelled
	wallet_transaction_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("wallet_transactions.id", ondelete="SET NULL"), nullable=True, index=True)
	invoice_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("marketplace_invoices.id", ondelete="SET NULL"), nullable=True, index=True)
	external_ref: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
	extra_info: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)


class MarketplaceInvoice(Base):
	__tablename__ = "marketplace_invoices"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	order_id: Mapped[int] = mapped_column(Integer, ForeignKey("marketplace_orders.id", ondelete="CASCADE"), index=True, nullable=False)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), index=True, nullable=False)
	code: Mapped[str] = mapped_column(String(50), nullable=False)
	total: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	currency_id: Mapped[int] = mapped_column(Integer, ForeignKey("currencies.id", ondelete="RESTRICT"), nullable=False)
	status: Mapped[str] = mapped_column(String(20), nullable=False, default="issued")  # issued | paid | void
	issued_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	paid_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	extra_info: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)


class BusinessPlugin(Base):
	__tablename__ = "business_plugins"
	__table_args__ = (
		UniqueConstraint("business_id", "plugin_id", name="uq_business_plugin_unique"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), index=True, nullable=False)
	plugin_id: Mapped[int] = mapped_column(Integer, ForeignKey("marketplace_plugins.id", ondelete="RESTRICT"), index=True, nullable=False)
	plan_id: Mapped[int] = mapped_column(Integer, ForeignKey("marketplace_plugin_plans.id", ondelete="RESTRICT"), index=True, nullable=False)
	status: Mapped[str] = mapped_column(String(20), nullable=False, default="active")  # active | expired | suspended
	starts_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	ends_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	auto_renew: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	extra_info: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)


