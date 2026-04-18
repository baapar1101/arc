from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from sqlalchemy import (
	String,
	Integer,
	DateTime,
	ForeignKey,
	Numeric,
	Boolean,
	Text,
	UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class CustomerClubSettings(Base):
	"""تنظیمات باشگاه مشتریان به ازای هر کسب‌وکار."""

	__tablename__ = "customer_club_settings"
	__table_args__ = (UniqueConstraint("business_id", name="uq_customer_club_settings_business"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer,
		ForeignKey("businesses.id", ondelete="CASCADE"),
		nullable=False,
		index=True,
	)
	enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	# percent_basis | points_per_currency
	earn_mode: Mapped[str] = mapped_column(String(40), nullable=False, default="percent_basis")
	# net | total_with_tax
	amount_basis: Mapped[str] = mapped_column(String(40), nullable=False, default="net")
	percent_of_basis: Mapped[Decimal | None] = mapped_column(Numeric(18, 8), nullable=True)
	step_currency_amount: Mapped[Decimal | None] = mapped_column(Numeric(18, 4), nullable=True)
	points_per_step: Mapped[Decimal | None] = mapped_column(Numeric(18, 8), nullable=True)
	# floor | ceil | round
	rounding_mode: Mapped[str] = mapped_column(String(16), nullable=False, default="floor")
	max_points_per_invoice: Mapped[Decimal | None] = mapped_column(Numeric(18, 4), nullable=True)
	min_basis_amount: Mapped[Decimal] = mapped_column(Numeric(18, 4), nullable=False, default=Decimal("0"))
	require_customer_person_type: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	currency_value_per_point: Mapped[Decimal | None] = mapped_column(
		Numeric(18, 8), nullable=True, comment="مبلغ تخفیف به ازای هر امتیاز در ارز فاکتور"
	)
	max_redeem_points_per_invoice: Mapped[Decimal | None] = mapped_column(Numeric(18, 4), nullable=True)
	points_expire_after_days: Mapped[int | None] = mapped_column(Integer, nullable=True)

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class CustomerClubBalance(Base):
	"""مانده امتیاز به ازای هر شخص در کسب‌وکار."""

	__tablename__ = "customer_club_balances"
	__table_args__ = (UniqueConstraint("business_id", "person_id", name="uq_customer_club_balance_biz_person"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer,
		ForeignKey("businesses.id", ondelete="CASCADE"),
		nullable=False,
		index=True,
	)
	person_id: Mapped[int] = mapped_column(
		Integer,
		ForeignKey("persons.id", ondelete="CASCADE"),
		nullable=False,
		index=True,
	)
	balance_points: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False, default=Decimal("0"))

	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class CustomerClubLedger(Base):
	"""دفتر تراکنش‌های امتیاز (append-only منطقی)."""

	__tablename__ = "customer_club_ledger"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer,
		ForeignKey("businesses.id", ondelete="CASCADE"),
		nullable=False,
		index=True,
	)
	person_id: Mapped[int] = mapped_column(
		Integer,
		ForeignKey("persons.id", ondelete="SET NULL"),
		nullable=True,
		index=True,
	)
	delta_points: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False)
	balance_after: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False)
	# accrual | reversal | adjustment | sync_delta
	transaction_type: Mapped[str] = mapped_column(String(32), nullable=False)
	reference_document_id: Mapped[int | None] = mapped_column(
		Integer,
		ForeignKey("documents.id", ondelete="SET NULL"),
		nullable=True,
		index=True,
	)
	description: Mapped[str | None] = mapped_column(Text, nullable=True)
	created_by_user_id: Mapped[int | None] = mapped_column(
		Integer,
		ForeignKey("users.id", ondelete="SET NULL"),
		nullable=True,
		index=True,
	)

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


class CustomerClubInvoiceSnapshot(Base):
	"""آخرین امتیاز ثبت‌شده برای یک سند فاکتور جهت همگام‌سازی و حذف."""

	__tablename__ = "customer_club_invoice_snapshots"

	document_id: Mapped[int] = mapped_column(
		Integer,
		ForeignKey("documents.id", ondelete="CASCADE"),
		primary_key=True,
	)
	business_id: Mapped[int] = mapped_column(
		Integer,
		ForeignKey("businesses.id", ondelete="CASCADE"),
		nullable=False,
		index=True,
	)
	person_id: Mapped[int] = mapped_column(
		Integer,
		ForeignKey("persons.id", ondelete="SET NULL"),
		nullable=True,
		index=True,
	)
	accrued_points: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False, default=Decimal("0"))
	redeemed_points: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False, default=Decimal("0"))

	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)


class CustomerClubTier(Base):
	"""سطح وفاداری (ضریب امتیاز)."""

	__tablename__ = "customer_club_tiers"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer,
		ForeignKey("businesses.id", ondelete="CASCADE"),
		nullable=False,
		index=True,
	)
	sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
	name: Mapped[str] = mapped_column(String(120), nullable=False)
	min_balance_points: Mapped[Decimal] = mapped_column(
		Numeric(18, 6), nullable=False, default=Decimal("0")
	)
	earn_multiplier: Mapped[Decimal] = mapped_column(
		Numeric(18, 6), nullable=False, default=Decimal("1")
	)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)
