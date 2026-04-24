"""Warehouse locations (per-warehouse hierarchy) and product placements

Revision ID: 20260418_000003_warehouse_locations_and_placements
Revises: 20260418_000002_customer_club_tables
Create Date: 2026-04-18
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260418_000003_warehouse_locations_and_placements"
down_revision = "20260418_000002_customer_club_tables"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"warehouse_locations",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("warehouse_id", sa.Integer(), nullable=False),
		sa.Column("parent_id", sa.Integer(), nullable=True),
		sa.Column("code", sa.String(length=64), nullable=False, comment="کد یکتا در هر انبار"),
		sa.Column("name", sa.String(length=255), nullable=False),
		sa.Column(
			"location_kind",
			sa.String(length=32),
			nullable=False,
			server_default=sa.text("'zone'"),
			comment="نوع: zone|aisle|rack|shelf|bin|other",
		),
		sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("notes", sa.Text(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["warehouse_id"], ["warehouses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["parent_id"], ["warehouse_locations.id"], ondelete="RESTRICT"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("warehouse_id", "code", name="uq_warehouse_locations_wh_code"),
	)
	op.create_index(op.f("ix_warehouse_locations_business_id"), "warehouse_locations", ["business_id"], unique=False)
	op.create_index(op.f("ix_warehouse_locations_warehouse_id"), "warehouse_locations", ["warehouse_id"], unique=False)
	op.create_index(op.f("ix_warehouse_locations_parent_id"), "warehouse_locations", ["parent_id"], unique=False)

	op.create_table(
		"warehouse_product_placements",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("warehouse_id", sa.Integer(), nullable=False),
		sa.Column("warehouse_location_id", sa.Integer(), nullable=False),
		sa.Column("product_id", sa.Integer(), nullable=False),
		sa.Column("quantity", sa.Numeric(precision=18, scale=6), nullable=False, server_default="0"),
		sa.Column("notes", sa.Text(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["warehouse_id"], ["warehouses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["warehouse_location_id"], ["warehouse_locations.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["product_id"], ["products.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint(
			"warehouse_id",
			"product_id",
			"warehouse_location_id",
			name="uq_wh_placements_wh_product_location",
		),
	)
	op.create_index(op.f("ix_wh_pp_business_id"), "warehouse_product_placements", ["business_id"], unique=False)
	op.create_index(op.f("ix_wh_pp_warehouse_id"), "warehouse_product_placements", ["warehouse_id"], unique=False)
	op.create_index(op.f("ix_wh_pp_location_id"), "warehouse_product_placements", ["warehouse_location_id"], unique=False)
	op.create_index(op.f("ix_wh_pp_product_id"), "warehouse_product_placements", ["product_id"], unique=False)


def downgrade() -> None:
	op.drop_index(op.f("ix_wh_pp_product_id"), table_name="warehouse_product_placements")
	op.drop_index(op.f("ix_wh_pp_location_id"), table_name="warehouse_product_placements")
	op.drop_index(op.f("ix_wh_pp_warehouse_id"), table_name="warehouse_product_placements")
	op.drop_index(op.f("ix_wh_pp_business_id"), table_name="warehouse_product_placements")
	op.drop_table("warehouse_product_placements")

	op.drop_index(op.f("ix_warehouse_locations_parent_id"), table_name="warehouse_locations")
	op.drop_index(op.f("ix_warehouse_locations_warehouse_id"), table_name="warehouse_locations")
	op.drop_index(op.f("ix_warehouse_locations_business_id"), table_name="warehouse_locations")
	op.drop_table("warehouse_locations")
