from __future__ import annotations

from datetime import datetime

from sqlalchemy import String, Integer, DateTime, ForeignKey, UniqueConstraint, Boolean
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class PettyCash(Base):
	__tablename__ = "petty_cash"
	__table_args__ = (
		UniqueConstraint('business_id', 'code', name='uq_petty_cash_business_code'),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)

	# مشخصات
	name: Mapped[str] = mapped_column(String(255), nullable=False, index=True, comment="نام تنخواه گردان")
	code: Mapped[str | None] = mapped_column(String(50), nullable=True, index=True, comment="کد یکتا در هر کسب‌وکار (اختیاری)")
	description: Mapped[str | None] = mapped_column(String(500), nullable=True)

	# تنظیمات
	currency_id: Mapped[int] = mapped_column(Integer, ForeignKey("currencies.id", ondelete="RESTRICT"), nullable=False, index=True)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="1")
	is_default: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="0")

	# زمان بندی
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	# روابط
	business = relationship("Business", backref="petty_cash")
	currency = relationship("Currency", backref="petty_cash")
