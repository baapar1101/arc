from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from enum import Enum

from sqlalchemy import (
    String,
    Integer,
    DateTime,
    Text,
    ForeignKey,
    UniqueConstraint,
    Boolean,
    Numeric,
    Enum as SQLEnum,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class ProductItemType(str, Enum):
    PRODUCT = "کالا"
    SERVICE = "خدمت"


class Product(Base):
    """
    موجودیت کالا/خدمت در سطح هر کسب‌وکار
    - کد دستی/اتوماتیک یکتا در هر کسب‌وکار
    - پشتیبانی از مالیات فروش/خرید، کنترل موجودی و واحدها
    - اتصال به دسته‌بندی‌ها و ویژگی‌ها (ویژگی‌ها از طریق جدول لینک)
    """

    __tablename__ = "products"
    __table_args__ = (
        UniqueConstraint("business_id", "code", name="uq_products_business_code"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)

    item_type: Mapped[ProductItemType] = mapped_column(
        SQLEnum(ProductItemType, values_callable=lambda obj: [e.value for e in obj], name="product_item_type_enum"),
        nullable=False,
        default=ProductItemType.PRODUCT,
        comment="نوع آیتم (کالا/خدمت)",
    )

    code: Mapped[str] = mapped_column(String(64), nullable=False, comment="کد یکتا در هر کسب‌وکار")
    name: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)

    # دسته‌بندی (اختیاری)
    category_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("categories.id", ondelete="SET NULL"), nullable=True, index=True)

    # واحدها
    main_unit: Mapped[str | None] = mapped_column(String(32), nullable=True, index=True, comment="واحد اصلی شمارش")
    secondary_unit: Mapped[str | None] = mapped_column(String(32), nullable=True, index=True, comment="واحد فرعی شمارش")
    unit_conversion_factor: Mapped[Decimal | None] = mapped_column(Numeric(18, 6), nullable=True)

    # قیمت‌های پایه (نمایشی)
    base_sales_price: Mapped[Decimal | None] = mapped_column(Numeric(18, 2), nullable=True)
    base_sales_note: Mapped[str | None] = mapped_column(Text, nullable=True)
    base_purchase_price: Mapped[Decimal | None] = mapped_column(Numeric(18, 2), nullable=True)
    base_purchase_note: Mapped[str | None] = mapped_column(Text, nullable=True)

    # کنترل موجودی
    track_inventory: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    reorder_point: Mapped[int | None] = mapped_column(Integer, nullable=True)
    min_order_qty: Mapped[int | None] = mapped_column(Integer, nullable=True)
    lead_time_days: Mapped[int | None] = mapped_column(Integer, nullable=True)

    # مالیات
    is_sales_taxable: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    is_purchase_taxable: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    sales_tax_rate: Mapped[Decimal | None] = mapped_column(Numeric(5, 2), nullable=True)
    purchase_tax_rate: Mapped[Decimal | None] = mapped_column(Numeric(5, 2), nullable=True)
    tax_type_id: Mapped[int | None] = mapped_column(Integer, nullable=True, index=True)
    tax_code: Mapped[str | None] = mapped_column(String(100), nullable=True)
    tax_unit_id: Mapped[int | None] = mapped_column(Integer, nullable=True, index=True)

    # عکس کالا
    image_file_id: Mapped[str | None] = mapped_column(String(36), ForeignKey("file_storage.id", ondelete="SET NULL"), nullable=True, index=True)

    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    # Relationships
    image_file = relationship("FileStorage", foreign_keys=[image_file_id], lazy="select")


