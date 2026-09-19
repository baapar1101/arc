from __future__ import annotations

from datetime import datetime

from sqlalchemy import (
    String,
    Integer,
    DateTime,
    Text,
    ForeignKey,
    Boolean,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class ProductSupplier(Base):
    """تأمین‌کنندهٔ مرتبط با یک کالا (چندتایی برای هر محصول)."""

    __tablename__ = "product_suppliers"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
    )
    product_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("products.id", ondelete="CASCADE"), nullable=False, index=True
    )
    person_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("persons.id", ondelete="SET NULL"), nullable=True, index=True
    )

    name: Mapped[str] = mapped_column(String(255), nullable=False, comment="نام/عنوان تأمین‌کننده")
    website: Mapped[str | None] = mapped_column(String(512), nullable=True)
    phone: Mapped[str | None] = mapped_column(String(64), nullable=True)
    email: Mapped[str | None] = mapped_column(String(255), nullable=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_preferred: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False, server_default="0")
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")

    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
    )

    social_contacts: Mapped[list["ProductSupplierSocialContact"]] = relationship(
        "ProductSupplierSocialContact",
        back_populates="supplier",
        cascade="all, delete-orphan",
        order_by="ProductSupplierSocialContact.sort_order",
    )
    person = relationship("Person", foreign_keys=[person_id], lazy="select")


class ProductSupplierSocialContact(Base):
    """راه ارتباط پیام‌رسان / شبکه اجتماعی برای تأمین‌کنندهٔ کالا."""

    __tablename__ = "product_supplier_social_contacts"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    supplier_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("product_suppliers.id", ondelete="CASCADE"), nullable=False, index=True
    )
    platform_key: Mapped[str] = mapped_column(String(64), nullable=False)
    custom_label: Mapped[str | None] = mapped_column(String(128), nullable=True)
    value: Mapped[str] = mapped_column(Text, nullable=False)
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")

    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
    )

    supplier: Mapped["ProductSupplier"] = relationship("ProductSupplier", back_populates="social_contacts")
