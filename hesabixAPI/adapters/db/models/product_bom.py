from __future__ import annotations

from datetime import datetime

from sqlalchemy import (
    String,
    Integer,
    DateTime,
    Text,
    ForeignKey,
    UniqueConstraint,
    Boolean,
    Numeric,
    Date,
    Enum as SQLEnum,
)
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class BomStatus(str):
    DRAFT = "draft"
    APPROVED = "approved"
    ARCHIVED = "archived"


class ProductBOM(Base):
    """
    سرشاخه فرمول تولید (BOM)
    """

    __tablename__ = "product_boms"
    __table_args__ = (
        UniqueConstraint("business_id", "product_id", "version", name="uq_product_bom_version_per_product"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
    product_id: Mapped[int] = mapped_column(Integer, ForeignKey("products.id", ondelete="CASCADE"), nullable=False, index=True)

    version: Mapped[str] = mapped_column(String(64), nullable=False, comment="نسخه فرمول")
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    is_default: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False, index=True)

    effective_from: Mapped[Date | None] = mapped_column(Date, nullable=True)
    effective_to: Mapped[Date | None] = mapped_column(Date, nullable=True)

    yield_percent: Mapped[float | None] = mapped_column(Numeric(5, 2), nullable=True, comment="بازده کل")
    wastage_percent: Mapped[float | None] = mapped_column(Numeric(5, 2), nullable=True, comment="پرت کل")

    status: Mapped[str] = mapped_column(String(16), default=BomStatus.DRAFT, nullable=False, index=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)

    created_by: Mapped[int | None] = mapped_column(Integer, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)


class ProductBOMItem(Base):
    """
    اقلام مصرفی BOM
    """

    __tablename__ = "product_bom_items"
    __table_args__ = (
        UniqueConstraint("bom_id", "line_no", name="uq_bom_items_line"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    bom_id: Mapped[int] = mapped_column(Integer, ForeignKey("product_boms.id", ondelete="CASCADE"), nullable=False, index=True)

    line_no: Mapped[int] = mapped_column(Integer, nullable=False)
    component_product_id: Mapped[int] = mapped_column(Integer, ForeignKey("products.id", ondelete="RESTRICT"), nullable=False, index=True)

    qty_per: Mapped[float] = mapped_column(Numeric(18, 6), nullable=False, comment="مقدار برای تولید 1 واحد")
    uom: Mapped[str | None] = mapped_column(String(32), nullable=True)
    wastage_percent: Mapped[float | None] = mapped_column(Numeric(5, 2), nullable=True)

    is_optional: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    substitute_group: Mapped[str | None] = mapped_column(String(64), nullable=True)

    suggested_warehouse_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("warehouses.id", ondelete="SET NULL"), nullable=True)


class ProductBOMOutput(Base):
    """
    خروجی‌های BOM (محصول اصلی و جانبی)
    """

    __tablename__ = "product_bom_outputs"
    __table_args__ = (
        UniqueConstraint("bom_id", "line_no", name="uq_bom_outputs_line"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    bom_id: Mapped[int] = mapped_column(Integer, ForeignKey("product_boms.id", ondelete="CASCADE"), nullable=False, index=True)

    line_no: Mapped[int] = mapped_column(Integer, nullable=False)
    output_product_id: Mapped[int] = mapped_column(Integer, ForeignKey("products.id", ondelete="RESTRICT"), nullable=False, index=True)
    ratio: Mapped[float] = mapped_column(Numeric(18, 6), nullable=False, comment="نسبت خروجی نسبت به 1 واحد")
    uom: Mapped[str | None] = mapped_column(String(32), nullable=True)


class ProductBOMOperation(Base):
    """
    عملیات/سربار BOM
    """

    __tablename__ = "product_bom_operations"
    __table_args__ = (
        UniqueConstraint("bom_id", "line_no", name="uq_bom_operations_line"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    bom_id: Mapped[int] = mapped_column(Integer, ForeignKey("product_boms.id", ondelete="CASCADE"), nullable=False, index=True)

    line_no: Mapped[int] = mapped_column(Integer, nullable=False)
    operation_name: Mapped[str] = mapped_column(String(255), nullable=False)
    cost_fixed: Mapped[float | None] = mapped_column(Numeric(18, 2), nullable=True)
    cost_per_unit: Mapped[float | None] = mapped_column(Numeric(18, 6), nullable=True)
    cost_uom: Mapped[str | None] = mapped_column(String(32), nullable=True)
    work_center: Mapped[str | None] = mapped_column(String(128), nullable=True)


