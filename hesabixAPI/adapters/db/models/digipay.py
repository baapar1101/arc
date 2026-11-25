"""مدل‌های افزونه پرداخت اعتباری دیجی‌پی."""

from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import (
	Boolean,
	Date,
	DateTime,
	ForeignKey,
	Integer,
	Numeric,
	String,
	Text,
	UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base
from app.core.datetime_utils import utc_now


class DigipaySettings(Base):
	__tablename__ = "digipay_settings"
	__table_args__ = (UniqueConstraint("business_id", name="uq_digipay_settings_business"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
	)
	environment: Mapped[str] = mapped_column(String(16), nullable=False, default="sandbox")
	username_encrypted: Mapped[str | None] = mapped_column(Text, nullable=True)
	password_encrypted: Mapped[str | None] = mapped_column(Text, nullable=True)
	client_id_encrypted: Mapped[str | None] = mapped_column(Text, nullable=True)
	client_secret_encrypted: Mapped[str | None] = mapped_column(Text, nullable=True)
	person_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("persons.id", ondelete="SET NULL"), nullable=True, index=True
	)
	settlement_bank_account_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("bank_accounts.id", ondelete="SET NULL"), nullable=True
	)
	commission_percent: Mapped[Decimal] = mapped_column(
		Numeric(7, 3), nullable=False, default=Decimal("0")
	)
	vat_on_commission_percent: Mapped[Decimal] = mapped_column(
		Numeric(7, 3), nullable=False, default=Decimal("10")
	)
	seller_id: Mapped[str | None] = mapped_column(String(120), nullable=True)
	auto_deliver_in_store: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	extra_settings: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=utc_now)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, nullable=False, default=utc_now, onupdate=utc_now
	)


class DigipayPurchase(Base):
	__tablename__ = "digipay_purchases"
	__table_args__ = (
		UniqueConstraint("business_id", "provider_id", name="uq_digipay_purchases_provider"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
	)
	provider_id: Mapped[str] = mapped_column(String(80), nullable=False, index=True)
	ticket: Mapped[str | None] = mapped_column(String(255), nullable=True)
	redirect_url: Mapped[str | None] = mapped_column(Text, nullable=True)
	amount: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)
	cash_amount: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=Decimal("0"))
	credit_amount: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=Decimal("0"))
	cell_number: Mapped[str | None] = mapped_column(String(20), nullable=True)
	tracking_code: Mapped[str | None] = mapped_column(String(80), nullable=True, index=True)
	ticket_type: Mapped[int | None] = mapped_column(Integer, nullable=True)
	payment_gateway: Mapped[int | None] = mapped_column(Integer, nullable=True)
	status: Mapped[str] = mapped_column(String(24), nullable=False, default="pending", index=True)
	source: Mapped[str] = mapped_column(String(32), nullable=False, default="quick_sales")
	invoice_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("documents.id", ondelete="SET NULL"), nullable=True, index=True
	)
	receipt_document_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("documents.id", ondelete="SET NULL"), nullable=True
	)
	settlement_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("digipay_settlements.id", ondelete="SET NULL"), nullable=True, index=True
	)
	basket_json: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
	extra_info: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
	verified_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	delivered_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	created_by_user_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
	)
	created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=utc_now)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, nullable=False, default=utc_now, onupdate=utc_now
	)


class DigipaySettlement(Base):
	__tablename__ = "digipay_settlements"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
	)
	document_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("documents.id", ondelete="SET NULL"), nullable=True
	)
	bank_account_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("bank_accounts.id", ondelete="RESTRICT"), nullable=False
	)
	settlement_date: Mapped[date] = mapped_column(Date, nullable=False)
	gross_amount: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)
	commission_amount: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=Decimal("0"))
	vat_amount: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=Decimal("0"))
	net_amount: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)
	notes: Mapped[str | None] = mapped_column(Text, nullable=True)
	created_by_user_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
	)
	created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=utc_now)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, nullable=False, default=utc_now, onupdate=utc_now
	)
