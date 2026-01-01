from __future__ import annotations

from datetime import datetime
from sqlalchemy import String, Integer, DateTime, Enum as SQLEnum, ForeignKey, Numeric, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship
from adapters.db.session import Base
import enum


class AIInvoiceType(str, enum.Enum):
    SUBSCRIPTION = "subscription"
    USAGE = "usage"
    RENEWAL = "renewal"


class AIInvoiceStatus(str, enum.Enum):
    ISSUED = "issued"
    PAID = "paid"
    CANCELED = "canceled"


class AIInvoice(Base):
    __tablename__ = "ai_invoices"
    __table_args__ = (
        UniqueConstraint('code', name='uq_ai_invoices_code'),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    
    # اشتراک (nullable برای usage invoices)
    subscription_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("user_ai_subscriptions.id", ondelete="SET NULL"), nullable=True, index=True)
    business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
    plan_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("ai_plans.id", ondelete="SET NULL"), nullable=True, index=True)
    
    # اطلاعات صورتحساب
    invoice_type: Mapped[str] = mapped_column(
        String(50),
        nullable=False
    )
    code: Mapped[str] = mapped_column(String(50), nullable=False, unique=True, index=True)
    total: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False)
    currency_id: Mapped[int] = mapped_column(Integer, ForeignKey("currencies.id", ondelete="RESTRICT"), nullable=False)
    
    # وضعیت
    status: Mapped[str] = mapped_column(
        String(50),
        nullable=False,
        default=AIInvoiceStatus.ISSUED.value
    )
    issued_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=datetime.utcnow)
    paid_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    
    # پرداخت
    wallet_transaction_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("wallet_transactions.id", ondelete="RESTRICT"), nullable=True, index=True)
    document_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("documents.id", ondelete="SET NULL"), nullable=True, index=True)
    
    # زمان‌بندی
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
    
    # Relationships
    subscription = relationship("UserAISubscription", back_populates="invoices")
    business = relationship("Business", backref="ai_invoices")
    plan = relationship("AIPlan", back_populates="invoices")
    wallet_transaction = relationship("WalletTransaction", foreign_keys=[wallet_transaction_id])
    document = relationship("Document", foreign_keys=[document_id])

