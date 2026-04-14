from __future__ import annotations

from datetime import datetime

from sqlalchemy import String, Integer, DateTime, ForeignKey, UniqueConstraint, Boolean
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class BankAccount(Base):
	__tablename__ = "bank_accounts"
	__table_args__ = (
		UniqueConstraint('business_id', 'code', name='uq_bank_accounts_business_code'),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)

	# اطلاعات اصلی/نمایشی
	code: Mapped[str | None] = mapped_column(String(50), nullable=True, index=True, comment="کد یکتا در هر کسب‌وکار (اختیاری)")
	name: Mapped[str] = mapped_column(String(255), nullable=False, index=True, comment="نام حساب")
	description: Mapped[str | None] = mapped_column(String(500), nullable=True)

	# اطلاعات بانکی
	branch: Mapped[str | None] = mapped_column(String(255), nullable=True)
	account_number: Mapped[str | None] = mapped_column(String(50), nullable=True)
	sheba_number: Mapped[str | None] = mapped_column(String(30), nullable=True)
	card_number: Mapped[str | None] = mapped_column(String(20), nullable=True)
	owner_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
	pos_number: Mapped[str | None] = mapped_column(String(50), nullable=True)
	payment_id: Mapped[str | None] = mapped_column(String(100), nullable=True)

	# تنظیمات
	currency_id: Mapped[int] = mapped_column(Integer, ForeignKey("currencies.id", ondelete="RESTRICT"), nullable=False, index=True)
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True, server_default="1")
	is_default: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="0")

	# زمان‌بندی
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	# روابط
	business = relationship("Business", backref="bank_accounts")
	currency = relationship("Currency", backref="bank_accounts")


