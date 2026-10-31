from __future__ import annotations

from datetime import datetime

from sqlalchemy import (
    BigInteger,
    Boolean,
    DateTime,
    ForeignKey,
    Integer,
    String,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class ProductAttributeOption(Base):
    """گزینه پایدار ویژگی select؛ JSON عنوان‌ها همچنان برای سازگاری نگه داشته می‌شود."""

    __tablename__ = "product_attribute_options"
    __table_args__ = (
        UniqueConstraint("attribute_id", "code", name="uq_product_attribute_options_attr_code"),
        UniqueConstraint(
            "attribute_id",
            "normalized_label",
            name="uq_product_attribute_options_attr_normalized",
        ),
        UniqueConstraint(
            "id",
            "business_id",
            "attribute_id",
            name="uq_product_attribute_options_id_business_attr",
        ),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
    )
    attribute_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("product_attributes.id", ondelete="CASCADE"), nullable=False, index=True
    )
    code: Mapped[str] = mapped_column(String(64), nullable=False)
    label: Mapped[str] = mapped_column(String(255), nullable=False)
    normalized_label: Mapped[str] = mapped_column(String(255), nullable=False)
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
    )
