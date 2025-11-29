from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from sqlalchemy import String, Integer, DateTime, ForeignKey, UniqueConstraint, Numeric, Boolean, Text, JSON
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class ZohalService(Base):
	__tablename__ = "zohal_services"
	__table_args__ = (
		UniqueConstraint('service_code', name='uq_zohal_services_code'),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	
	# اطلاعات سرویس
	service_code: Mapped[str] = mapped_column(String(100), nullable=False, unique=True, index=True)  # مثل "card_inquiry"
	service_path: Mapped[str] = mapped_column(String(255), nullable=False)  # "/services/inquiry/card_inquiry"
	service_name: Mapped[str] = mapped_column(String(255), nullable=False)  # "استعلام نام صاحب کارت"
	service_category: Mapped[str] = mapped_column(String(50), nullable=False, index=True)  # "بانکی", "احراز هویت", ...
	description: Mapped[str | None] = mapped_column(Text, nullable=True)
	
	# وضعیت و قیمت
	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	base_price: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)  # قیمت هر درخواست
	currency_id: Mapped[int] = mapped_column(Integer, ForeignKey("currencies.id", ondelete="RESTRICT"), nullable=False, index=True)
	
	# ساختار درخواست و پاسخ (از OpenAPI)
	request_schema: Mapped[dict | None] = mapped_column(JSON, nullable=True)  # ساختار فیلدهای ورودی
	response_schema: Mapped[dict | None] = mapped_column(JSON, nullable=True)  # ساختار پاسخ
	
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
	
	# روابط
	currency = relationship("Currency", backref="zohal_services")
	service_logs = relationship("ZohalServiceLog", back_populates="service")


class ZohalServiceLog(Base):
	__tablename__ = "zohal_service_logs"
	__table_args__ = (
		# ایندکس‌ها از طریق migration اضافه می‌شود
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	service_id: Mapped[int] = mapped_column(Integer, ForeignKey("zohal_services.id", ondelete="RESTRICT"), nullable=False, index=True)
	user_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)
	
	# داده‌های درخواست و پاسخ
	request_data: Mapped[dict] = mapped_column(JSON, nullable=False)  # داده‌های ارسالی به زحل
	response_data: Mapped[dict] = mapped_column(JSON, nullable=False)  # پاسخ دریافتی از زحل
	
	# وضعیت
	status: Mapped[str] = mapped_column(String(20), nullable=False, default="pending")  # pending, success, failed, error
	error_message: Mapped[str | None] = mapped_column(Text, nullable=True)
	
	# اطلاعات مالی
	amount_charged: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)  # مبلغ کسر شده
	currency_id: Mapped[int] = mapped_column(Integer, ForeignKey("currencies.id", ondelete="RESTRICT"), nullable=False, index=True)
	
	# پیوند به تراکنش و سند
	wallet_transaction_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("wallet_transactions.id", ondelete="SET NULL"), nullable=True, index=True)
	document_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("documents.id", ondelete="SET NULL"), nullable=True, index=True)
	
	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False, index=True)
	
	# روابط
	business = relationship("Business", backref="zohal_service_logs")
	service = relationship("ZohalService", back_populates="service_logs")
	user = relationship("User", backref="zohal_service_logs")
	currency = relationship("Currency", backref="zohal_service_logs")
	wallet_transaction = relationship("WalletTransaction", backref="zohal_service_logs")
	document = relationship("Document", backref="zohal_service_logs")

