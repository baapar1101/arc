from __future__ import annotations

from datetime import datetime
from sqlalchemy import String, Integer, DateTime, ForeignKey, Boolean, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class PaymentGateway(Base):
	__tablename__ = "payment_gateways"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)

	# zarinpal | parsian | ...
	provider: Mapped[str] = mapped_column(String(50), nullable=False)
	display_name: Mapped[str] = mapped_column(String(100), nullable=False)

	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
	is_sandbox: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

	# JSON string: provider-specific fields (merchant_id, terminal_id, callback_url, fee_percent, etc.)
	config_json: Mapped[str | None] = mapped_column(Text, nullable=True)

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	# relationships
	business_links = relationship("BusinessPaymentGateway", back_populates="gateway", cascade="all, delete-orphan")


class BusinessPaymentGateway(Base):
	__tablename__ = "business_payment_gateways"

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	gateway_id: Mapped[int] = mapped_column(Integer, ForeignKey("payment_gateways.id", ondelete="CASCADE"), nullable=False, index=True)

	is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

	created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
	updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

	business = relationship("Business", backref="payment_gateways")
	gateway = relationship("PaymentGateway", back_populates="business_links")



