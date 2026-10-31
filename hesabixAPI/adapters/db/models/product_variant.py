from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from sqlalchemy import (
    BigInteger,
    Boolean,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    UniqueConstraint,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class ProductVariantDimension(Base):
    """ویژگی select اثرگذار بر موجودی یک کالا. سقف تعداد در سرویس اعمال می‌شود."""

    __tablename__ = "product_variant_dimensions"
    __table_args__ = (
        UniqueConstraint("product_id", "attribute_id", name="uq_product_variant_dimensions_product_attr"),
        Index("ix_product_variant_dimensions_business_product", "business_id", "product_id"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
    )
    product_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("products.id", ondelete="CASCADE"), nullable=False, index=True
    )
    attribute_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("product_attributes.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    is_required: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)


class ProductVariant(Base):
    """ترکیب واقعی قابل فروش/انبارش برای کالای فله‌ای."""

    __tablename__ = "product_variants"
    __table_args__ = (
        UniqueConstraint("product_id", "combination_key", name="uq_product_variants_product_combination"),
        UniqueConstraint("id", "business_id", "product_id", name="uq_product_variants_id_business_product"),
        Index("ix_product_variants_business_product_active", "business_id", "product_id", "is_active"),
        Index(
            "uq_product_variants_business_code",
            "business_id",
            "code",
            unique=True,
            sqlite_where=text("code IS NOT NULL"),
            postgresql_where=text("code IS NOT NULL"),
        ),
        Index(
            "uq_product_variants_business_barcode",
            "business_id",
            "barcode",
            unique=True,
            sqlite_where=text("barcode IS NOT NULL"),
            postgresql_where=text("barcode IS NOT NULL"),
        ),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
    )
    product_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("products.id", ondelete="CASCADE"), nullable=False, index=True
    )
    code: Mapped[str | None] = mapped_column(String(64), nullable=True)
    display_title: Mapped[str | None] = mapped_column(String(255), nullable=True)
    barcode: Mapped[str | None] = mapped_column(String(128), nullable=True)
    sales_price: Mapped[Decimal | None] = mapped_column(Numeric(18, 2), nullable=True)
    purchase_price: Mapped[Decimal | None] = mapped_column(Numeric(18, 2), nullable=True)
    combination_key: Mapped[str] = mapped_column(String(512), nullable=False)
    row_version: Mapped[int] = mapped_column(BigInteger, nullable=False, default=1)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
    )


class ProductVariantValue(Base):
    """مقدار ویژگی یک ترکیب؛ هویت فقط با ID است نه عنوان فارسی."""

    __tablename__ = "product_variant_values"
    __table_args__ = (
        UniqueConstraint("variant_id", "option_id", name="uq_product_variant_values_variant_option"),
    )

    variant_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("product_variants.id", ondelete="CASCADE"), primary_key=True
    )
    attribute_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("product_attributes.id", ondelete="RESTRICT"), primary_key=True
    )
    business_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
    )
    option_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("product_attribute_options.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
