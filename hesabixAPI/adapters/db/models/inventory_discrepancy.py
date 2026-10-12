from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from sqlalchemy import DateTime, ForeignKey, Integer, Numeric, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class InventoryDiscrepancyCase(Base):
    """ردپای قابل رسیدگی برای فروش‌هایی که با کسری سیستمی ثبت شده‌اند."""

    __tablename__ = "inventory_discrepancy_cases"
    __table_args__ = (
        UniqueConstraint("business_id", "request_token", name="uq_inventory_discrepancy_request"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    business_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True
    )
    invoice_document_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("documents.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    warehouse_document_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("warehouse_documents.id", ondelete="SET NULL"), nullable=True, index=True
    )
    resolution_document_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("goods_expense_income_documents.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    status: Mapped[str] = mapped_column(String(24), nullable=False, default="open", index=True)
    source_type: Mapped[str] = mapped_column(String(32), nullable=False, default="quick_sale")
    request_token: Mapped[str] = mapped_column(String(80), nullable=False)
    reason_code: Mapped[str] = mapped_column(String(48), nullable=False)
    reason_note: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_by_user_id: Mapped[int] = mapped_column(Integer, nullable=False, index=True)
    resolved_by_user_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    resolution_type: Mapped[str | None] = mapped_column(String(48), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
    )
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    lines = relationship(
        "InventoryDiscrepancyLine",
        back_populates="case",
        cascade="all, delete-orphan",
        order_by="InventoryDiscrepancyLine.id",
    )
    invoice_document = relationship("Document", foreign_keys=[invoice_document_id])


class InventoryDiscrepancyLine(Base):
    __tablename__ = "inventory_discrepancy_lines"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    case_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("inventory_discrepancy_cases.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    product_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("products.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    warehouse_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("warehouses.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    invoice_item_line_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("invoice_item_lines.id", ondelete="SET NULL"), nullable=True
    )
    available_quantity: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False)
    requested_quantity: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False)
    shortage_quantity: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False)
    resolved_quantity: Mapped[Decimal] = mapped_column(
        Numeric(18, 6), nullable=False, default=Decimal("0")
    )
    resolution_unit_cost: Mapped[Decimal | None] = mapped_column(Numeric(18, 6), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)

    case = relationship("InventoryDiscrepancyCase", back_populates="lines")
    product = relationship("Product", foreign_keys=[product_id])
    warehouse = relationship("Warehouse", foreign_keys=[warehouse_id])
