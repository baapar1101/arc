"""Add production-order costing snapshots, operations, and light lot codes.

Revision ID: 20261021_000002_production_order_costing
Revises: 20261021_000001_production_orders
"""

from alembic import op
import sqlalchemy as sa


revision = "20261021_000002_production_order_costing"
down_revision = "20261021_000001_production_orders"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column("production_orders", sa.Column("standard_materials_cost", sa.Numeric(18, 2), server_default="0", nullable=False))
	op.add_column("production_orders", sa.Column("standard_operations_cost", sa.Numeric(18, 2), server_default="0", nullable=False))
	op.add_column("production_orders", sa.Column("actual_materials_cost", sa.Numeric(18, 2), server_default="0", nullable=False))
	op.add_column("production_orders", sa.Column("actual_operations_cost", sa.Numeric(18, 2), server_default="0", nullable=False))
	op.add_column("production_orders", sa.Column("actual_finished_cost", sa.Numeric(18, 2), server_default="0", nullable=False))
	op.add_column("production_orders", sa.Column("costing_frozen_at", sa.DateTime(timezone=True), nullable=True))

	op.add_column("production_order_materials", sa.Column("standard_unit_cost", sa.Numeric(18, 6), server_default="0", nullable=False))
	op.add_column("production_order_materials", sa.Column("standard_total_cost", sa.Numeric(18, 2), server_default="0", nullable=False))
	op.add_column("production_order_materials", sa.Column("actual_total_cost", sa.Numeric(18, 2), server_default="0", nullable=False))
	op.add_column("production_order_materials", sa.Column("lot_code", sa.String(length=64), nullable=True))

	op.add_column("production_order_outputs", sa.Column("standard_unit_cost", sa.Numeric(18, 6), server_default="0", nullable=False))
	op.add_column("production_order_outputs", sa.Column("standard_total_cost", sa.Numeric(18, 2), server_default="0", nullable=False))
	op.add_column("production_order_outputs", sa.Column("actual_total_cost", sa.Numeric(18, 2), server_default="0", nullable=False))
	op.add_column("production_order_outputs", sa.Column("lot_code", sa.String(length=64), nullable=True))
	op.add_column("production_order_outputs", sa.Column("scrap_quantity", sa.Numeric(18, 6), server_default="0", nullable=False))

	op.create_table(
		"production_order_operations",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("production_order_id", sa.Integer(), nullable=False),
		sa.Column("line_no", sa.Integer(), nullable=False),
		sa.Column("operation_name", sa.String(length=255), nullable=False),
		sa.Column("work_center", sa.String(length=128), nullable=True),
		sa.Column("cost_uom", sa.String(length=32), nullable=True),
		sa.Column("standard_cost_fixed", sa.Numeric(18, 2), server_default="0", nullable=False),
		sa.Column("standard_cost_per_unit", sa.Numeric(18, 6), server_default="0", nullable=False),
		sa.Column("standard_total_cost", sa.Numeric(18, 2), server_default="0", nullable=False),
		sa.Column("actual_total_cost", sa.Numeric(18, 2), server_default="0", nullable=False),
		sa.Column("source_bom_id", sa.Integer(), nullable=True),
		sa.CheckConstraint("line_no > 0", name="ck_production_order_operation_line_positive"),
		sa.CheckConstraint("standard_total_cost >= 0", name="ck_production_order_operation_standard_nonnegative"),
		sa.CheckConstraint("actual_total_cost >= 0", name="ck_production_order_operation_actual_nonnegative"),
		sa.ForeignKeyConstraint(["production_order_id"], ["production_orders.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["source_bom_id"], ["product_boms.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("production_order_id", "line_no", name="uq_production_order_operation_line"),
	)
	op.create_index(
		"ix_production_order_operations_production_order_id",
		"production_order_operations",
		["production_order_id"],
	)


def downgrade() -> None:
	op.drop_index("ix_production_order_operations_production_order_id", table_name="production_order_operations")
	op.drop_table("production_order_operations")

	op.drop_column("production_order_outputs", "scrap_quantity")
	op.drop_column("production_order_outputs", "lot_code")
	op.drop_column("production_order_outputs", "actual_total_cost")
	op.drop_column("production_order_outputs", "standard_total_cost")
	op.drop_column("production_order_outputs", "standard_unit_cost")

	op.drop_column("production_order_materials", "lot_code")
	op.drop_column("production_order_materials", "actual_total_cost")
	op.drop_column("production_order_materials", "standard_total_cost")
	op.drop_column("production_order_materials", "standard_unit_cost")

	op.drop_column("production_orders", "costing_frozen_at")
	op.drop_column("production_orders", "actual_finished_cost")
	op.drop_column("production_orders", "actual_operations_cost")
	op.drop_column("production_orders", "actual_materials_cost")
	op.drop_column("production_orders", "standard_operations_cost")
	op.drop_column("production_orders", "standard_materials_cost")
