from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class ProductBundle(Base):
    """یک الگوی ورود سریع چند کالا به فاکتور؛ بدون قیمت و موجودی مستقل."""

    __tablename__ = "product_bundles"
    __table_args__ = (
        UniqueConstraint("business_id", "name", name="uq_product_bundles_business_name"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("businesses.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_active: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default="true", index=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        nullable=False,
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
    )

    items: Mapped[list[ProductBundleItem]] = relationship(
        "ProductBundleItem",
        back_populates="bundle",
        cascade="all, delete-orphan",
        order_by="ProductBundleItem.line_order",
        lazy="selectin",
    )


class ProductBundleItem(Base):
    """کالا و تعداد آن در یک Bundle."""

    __tablename__ = "product_bundle_items"
    __table_args__ = (
        UniqueConstraint("bundle_id", "product_id", name="uq_product_bundle_items_product"),
        UniqueConstraint("bundle_id", "line_order", name="uq_product_bundle_items_line_order"),
        CheckConstraint("quantity > 0", name="ck_product_bundle_items_quantity_positive"),
        CheckConstraint("line_order > 0", name="ck_product_bundle_items_line_order_positive"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    bundle_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("product_bundles.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    product_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("products.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
    )
    quantity: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False)
    line_order: Mapped[int] = mapped_column(Integer, nullable=False)

    bundle: Mapped[ProductBundle] = relationship("ProductBundle", back_populates="items")
    product = relationship("Product", lazy="joined")
