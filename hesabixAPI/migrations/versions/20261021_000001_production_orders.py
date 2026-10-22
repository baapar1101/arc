"""Add production orders and material reservations.

Revision ID: 20261021_000001_production_orders
Revises: 20261019_000002_quick_sale_job_error_details
"""

from alembic import op
import sqlalchemy as sa


revision = "20261021_000001_production_orders"
down_revision = "20261019_000002_quick_sale_job_error_details"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"production_orders",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("code", sa.String(length=64), nullable=False),
		sa.Column("product_id", sa.Integer(), nullable=False),
		sa.Column("bom_id", sa.Integer(), nullable=False),
		sa.Column("warehouse_id", sa.Integer(), nullable=False),
		sa.Column("output_warehouse_id", sa.Integer(), nullable=False),
		sa.Column("planned_quantity", sa.Numeric(18, 6), nullable=False),
		sa.Column("produced_quantity", sa.Numeric(18, 6), server_default="0", nullable=False),
		sa.Column("status", sa.String(length=16), server_default="draft", nullable=False),
		sa.Column("priority", sa.Integer(), server_default="3", nullable=False),
		sa.Column("planned_start_date", sa.Date(), nullable=True),
		sa.Column("due_date", sa.Date(), nullable=True),
		sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
		sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
		sa.Column("created_by_user_id", sa.Integer(), nullable=True),
		sa.Column("version", sa.Integer(), server_default="1", nullable=False),
		sa.Column("notes", sa.Text(), nullable=True),
		sa.Column("extra_info", sa.JSON(), nullable=True),
		sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
		sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
		sa.CheckConstraint("planned_quantity > 0", name="ck_production_order_planned_positive"),
		sa.CheckConstraint("produced_quantity >= 0", name="ck_production_order_produced_nonnegative"),
		sa.CheckConstraint("priority BETWEEN 1 AND 5", name="ck_production_order_priority_range"),
		sa.CheckConstraint("status IN ('draft', 'released', 'in_progress', 'completed', 'cancelled')", name="ck_production_order_status"),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["product_id"], ["products.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["bom_id"], ["product_boms.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["warehouse_id"], ["warehouses.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["output_warehouse_id"], ["warehouses.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "code", name="uq_production_orders_business_code"),
	)
	op.create_index("ix_production_orders_business_id", "production_orders", ["business_id"])
	op.create_index("ix_production_orders_product_id", "production_orders", ["product_id"])
	op.create_index("ix_production_orders_bom_id", "production_orders", ["bom_id"])
	op.create_index("ix_production_orders_status", "production_orders", ["status"])
	op.create_index("ix_production_orders_due_date", "production_orders", ["due_date"])
	op.create_index("ix_production_orders_business_status_due", "production_orders", ["business_id", "status", "due_date"])

	op.create_table(
		"production_order_materials",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("production_order_id", sa.Integer(), nullable=False),
		sa.Column("line_no", sa.Integer(), nullable=False),
		sa.Column("product_id", sa.Integer(), nullable=False),
		sa.Column("warehouse_id", sa.Integer(), nullable=False),
		sa.Column("planned_quantity", sa.Numeric(18, 6), nullable=False),
		sa.Column("reserved_quantity", sa.Numeric(18, 6), server_default="0", nullable=False),
		sa.Column("issued_quantity", sa.Numeric(18, 6), server_default="0", nullable=False),
		sa.Column("uom", sa.String(length=32), nullable=True),
		sa.Column("bom_path", sa.String(length=512), nullable=True),
		sa.Column("is_optional", sa.Boolean(), server_default=sa.false(), nullable=False),
		sa.Column("source_bom_id", sa.Integer(), nullable=True),
		sa.CheckConstraint("line_no > 0", name="ck_production_order_material_line_positive"),
		sa.CheckConstraint("planned_quantity > 0", name="ck_production_order_material_planned_positive"),
		sa.CheckConstraint("reserved_quantity >= 0", name="ck_production_order_material_reserved_nonnegative"),
		sa.CheckConstraint("issued_quantity >= 0", name="ck_production_order_material_issued_nonnegative"),
		sa.ForeignKeyConstraint(["production_order_id"], ["production_orders.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["product_id"], ["products.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["warehouse_id"], ["warehouses.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["source_bom_id"], ["product_boms.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("production_order_id", "line_no", name="uq_production_order_material_line"),
	)
	op.create_index("ix_production_order_materials_production_order_id", "production_order_materials", ["production_order_id"])
	op.create_index("ix_production_order_materials_product_id", "production_order_materials", ["product_id"])
	op.create_index("ix_production_order_materials_warehouse_id", "production_order_materials", ["warehouse_id"])
	op.create_index("ix_production_order_material_reservation", "production_order_materials", ["product_id", "warehouse_id", "production_order_id"])

	op.create_table(
		"production_order_outputs",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("production_order_id", sa.Integer(), nullable=False),
		sa.Column("line_no", sa.Integer(), nullable=False),
		sa.Column("product_id", sa.Integer(), nullable=False),
		sa.Column("planned_quantity", sa.Numeric(18, 6), nullable=False),
		sa.Column("produced_quantity", sa.Numeric(18, 6), server_default="0", nullable=False),
		sa.Column("uom", sa.String(length=32), nullable=True),
		sa.CheckConstraint("line_no > 0", name="ck_production_order_output_line_positive"),
		sa.CheckConstraint("planned_quantity > 0", name="ck_production_order_output_planned_positive"),
		sa.CheckConstraint("produced_quantity >= 0", name="ck_production_order_output_produced_nonnegative"),
		sa.ForeignKeyConstraint(["production_order_id"], ["production_orders.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["product_id"], ["products.id"], ondelete="RESTRICT"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("production_order_id", "line_no", name="uq_production_order_output_line"),
	)
	op.create_index("ix_production_order_outputs_production_order_id", "production_order_outputs", ["production_order_id"])
	op.create_index("ix_production_order_outputs_product_id", "production_order_outputs", ["product_id"])
	op.create_index("ix_production_order_output_product", "production_order_outputs", ["product_id", "production_order_id"])


def downgrade() -> None:
	op.drop_index("ix_production_order_output_product", table_name="production_order_outputs")
	op.drop_index("ix_production_order_outputs_product_id", table_name="production_order_outputs")
	op.drop_index("ix_production_order_outputs_production_order_id", table_name="production_order_outputs")
	op.drop_table("production_order_outputs")
	op.drop_index("ix_production_order_material_reservation", table_name="production_order_materials")
	op.drop_index("ix_production_order_materials_warehouse_id", table_name="production_order_materials")
	op.drop_index("ix_production_order_materials_product_id", table_name="production_order_materials")
	op.drop_index("ix_production_order_materials_production_order_id", table_name="production_order_materials")
	op.drop_table("production_order_materials")
	op.drop_index("ix_production_orders_business_status_due", table_name="production_orders")
	op.drop_index("ix_production_orders_due_date", table_name="production_orders")
	op.drop_index("ix_production_orders_status", table_name="production_orders")
	op.drop_index("ix_production_orders_bom_id", table_name="production_orders")
	op.drop_index("ix_production_orders_product_id", table_name="production_orders")
	op.drop_index("ix_production_orders_business_id", table_name="production_orders")
	op.drop_table("production_orders")
