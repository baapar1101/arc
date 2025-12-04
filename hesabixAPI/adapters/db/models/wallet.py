from __future__ import annotations

from datetime import datetime
from typing import Optional

from sqlalchemy import String, Integer, DateTime, ForeignKey, UniqueConstraint, Numeric, Boolean, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class WalletAccount(Base):
	__tablename__ = "wallet_accounts"
	__table_args__ = (
		UniqueConstraint('business_id', name='uq_wallet_accounts_business'),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)

	# مانده‌ها به ارز پایه سیستم
	available_balance: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	pending_balance: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)

	status: Mapped[str] = mapped_column(String(20), nullable=False, default="active")  # active | suspended

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	# روابط
	business = relationship("Business", backref="wallet_account", uselist=False)


class WalletTransaction(Base):
	__tablename__ = "wallet_transactions"
	__table_args__ = (
		# ایندکس‌ها از طریق migration اضافه می‌شود
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)

	# انواع: customer_payment, top_up, internal_invoice_payment, payout_request, payout_settlement, refund, fee, chargeback, reversal
	type: Mapped[str] = mapped_column(String(50), nullable=False)
	status: Mapped[str] = mapped_column(String(20), nullable=False, default="pending")  # pending, succeeded, failed, reversed

	amount: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)  # ارز پایه
	fee_amount: Mapped[float | None] = mapped_column(Numeric(18, 2), nullable=True)

	description: Mapped[str | None] = mapped_column(String(500), nullable=True)
	external_ref: Mapped[str | None] = mapped_column(String(100), nullable=True)  # شناسه درگاه/مرجع خارجی

	# پیوند به سند حسابداری
	document_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("documents.id", ondelete="SET NULL"), nullable=True, index=True)

	# متادیتا
	extra_info: Mapped[str | None] = mapped_column(Text, nullable=True)

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	business = relationship("Business", backref="wallet_transactions")
	document = relationship("Document", backref="wallet_transactions")


class WalletPayout(Base):
	__tablename__ = "wallet_payouts"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	bank_account_id: Mapped[int] = mapped_column(Integer, ForeignKey("bank_accounts.id", ondelete="RESTRICT"), nullable=False, index=True)

	gross_amount: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	fees: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	net_amount: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)

	status: Mapped[str] = mapped_column(String(20), nullable=False, default="requested")  # requested, approved, processing, settled, failed, canceled
	schedule_type: Mapped[str] = mapped_column(String(20), nullable=False, default="manual")  # manual, daily, weekly, threshold

	external_ref: Mapped[str | None] = mapped_column(String(100), nullable=True)
	extra_info: Mapped[str | None] = mapped_column(Text, nullable=True)
	document_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("documents.id", ondelete="SET NULL"), nullable=True, index=True)
	settlement_date: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	bank_tracking_code: Mapped[str | None] = mapped_column(String(100), nullable=True)
	settlement_note: Mapped[str | None] = mapped_column(Text, nullable=True)

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	business = relationship("Business", backref="wallet_payouts")
	bank_account = relationship("BankAccount", backref="wallet_payouts")
	document = relationship("Document", backref="wallet_payouts")


class WalletSetting(Base):
	__tablename__ = "wallet_settings"
	__table_args__ = (
		UniqueConstraint('business_id', name='uq_wallet_settings_business'),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)

	mode: Mapped[str] = mapped_column(String(20), nullable=False, default="manual")  # manual | auto
	frequency: Mapped[str | None] = mapped_column(String(20), nullable=True)  # daily | weekly
	threshold_amount: Mapped[float | None] = mapped_column(Numeric(18, 2), nullable=True)
	min_reserve: Mapped[float | None] = mapped_column(Numeric(18, 2), nullable=True)
	default_bank_account_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("bank_accounts.id", ondelete="SET NULL"), nullable=True)

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	business = relationship("Business", backref="wallet_settings", uselist=False)


