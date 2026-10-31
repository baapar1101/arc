from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from sqlalchemy import (
    JSON,
    BigInteger,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class InvoiceItemLineVariantAllocation(Base):
    """تخصیص Variant به ردیف مالی فاکتور؛ مقدار در واحد همان ردیف است."""

    __tablename__ = "invoice_item_line_variant_allocations"
    __table_args__ = (
        UniqueConstraint(
            "invoice_item_line_id",
            "variant_id",
            name="uq_invoice_line_variant_alloc_line_variant",
        ),
        CheckConstraint("quantity > 0", name="ck_invoice_line_variant_alloc_qty_positive"),
        Index(
            "ix_invoice_line_variant_alloc_business_variant",
            "business_id",
            "variant_id",
        ),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
    )
    invoice_item_line_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("invoice_item_lines.id", ondelete="CASCADE"), nullable=False, index=True
    )
    product_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("products.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    variant_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("product_variants.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    quantity: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False)
    unit_price: Mapped[Decimal | None] = mapped_column(Numeric(18, 2), nullable=True)
    attributes_snapshot: Mapped[dict] = mapped_column(JSON, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
    )


class WarehouseLineVariantAllocation(Base):
    """تخصیص Variant به خط حواله؛ مقدار همیشه واحد اصلی کالا است."""

    __tablename__ = "warehouse_line_variant_allocations"
    __table_args__ = (
        UniqueConstraint(
            "warehouse_document_line_id",
            "variant_id",
            name="uq_warehouse_line_variant_alloc_line_variant",
        ),
        CheckConstraint("quantity > 0", name="ck_warehouse_line_variant_alloc_qty_positive"),
        Index(
            "ix_warehouse_line_variant_alloc_business_variant",
            "business_id",
            "variant_id",
        ),
        Index(
            "ix_warehouse_line_variant_alloc_business_line",
            "business_id",
            "warehouse_document_line_id",
        ),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
    )
    warehouse_document_line_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("warehouse_document_lines.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    product_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("products.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    variant_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("product_variants.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    source_document_allocation_id: Mapped[int | None] = mapped_column(
        BigInteger,
        ForeignKey("invoice_item_line_variant_allocations.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    quantity: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
    )
