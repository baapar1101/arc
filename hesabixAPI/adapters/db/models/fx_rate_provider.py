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
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class FxRateProvider(Base):
	"""ارائه‌دهنده نرخ ارز در سطح سیستم (کلید و تنظیمات متمرکز)."""

	__tablename__ = "fx_rate_providers"
	__table_args__ = (UniqueConstraint("code", name="uq_fx_rate_providers_code"),)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	code: Mapped[str] = mapped_column(String(50), nullable=False, index=True)
	display_name: Mapped[str] = mapped_column(String(120), nullable=False)
	api_base_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
	api_key_encrypted: Mapped[str | None] = mapped_column(Text, nullable=True)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	fetch_interval_seconds: Mapped[int] = mapped_column(Integer, nullable=False, default=900)
	config_json: Mapped[str | None] = mapped_column(Text, nullable=True)
	last_fetch_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
	last_fetch_status: Mapped[str | None] = mapped_column(String(32), nullable=True)
	last_fetch_error: Mapped[str | None] = mapped_column(Text, nullable=True)
	last_fetch_http_status: Mapped[int | None] = mapped_column(Integer, nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)

	rates = relationship("FxGlobalRate", back_populates="provider", cascade="all, delete-orphan")


class FxGlobalRate(Base):
	"""اسنپ‌شات مرکزی آخرین نرخ هر نماد از یک ارائه‌دهنده."""

	__tablename__ = "fx_global_rates"
	__table_args__ = (
		UniqueConstraint("provider_id", "symbol", name="uq_fx_global_rates_provider_symbol"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	provider_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("fx_rate_providers.id", ondelete="CASCADE"), nullable=False, index=True
	)
	symbol: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
	currency_code: Mapped[str] = mapped_column(String(16), nullable=False, index=True)
	price_quote: Mapped[Decimal] = mapped_column(Numeric(24, 10), nullable=False)
	quote_unit: Mapped[str] = mapped_column(String(16), nullable=False, default="IRT")
	price_irr: Mapped[Decimal] = mapped_column(
		Numeric(24, 10), nullable=False, comment="۱ واحد ارز = چند ریال ایران"
	)
	name_fa: Mapped[str | None] = mapped_column(String(120), nullable=True)
	name_en: Mapped[str | None] = mapped_column(String(120), nullable=True)
	source_time: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
	fetched_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
	raw_json: Mapped[str | None] = mapped_column(Text, nullable=True)

	provider = relationship("FxRateProvider", back_populates="rates")
