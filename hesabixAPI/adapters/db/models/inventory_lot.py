from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from adapters.db.session import Base


class InventoryLot(Base):
    """لات همگن: یک کد + یک تاریخ تولید + یک تاریخ انقضا برای یک کالا/واریانت."""

    __tablename__ = "inventory_lots"
    __table_args__ = (
        UniqueConstraint("business_id", "identity_key", name="uq_inventory_lots_business_identity"),
        Index("ix_inventory_lots_business_product", "business_id", "product_id"),
        Index("ix_inventory_lots_business_expiry", "business_id", "expiry_date"),
        Index("ix_inventory_lots_business_alert", "business_id", "alert_date"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
    )
    product_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("products.id", ondelete="CASCADE"), nullable=False, index=True
    )
    variant_id: Mapped[int | None] = mapped_column(
        BigInteger, ForeignKey("product_variants.id", ondelete="SET NULL"), nullable=True, index=True
    )
    lot_code: Mapped[str] = mapped_column(String(64), nullable=False, default="-")
    identity_key: Mapped[str] = mapped_column(String(255), nullable=False)
    manufacturing_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    expiry_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    best_before_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    removal_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    alert_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    is_undated: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
    )


class InvoiceItemLineLotAllocation(Base):
    """تخصیص لات به ردیف فاکتور؛ مقدار در واحد همان ردیف است."""

    __tablename__ = "invoice_item_line_lot_allocations"
    __table_args__ = (
        UniqueConstraint(
            "invoice_item_line_id",
            "lot_id",
            name="uq_invoice_line_lot_alloc_line_lot",
        ),
        CheckConstraint("quantity > 0", name="ck_invoice_line_lot_alloc_qty_positive"),
        Index("ix_invoice_line_lot_alloc_business_lot", "business_id", "lot_id"),
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
    lot_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("inventory_lots.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    quantity: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
    )


class WarehouseLineLotAllocation(Base):
    """تخصیص لات به خط حواله؛ مقدار همیشه واحد اصلی کالاست."""

    __tablename__ = "warehouse_line_lot_allocations"
    __table_args__ = (
        UniqueConstraint(
            "warehouse_document_line_id",
            "lot_id",
            name="uq_warehouse_line_lot_alloc_line_lot",
        ),
        CheckConstraint("quantity > 0", name="ck_warehouse_line_lot_alloc_qty_positive"),
        Index("ix_warehouse_line_lot_alloc_business_lot", "business_id", "lot_id"),
        Index(
            "ix_warehouse_line_lot_alloc_business_line",
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
    lot_id: Mapped[int] = mapped_column(
        BigInteger, ForeignKey("inventory_lots.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    source_document_allocation_id: Mapped[int | None] = mapped_column(
        BigInteger,
        ForeignKey("invoice_item_line_lot_allocations.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    quantity: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
    )
