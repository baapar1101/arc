from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from sqlalchemy import (
    String,
    Integer,
    DateTime,
    ForeignKey,
    UniqueConstraint,
    Boolean,
    Numeric,
)
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class PriceList(Base):
    __tablename__ = "price_lists"
    __table_args__ = (
        UniqueConstraint("business_id", "name", name="uq_price_lists_business_name"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
    name: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    currency_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("currencies.id", ondelete="RESTRICT"), nullable=True, index=True)
    default_unit_id: Mapped[int | None] = mapped_column(Integer, nullable=True, index=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)


class PriceItem(Base):
    __tablename__ = "price_items"
    __table_args__ = (
        UniqueConstraint("price_list_id", "product_id", "unit_id", "tier_name", "min_qty", name="uq_price_items_unique_tier"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    price_list_id: Mapped[int] = mapped_column(Integer, ForeignKey("price_lists.id", ondelete="CASCADE"), nullable=False, index=True)
    product_id: Mapped[int] = mapped_column(Integer, ForeignKey("products.id", ondelete="CASCADE"), nullable=False, index=True)
    unit_id: Mapped[int | None] = mapped_column(Integer, nullable=True, index=True)
    currency_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("currencies.id", ondelete="RESTRICT"), nullable=True, index=True)
    tier_name: Mapped[str] = mapped_column(String(64), nullable=False, comment="نام پله قیمت (تکی/عمده/همکار/...)" )
    min_qty: Mapped[Decimal] = mapped_column(Numeric(18, 3), nullable=False, default=0)
    price: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)


