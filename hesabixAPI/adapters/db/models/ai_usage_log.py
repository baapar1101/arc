from __future__ import annotations

from datetime import datetime
from sqlalchemy import String, Integer, DateTime, Enum as SQLEnum, ForeignKey, Numeric, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship
from adapters.db.session import Base
import enum


class PaymentMethod(str, enum.Enum):
    FREE = "free"
    SUBSCRIPTION = "subscription"
    WALLET = "wallet"


class AIUsageLog(Base):
    __tablename__ = "ai_usage_logs"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    
    # کاربر و کسب‌وکار
    user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    business_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=True, index=True)
    
    # اشتراک و صورتحساب
    subscription_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("user_ai_subscriptions.id", ondelete="SET NULL"), nullable=True, index=True)
    invoice_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("ai_invoices.id", ondelete="SET NULL"), nullable=True, index=True)
    
    # اطلاعات استفاده
    provider: Mapped[str] = mapped_column(String(50), nullable=False)
    model: Mapped[str] = mapped_column(String(100), nullable=False)
    input_tokens: Mapped[int] = mapped_column(Integer, nullable=False)
    output_tokens: Mapped[int] = mapped_column(Integer, nullable=False)
    cost: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False, default=0)
    
    # روش پرداخت
    payment_method: Mapped[str] = mapped_column(
        String(50),
        nullable=False
    )
    wallet_transaction_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("wallet_transactions.id", ondelete="RESTRICT"), nullable=True, index=True)
    document_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("documents.id", ondelete="SET NULL"), nullable=True, index=True)
    
    # Context (JSON)
    context: Mapped[str | None] = mapped_column(Text, nullable=True)  # JSON
    
    # زمان‌بندی
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False, index=True)
    
    # Relationships
    user = relationship("User", backref="ai_usage_logs")
    business = relationship("Business", backref="ai_usage_logs")
    subscription = relationship("UserAISubscription", back_populates="usage_logs")
    invoice = relationship("AIInvoice", backref="usage_logs")
    wallet_transaction = relationship("WalletTransaction", foreign_keys=[wallet_transaction_id])
    document = relationship("Document", foreign_keys=[document_id])

