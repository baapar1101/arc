from __future__ import annotations

from datetime import datetime

from sqlalchemy import BigInteger, Boolean, DateTime, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class TaxProviderCredential(Base):
    """System-wide credentials and defaults for a tax submission provider."""

    __tablename__ = "tax_provider_credentials"
    __table_args__ = (UniqueConstraint("provider_code", name="uq_tax_provider_credentials_provider"),)

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    provider_code: Mapped[str] = mapped_column(String(40), nullable=False, index=True)
    display_name: Mapped[str] = mapped_column(String(120), nullable=False)
    base_url: Mapped[str] = mapped_column(String(500), nullable=False)
    username_encrypted: Mapped[str | None] = mapped_column(Text, nullable=True)
    password_encrypted: Mapped[str | None] = mapped_column(Text, nullable=True)
    broker_code: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    contract_duration_days: Mapped[int] = mapped_column(Integer, nullable=False, default=365, server_default="365")
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="false")
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow)


class BusinessTaxProviderAccount(Base):
    """A taxpayer account provisioned through a broker for one business."""

    __tablename__ = "business_tax_provider_accounts"
    __table_args__ = (
        UniqueConstraint("business_id", "provider_code", name="uq_business_tax_provider_account"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
    provider_code: Mapped[str] = mapped_column(String(40), nullable=False, index=True)
    status: Mapped[str] = mapped_column(String(32), nullable=False, default="not_connected", server_default="not_connected")
    cartable_id: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    memory_id: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    memory_number: Mapped[str | None] = mapped_column(String(128), nullable=True)
    consented_by_user_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    consented_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    username_encrypted: Mapped[str | None] = mapped_column(Text, nullable=True)
    password_encrypted: Mapped[str | None] = mapped_column(Text, nullable=True)
    access_token_encrypted: Mapped[str | None] = mapped_column(Text, nullable=True)
    token_expires_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    last_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    registered_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    last_synced_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow)
