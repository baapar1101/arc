from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from sqlalchemy import Integer, DateTime, ForeignKey, Text, Numeric
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class BusinessCurrencyRate(Base):
	"""نرخ تسعیر: ۱ واحد ارز `currency_id` (غیر پایه) معادل `rate` واحد از ارز اصلی کسب‌وکار است."""

	__tablename__ = "business_currency_rates"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
	)
	currency_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("currencies.id", ondelete="RESTRICT"), nullable=False, index=True
	)
	effective_at: Mapped[datetime] = mapped_column(
		DateTime(timezone=True), nullable=False, index=True, comment="زمان مؤثر نرخ (چند نرخ در یک روز با زمان متفاوت)"
	)
	rate: Mapped[Decimal] = mapped_column(
		Numeric(24, 10), nullable=False, comment="۱ واحد ارز غیرپایه = rate × واحد پایه"
	)
	note: Mapped[str | None] = mapped_column(Text, nullable=True)
	created_by_user_id: Mapped[int] = mapped_column(
		Integer, ForeignKey("users.id", ondelete="RESTRICT"), nullable=False
	)
	created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)

	currency = relationship("Currency", lazy="joined")
	created_by = relationship("User", foreign_keys=[created_by_user_id])
