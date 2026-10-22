from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import (
	Boolean,
	Date,
	DateTime,
	ForeignKey,
	Index,
	Integer,
	JSON,
	Numeric,
	String,
	Text,
	UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from adapters.db.session import Base


class ProductionOrder(Base):
	"""Planned and controlled manufacturing order; inventory documents carry actuals."""

	__tablename__ = "production_orders"
	__table_args__ = (
		UniqueConstraint("business_id", "code", name="uq_production_orders_business_code"),
		Index("ix_production_orders_business_status_due", "business_id", "status", "due_date"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	business_id: Mapped[int] = mapped_column(Integer, ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False, index=True)
	code: Mapped[str] = mapped_column(String(64), nullable=False)
	product_id: Mapped[int] = mapped_column(Integer, ForeignKey("products.id", ondelete="RESTRICT"), nullable=False, index=True)
	bom_id: Mapped[int] = mapped_column(Integer, ForeignKey("product_boms.id", ondelete="RESTRICT"), nullable=False, index=True)
	warehouse_id: Mapped[int] = mapped_column(Integer, ForeignKey("warehouses.id", ondelete="RESTRICT"), nullable=False)
	output_warehouse_id: Mapped[int] = mapped_column(Integer, ForeignKey("warehouses.id", ondelete="RESTRICT"), nullable=False)
	planned_quantity: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False)
	produced_quantity: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False, default=Decimal("0"))
	status: Mapped[str] = mapped_column(String(16), nullable=False, default="draft", index=True)
	priority: Mapped[int] = mapped_column(Integer, nullable=False, default=3)
	planned_start_date: Mapped[date | None] = mapped_column(Date, nullable=True)
	due_date: Mapped[date | None] = mapped_column(Date, nullable=True, index=True)
	started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
	completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
	created_by_user_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
	version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
	notes: Mapped[str | None] = mapped_column(Text, nullable=True)
	extra_info: Mapped[dict | None] = mapped_column(JSON, nullable=True)
	standard_materials_cost: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=Decimal("0"))
	standard_operations_cost: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=Decimal("0"))
	actual_materials_cost: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=Decimal("0"))
	actual_operations_cost: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=Decimal("0"))
	actual_finished_cost: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=Decimal("0"))
	costing_frozen_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
	created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=datetime.utcnow)
	updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow)

	materials = relationship("ProductionOrderMaterial", back_populates="order", cascade="all, delete-orphan", order_by="ProductionOrderMaterial.line_no")
	outputs = relationship("ProductionOrderOutput", back_populates="order", cascade="all, delete-orphan", order_by="ProductionOrderOutput.line_no")
	operations = relationship("ProductionOrderOperation", back_populates="order", cascade="all, delete-orphan", order_by="ProductionOrderOperation.line_no")


class ProductionOrderMaterial(Base):
	"""Immutable-at-release material requirement snapshot and its outstanding reservation."""

	__tablename__ = "production_order_materials"
	__table_args__ = (
		UniqueConstraint("production_order_id", "line_no", name="uq_production_order_material_line"),
		Index("ix_production_order_material_reservation", "product_id", "warehouse_id", "production_order_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	production_order_id: Mapped[int] = mapped_column(Integer, ForeignKey("production_orders.id", ondelete="CASCADE"), nullable=False, index=True)
	line_no: Mapped[int] = mapped_column(Integer, nullable=False)
	product_id: Mapped[int] = mapped_column(Integer, ForeignKey("products.id", ondelete="RESTRICT"), nullable=False, index=True)
	warehouse_id: Mapped[int] = mapped_column(Integer, ForeignKey("warehouses.id", ondelete="RESTRICT"), nullable=False, index=True)
	planned_quantity: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False)
	reserved_quantity: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False, default=Decimal("0"))
	issued_quantity: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False, default=Decimal("0"))
	standard_unit_cost: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False, default=Decimal("0"))
	standard_total_cost: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=Decimal("0"))
	actual_total_cost: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=Decimal("0"))
	uom: Mapped[str | None] = mapped_column(String(32), nullable=True)
	lot_code: Mapped[str | None] = mapped_column(String(64), nullable=True)
	bom_path: Mapped[str | None] = mapped_column(String(512), nullable=True)
	is_optional: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
	source_bom_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("product_boms.id", ondelete="SET NULL"), nullable=True)

	order = relationship("ProductionOrder", back_populates="materials")


class ProductionOrderOutput(Base):
	"""Planned and actual output snapshots, including co-products."""

	__tablename__ = "production_order_outputs"
	__table_args__ = (
		UniqueConstraint("production_order_id", "line_no", name="uq_production_order_output_line"),
		Index("ix_production_order_output_product", "product_id", "production_order_id"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	production_order_id: Mapped[int] = mapped_column(Integer, ForeignKey("production_orders.id", ondelete="CASCADE"), nullable=False, index=True)
	line_no: Mapped[int] = mapped_column(Integer, nullable=False)
	product_id: Mapped[int] = mapped_column(Integer, ForeignKey("products.id", ondelete="RESTRICT"), nullable=False, index=True)
	planned_quantity: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False)
	produced_quantity: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False, default=Decimal("0"))
	scrap_quantity: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False, default=Decimal("0"))
	standard_unit_cost: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False, default=Decimal("0"))
	standard_total_cost: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=Decimal("0"))
	actual_total_cost: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=Decimal("0"))
	uom: Mapped[str | None] = mapped_column(String(32), nullable=True)
	lot_code: Mapped[str | None] = mapped_column(String(64), nullable=True)

	order = relationship("ProductionOrder", back_populates="outputs")


class ProductionOrderOperation(Base):
	"""Frozen BOM operation/overhead standards and actual ops cost for an order."""

	__tablename__ = "production_order_operations"
	__table_args__ = (
		UniqueConstraint("production_order_id", "line_no", name="uq_production_order_operation_line"),
	)

	id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
	production_order_id: Mapped[int] = mapped_column(Integer, ForeignKey("production_orders.id", ondelete="CASCADE"), nullable=False, index=True)
	line_no: Mapped[int] = mapped_column(Integer, nullable=False)
	operation_name: Mapped[str] = mapped_column(String(255), nullable=False)
	work_center: Mapped[str | None] = mapped_column(String(128), nullable=True)
	cost_uom: Mapped[str | None] = mapped_column(String(32), nullable=True)
	standard_cost_fixed: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=Decimal("0"))
	standard_cost_per_unit: Mapped[Decimal] = mapped_column(Numeric(18, 6), nullable=False, default=Decimal("0"))
	standard_total_cost: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=Decimal("0"))
	actual_total_cost: Mapped[Decimal] = mapped_column(Numeric(18, 2), nullable=False, default=Decimal("0"))
	source_bom_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("product_boms.id", ondelete="SET NULL"), nullable=True)

	order = relationship("ProductionOrder", back_populates="operations")
