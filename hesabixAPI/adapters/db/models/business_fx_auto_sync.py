from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from sqlalchemy import (
	Boolean,
	DateTime,
	ForeignKey,
	Integer,
	Numeric,
	String,
	Text,
	UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class BusinessFxAutoSyncSettings(Base):
	"""زمان‌بندی خودکار ثبت نرخ تسعیر از اسنپ‌شات مرکزی برای یک کسب‌وکار."""

	__tablename__ = "business_fx_auto_sync_settings"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, unique=True, index=True
	)
	enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	schedule_mode: Mapped[str] = mapped_column(
		String(20), nullable=False, default="interval", comment="interval | daily_times"
	)
	interval_hours: Mapped[int | None] = mapped_column(Integer, nullable=True, default=6)
	daily_times: Mapped[list | None] = mapped_column(JSONB, nullable=True)  # ["09:00","18:00"]
	timezone: Mapped[str | None] = mapped_column(String(64), nullable=True)
	skip_if_unchanged: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	min_change_percent: Mapped[Decimal] = mapped_column(
		Numeric(10, 6), nullable=False, default=Decimal("0.01"), comment="حداقل درصد تغییر برای ثبت دوباره"
	)
	block_if_stale: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	stale_after_hours: Mapped[int] = mapped_column(Integer, nullable=False, default=24)
	updated_by_user_id: Mapped[int | None] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True
	)
	last_run_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
	last_run_status: Mapped[str | None] = mapped_column(String(32), nullable=True)
	last_run_message: Mapped[str | None] = mapped_column(Text, nullable=True)
	next_run_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True, index=True)
	created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)

	rules = relationship(
		"BusinessFxAutoSyncCurrencyRule",
		back_populates="settings",
		cascade="all, delete-orphan",
		lazy="selectin",
	)


class BusinessFxAutoSyncCurrencyRule(Base):
	"""آفست per ارز برای به‌روزرسانی خودکار نرخ تسعیر."""

	__tablename__ = "business_fx_auto_sync_currency_rules"
	__table_args__ = (
		UniqueConstraint("business_id", "currency_id", name="uq_fx_auto_sync_rule_business_currency"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
	)
	settings_id: Mapped[int] = mapped_column(
		Integer,
		ForeignKey("business_fx_auto_sync_settings.id", ondelete="CASCADE"),
		nullable=False,
		index=True,
	)
	currency_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("currencies.id", ondelete="CASCADE"), nullable=False, index=True
	)
	enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	offset_type: Mapped[str] = mapped_column(
		String(16), nullable=False, default="none", comment="none | percent | amount"
	)
	offset_direction: Mapped[str] = mapped_column(
		String(8), nullable=False, default="up", comment="up | down"
	)
	offset_value: Mapped[Decimal] = mapped_column(Numeric(24, 10), nullable=False, default=Decimal(0))
	created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)

	settings = relationship("BusinessFxAutoSyncSettings", back_populates="rules")
	currency = relationship("Currency", lazy="joined")
