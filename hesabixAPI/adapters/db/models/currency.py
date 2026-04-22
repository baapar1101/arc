from __future__ import annotations

from datetime import datetime

from sqlalchemy import String, Integer, DateTime, ForeignKey, UniqueConstraint, Boolean, SmallInteger
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class Currency(Base):
	__tablename__ = "currencies"
	__table_args__ = (
		UniqueConstraint('name', name='uq_currencies_name'),
		UniqueConstraint('code', name='uq_currencies_code'),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	name: Mapped[str] = mapped_column(String(100), nullable=False, index=True)
	title: Mapped[str] = mapped_column(String(100), nullable=False)
	symbol: Mapped[str] = mapped_column(String(16), nullable=False)
	code: Mapped[str] = mapped_column(String(16), nullable=False)  # نام کوتاه
	decimal_places: Mapped[int] = mapped_column(
		SmallInteger,
		nullable=False,
		default=2,
		server_default="2",
		comment="تعداد اعشار مبلغ (۰=بدون اعشار، ۲=دو رقم اعشار)",
	)
	round_monetary_amounts: Mapped[bool] = mapped_column(
		Boolean,
		nullable=False,
		default=True,
		server_default="1",
		comment="گرد کردن مبالغ در محاسبات به decimal_places",
	)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	# Relationships
	businesses = relationship("Business", secondary="business_currencies", back_populates="currencies")
	documents = relationship("Document", back_populates="currency")


class BusinessCurrency(Base):
	__tablename__ = "business_currencies"
	__table_args__ = (
		UniqueConstraint('business_id', 'currency_id', name='uq_business_currencies_business_currency'),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	currency_id: Mapped[int] = mapped_column(Integer, ForeignKey("currencies.id", ondelete="CASCADE"), nullable=False, index=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)


