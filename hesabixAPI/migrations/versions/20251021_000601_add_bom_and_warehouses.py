"""add BOM and warehouses tables

Revision ID: 20251021_000601_add_bom_and_warehouses
Revises: 20251014_000501_add_quantity_to_document_lines
Create Date: 2025-10-21 00:06:01.000000

"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "20251021_000601_add_bom_and_warehouses"
down_revision = "20251014_000501_add_quantity_to_document_lines"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)

    # warehouses (ایجاد فقط اگر وجود ندارد)
    if not insp.has_table("warehouses"):
        op.create_table(
            "warehouses",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
            sa.Column("code", sa.String(length=64), nullable=False),
            sa.Column("name", sa.String(length=255), nullable=False),
            sa.Column("description", sa.Text(), nullable=True),
            sa.Column("is_default", sa.Boolean(), nullable=False, server_default=sa.text("0")),
            sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
            sa.UniqueConstraint("business_id", "code", name="uq_warehouses_business_code"),
        )
        try:
            op.create_index("ix_warehouses_business_id", "warehouses", ["business_id"]) 
            op.create_index("ix_warehouses_code", "warehouses", ["code"]) 
            op.create_index("ix_warehouses_name", "warehouses", ["name"]) 
            op.create_index("ix_warehouses_is_default", "warehouses", ["is_default"]) 
        except Exception:
            pass

    # product_boms
    if not insp.has_table("product_boms"):
        op.create_table(
            "product_boms",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
            sa.Column("product_id", sa.Integer(), sa.ForeignKey("products.id", ondelete="CASCADE"), nullable=False),
            sa.Column("version", sa.String(length=64), nullable=False),
            sa.Column("name", sa.String(length=255), nullable=False),
            sa.Column("is_default", sa.Boolean(), nullable=False, server_default=sa.text("0")),
            sa.Column("effective_from", sa.Date(), nullable=True),
            sa.Column("effective_to", sa.Date(), nullable=True),
            sa.Column("yield_percent", sa.Numeric(5, 2), nullable=True),
            sa.Column("wastage_percent", sa.Numeric(5, 2), nullable=True),
            sa.Column("status", sa.String(length=16), nullable=False, server_default=sa.text("'draft'")),
            sa.Column("notes", sa.Text(), nullable=True),
            sa.Column("created_by", sa.Integer(), nullable=True),
            sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
            sa.UniqueConstraint("business_id", "product_id", "version", name="uq_product_bom_version_per_product"),
        )
        try:
            op.create_index("ix_product_boms_business_id", "product_boms", ["business_id"]) 
            op.create_index("ix_product_boms_product_id", "product_boms", ["product_id"]) 
            op.create_index("ix_product_boms_is_default", "product_boms", ["is_default"]) 
            op.create_index("ix_product_boms_status", "product_boms", ["status"]) 
        except Exception:
            pass

    # product_bom_items
    if not insp.has_table("product_bom_items"):
        op.create_table(
            "product_bom_items",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("bom_id", sa.Integer(), sa.ForeignKey("product_boms.id", ondelete="CASCADE"), nullable=False),
            sa.Column("line_no", sa.Integer(), nullable=False),
            sa.Column("component_product_id", sa.Integer(), sa.ForeignKey("products.id", ondelete="RESTRICT"), nullable=False),
            sa.Column("qty_per", sa.Numeric(18, 6), nullable=False),
            sa.Column("uom", sa.String(length=32), nullable=True),
            sa.Column("wastage_percent", sa.Numeric(5, 2), nullable=True),
            sa.Column("is_optional", sa.Boolean(), nullable=False, server_default=sa.text("0")),
            sa.Column("substitute_group", sa.String(length=64), nullable=True),
            sa.Column("suggested_warehouse_id", sa.Integer(), sa.ForeignKey("warehouses.id", ondelete="SET NULL"), nullable=True),
            sa.UniqueConstraint("bom_id", "line_no", name="uq_bom_items_line"),
        )
        try:
            op.create_index("ix_product_bom_items_bom_id", "product_bom_items", ["bom_id"]) 
            op.create_index("ix_product_bom_items_component_product_id", "product_bom_items", ["component_product_id"]) 
        except Exception:
            pass

    # product_bom_outputs
    if not insp.has_table("product_bom_outputs"):
        op.create_table(
            "product_bom_outputs",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("bom_id", sa.Integer(), sa.ForeignKey("product_boms.id", ondelete="CASCADE"), nullable=False),
            sa.Column("line_no", sa.Integer(), nullable=False),
            sa.Column("output_product_id", sa.Integer(), sa.ForeignKey("products.id", ondelete="RESTRICT"), nullable=False),
            sa.Column("ratio", sa.Numeric(18, 6), nullable=False),
            sa.Column("uom", sa.String(length=32), nullable=True),
            sa.UniqueConstraint("bom_id", "line_no", name="uq_bom_outputs_line"),
        )
        try:
            op.create_index("ix_product_bom_outputs_bom_id", "product_bom_outputs", ["bom_id"]) 
            op.create_index("ix_product_bom_outputs_output_product_id", "product_bom_outputs", ["output_product_id"]) 
        except Exception:
            pass

    # product_bom_operations
    if not insp.has_table("product_bom_operations"):
        op.create_table(
            "product_bom_operations",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("bom_id", sa.Integer(), sa.ForeignKey("product_boms.id", ondelete="CASCADE"), nullable=False),
            sa.Column("line_no", sa.Integer(), nullable=False),
            sa.Column("operation_name", sa.String(length=255), nullable=False),
            sa.Column("cost_fixed", sa.Numeric(18, 2), nullable=True),
            sa.Column("cost_per_unit", sa.Numeric(18, 6), nullable=True),
            sa.Column("cost_uom", sa.String(length=32), nullable=True),
            sa.Column("work_center", sa.String(length=128), nullable=True),
            sa.UniqueConstraint("bom_id", "line_no", name="uq_bom_operations_line"),
        )
        try:
            op.create_index("ix_product_bom_operations_bom_id", "product_bom_operations", ["bom_id"]) 
        except Exception:
            pass


def downgrade() -> None:
    op.drop_index("ix_product_bom_operations_bom_id", table_name="product_bom_operations")
    op.drop_table("product_bom_operations")

    op.drop_index("ix_product_bom_outputs_output_product_id", table_name="product_bom_outputs")
    op.drop_index("ix_product_bom_outputs_bom_id", table_name="product_bom_outputs")
    op.drop_table("product_bom_outputs")

    op.drop_index("ix_product_bom_items_component_product_id", table_name="product_bom_items")
    op.drop_index("ix_product_bom_items_bom_id", table_name="product_bom_items")
    op.drop_table("product_bom_items")

    op.drop_index("ix_product_boms_status", table_name="product_boms")
    op.drop_index("ix_product_boms_is_default", table_name="product_boms")
    op.drop_index("ix_product_boms_product_id", table_name="product_boms")
    op.drop_index("ix_product_boms_business_id", table_name="product_boms")
    op.drop_table("product_boms")

    op.drop_index("ix_warehouses_is_default", table_name="warehouses")
    op.drop_index("ix_warehouses_name", table_name="warehouses")
    op.drop_index("ix_warehouses_code", table_name="warehouses")
    op.drop_index("ix_warehouses_business_id", table_name="warehouses")
    op.drop_table("warehouses")


