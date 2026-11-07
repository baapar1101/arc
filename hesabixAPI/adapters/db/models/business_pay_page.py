from __future__ import annotations

from datetime import datetime

from sqlalchemy import (
	Boolean,
	DateTime,
	ForeignKey,
	Integer,
	Numeric,
	String,
	Text,
	UniqueConstraint,
	Index,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class BusinessPayPage(Base):
	"""صفحه واریز عمومی یکتا برای هر کسب‌وکار (لینک /u/{username})."""

	__tablename__ = "business_pay_pages"
	__table_args__ = (
		UniqueConstraint("business_id", name="uq_business_pay_pages_business"),
		UniqueConstraint("username", name="uq_business_pay_pages_username"),
		Index("ix_business_pay_pages_username", "username"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
	)
	username: Mapped[str | None] = mapped_column(String(30), nullable=True)
	is_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="0")
	display_title: Mapped[str | None] = mapped_column(String(120), nullable=True)
	show_logo: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="1")
	intro_text: Mapped[str | None] = mapped_column(Text, nullable=True)
	gateway_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("payment_gateways.id", ondelete="SET NULL"), nullable=True
	)
	min_amount: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=50000)
	max_amount: Mapped[float | None] = mapped_column(Numeric(18, 2), nullable=True)
	notify_inapp: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="1")
	notify_sms: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="0")
	match_customer_by_mobile: Mapped[bool] = mapped_column(
		Boolean, nullable=False, default=True, server_default="1"
	)
	create_customer_if_missing: Mapped[bool] = mapped_column(
		Boolean, nullable=False, default=True, server_default="1"
	)
	use_anonymous_if_no_mobile: Mapped[bool] = mapped_column(
		Boolean, nullable=False, default=True, server_default="1"
	)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(
		DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
	)

	business = relationship("Business", backref="pay_page", uselist=False)
	gateway = relationship("PaymentGateway")


class BusinessPayPageUsernameHistory(Base):
	"""نام‌های کاربری قبلی برای redirect تا ۳۰ روز."""

	__tablename__ = "business_pay_page_username_history"
	__table_args__ = (
		Index("ix_pay_page_username_history_username", "username"),
		Index("ix_pay_page_username_history_business", "business_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	username: Mapped[str] = mapped_column(String(30), nullable=False)
	expires_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)

	business = relationship("Business")


class PublicPayPageReceipt(Base):
	"""توکن عمومی رسید واریز لینک پرداخت برای پیگیری مشتری و فروشنده."""

	__tablename__ = "public_pay_page_receipts"
	__table_args__ = (
		UniqueConstraint("wallet_transaction_id", name="uq_public_pay_page_receipts_tx"),
		Index("ix_public_pay_page_receipts_username", "username"),
	)

	token: Mapped[str] = mapped_column(String(48), primary_key=True)
	wallet_transaction_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("wallet_transactions.id", ondelete="CASCADE"), nullable=False
	)
	username: Mapped[str] = mapped_column(String(30), nullable=False)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


class PublicPayPageAbuseReport(Base):
	"""گزارش تخلف/فیشینگ صفحه واریز عمومی؛ در تنظیمات سیستم بررسی می‌شود."""

	__tablename__ = "public_pay_page_abuse_reports"
	__table_args__ = (
		Index("ix_pay_page_abuse_created_at", "created_at"),
		Index("ix_pay_page_abuse_status", "status"),
		Index("ix_pay_page_abuse_business", "business_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="SET NULL"), nullable=True
	)
	username: Mapped[str] = mapped_column(String(30), nullable=False)
	reason: Mapped[str] = mapped_column(String(40), nullable=False)
	details: Mapped[str] = mapped_column(Text, nullable=False)
	reporter_name: Mapped[str | None] = mapped_column(String(80), nullable=True)
	reporter_mobile: Mapped[str | None] = mapped_column(String(20), nullable=True)
	page_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
	ip_address: Mapped[str | None] = mapped_column(String(64), nullable=True)
	user_agent: Mapped[str | None] = mapped_column(String(400), nullable=True)
	status: Mapped[str] = mapped_column(String(20), nullable=False, default="new", server_default="new")
	admin_note: Mapped[str | None] = mapped_column(Text, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	reviewed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
	reviewed_by: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
	)

	business = relationship("Business")


class BusinessPayPageRequest(Base):
	"""درخواست لینک واریز اختصاصی (توکن‌دار) برای ارسال به مشتری."""

	__tablename__ = "business_pay_page_requests"
	__table_args__ = (
		Index("ix_pay_page_requests_business", "business_id"),
		Index("ix_pay_page_requests_page", "pay_page_id"),
		Index("ix_pay_page_requests_status", "status"),
	)

	token: Mapped[str] = mapped_column(String(48), primary_key=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False
	)
	pay_page_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("business_pay_pages.id", ondelete="CASCADE"), nullable=False
	)
	amount: Mapped[float | None] = mapped_column(Numeric(18, 2), nullable=True)
	amount_locked: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="0")
	payer_name: Mapped[str | None] = mapped_column(String(30), nullable=True)
	payer_mobile: Mapped[str | None] = mapped_column(String(20), nullable=True)
	payer_note: Mapped[str | None] = mapped_column(Text, nullable=True)
	created_by_user_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
	)
	status: Mapped[str] = mapped_column(String(20), nullable=False, default="open", server_default="open")
	paid_wallet_transaction_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("wallet_transactions.id", ondelete="SET NULL"), nullable=True
	)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	expires_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

	business = relationship("Business")
	pay_page = relationship("BusinessPayPage")
