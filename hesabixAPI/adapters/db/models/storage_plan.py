from __future__ import annotations

from datetime import datetime
from typing import Optional
from decimal import Decimal

from sqlalchemy import String, Integer, DateTime, ForeignKey, UniqueConstraint, Numeric, Boolean, Text, JSON
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class StoragePlan(Base):
	__tablename__ = "storage_plans"
	__table_args__ = (
		UniqueConstraint("code", name="uq_storage_plans_code"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	name: Mapped[str] = mapped_column(String(200), nullable=False)
	code: Mapped[str] = mapped_column(String(100), nullable=False, index=True)
	storage_limit_gb: Mapped[float] = mapped_column(Numeric(10, 3), nullable=False)  # محدودیت حجم به گیگابایت
	period: Mapped[str] = mapped_column(String(20), nullable=False)  # monthly, yearly, lifetime
	period_months: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)  # تعداد ماه‌ها - برای lifetime = null
	price: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)  # قیمت کل پلن
	price_per_gb: Mapped[Optional[float]] = mapped_column(Numeric(18, 2), nullable=True)  # قیمت هر گیگابایت اضافی
	is_free: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	currency_id: Mapped[int] = mapped_column(Integer, ForeignKey("currencies.id", ondelete="RESTRICT"), nullable=False)
	description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
	grace_period_days: Mapped[int] = mapped_column(Integer, nullable=False, default=30)  # مدت مهلت بعد از انقضا قبل از حذف فایل‌ها

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	# Relationships
	currency = relationship("Currency", backref="storage_plans")
	subscriptions = relationship("BusinessStorageSubscription", back_populates="plan", cascade="all, delete-orphan")


class BusinessStorageSubscription(Base):
	__tablename__ = "business_storage_subscriptions"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	plan_id: Mapped[int] = mapped_column(Integer, ForeignKey("storage_plans.id", ondelete="RESTRICT"), nullable=False, index=True)
	status: Mapped[str] = mapped_column(String(20), nullable=False, default="active")  # active, expired, suspended, cancelled
	starts_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	ends_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)  # null برای پلن‌های lifetime
	auto_renew: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	grace_period_ends_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)  # محاسبه می‌شود: ends_at + grace_period_days

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	# Relationships
	business = relationship("Business", backref="storage_subscriptions")
	plan = relationship("StoragePlan", back_populates="subscriptions")
	invoices = relationship("StorageInvoice", back_populates="subscription", cascade="all, delete-orphan")
	usage_transactions = relationship("StorageUsageTransaction", back_populates="subscription")


class StorageInvoice(Base):
	__tablename__ = "storage_invoices"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	subscription_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("business_storage_subscriptions.id", ondelete="SET NULL"), nullable=True, index=True)
	code: Mapped[str] = mapped_column(String(50), nullable=False, index=True)
	invoice_type: Mapped[str] = mapped_column(String(20), nullable=False)  # subscription, over_usage, renewal
	total: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
	currency_id: Mapped[int] = mapped_column(Integer, ForeignKey("currencies.id", ondelete="RESTRICT"), nullable=False)
	status: Mapped[str] = mapped_column(String(20), nullable=False, default="issued")  # issued, paid, void, cancelled
	issued_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	paid_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
	wallet_transaction_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("wallet_transactions.id", ondelete="SET NULL"), nullable=True, index=True)
	extra_info: Mapped[Optional[dict]] = mapped_column(JSON, nullable=True)  # اطلاعات اضافی: usage_gb, over_usage_gb, etc.

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	# Relationships
	business = relationship("Business", backref="storage_invoices")
	subscription = relationship("BusinessStorageSubscription", back_populates="invoices")
	currency = relationship("Currency", backref="storage_invoices")
	wallet_transaction = relationship("WalletTransaction", backref="storage_invoices")


class StorageUsageTransaction(Base):
	__tablename__ = "storage_usage_transactions"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	file_storage_id: Mapped[Optional[str]] = mapped_column(String(36), ForeignKey("file_storage.id", ondelete="SET NULL"), nullable=True, index=True)
	usage_gb: Mapped[float] = mapped_column(Numeric(10, 6), nullable=False)  # حجم استفاده شده (با دقت بالا)
	transaction_type: Mapped[str] = mapped_column(String(20), nullable=False)  # upload, delete
	subscription_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("business_storage_subscriptions.id", ondelete="SET NULL"), nullable=True, index=True)
	invoice_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("storage_invoices.id", ondelete="SET NULL"), nullable=True, index=True)

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)

	# Relationships
	business = relationship("Business", backref="storage_usage_transactions")
	file_storage = relationship("FileStorage", backref="usage_transactions")
	subscription = relationship("BusinessStorageSubscription", back_populates="usage_transactions")
	invoice = relationship("StorageInvoice", backref="usage_transactions")

