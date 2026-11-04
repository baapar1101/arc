"""اتصال سفارش به خط، شمارش WIP، دوباره‌کاری و برگشت به خط.

Revision ID: 20261105_000006_advanced_production_capacity_count
Revises: 20261105_000005_advanced_production_machine_hold
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261105_000006_advanced_production_capacity_count"
down_revision = "20261105_000005_advanced_production_machine_hold"
branch_labels = None
depends_on = None


def upgrade() -> None:
	conn = op.get_bind()
	tables = set(sa.inspect(conn).get_table_names())
	if "ap_order_lines" not in tables:
		op.create_table(
			"ap_order_lines",
			sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
			sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
			sa.Column("production_order_id", sa.Integer(), sa.ForeignKey("production_orders.id", ondelete="CASCADE"), nullable=False),
			sa.Column("line_id", sa.Integer(), sa.ForeignKey("ap_lines.id", ondelete="CASCADE"), nullable=False),
			sa.UniqueConstraint("business_id", "production_order_id", name="uq_ap_order_lines_order"),
		)
		op.create_index("ix_ap_order_lines_business", "ap_order_lines", ["business_id"])
	if "ap_wip_counts" not in tables:
		op.create_table(
			"ap_wip_counts",
			sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
			sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
			sa.Column("production_order_id", sa.Integer(), sa.ForeignKey("production_orders.id", ondelete="CASCADE"), nullable=False),
			sa.Column("counted_on", sa.Date(), nullable=False),
			sa.Column("counted_quantity", sa.Numeric(18, 6), nullable=False),
		)
		op.create_index("ix_ap_wip_counts_business", "ap_wip_counts", ["business_id"])
		op.create_index("ix_ap_wip_counts_order", "ap_wip_counts", ["production_order_id"])
	if "ap_rework" not in tables:
		op.create_table(
			"ap_rework",
			sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
			sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
			sa.Column("product_id", sa.Integer(), sa.ForeignKey("products.id", ondelete="RESTRICT"), nullable=False),
			sa.Column("production_order_id", sa.Integer(), sa.ForeignKey("production_orders.id", ondelete="SET NULL"), nullable=True),
			sa.Column("occurred_on", sa.Date(), nullable=False),
			sa.Column("quantity", sa.Numeric(18, 6), nullable=False),
		)
		op.create_index("ix_ap_rework_business", "ap_rework", ["business_id"])
		op.create_index("ix_ap_rework_product", "ap_rework", ["product_id"])
	if "ap_line_returns" not in tables:
		op.create_table(
			"ap_line_returns",
			sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
			sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
			sa.Column("product_id", sa.Integer(), sa.ForeignKey("products.id", ondelete="RESTRICT"), nullable=False),
			sa.Column("line_id", sa.Integer(), sa.ForeignKey("ap_lines.id", ondelete="SET NULL"), nullable=True),
			sa.Column("occurred_on", sa.Date(), nullable=False),
			sa.Column("quantity", sa.Numeric(18, 6), nullable=False),
		)
		op.create_index("ix_ap_line_returns_business", "ap_line_returns", ["business_id"])
		op.create_index("ix_ap_line_returns_product", "ap_line_returns", ["product_id"])


def downgrade() -> None:
	op.drop_index("ix_ap_line_returns_product", table_name="ap_line_returns")
	op.drop_index("ix_ap_line_returns_business", table_name="ap_line_returns")
	op.drop_table("ap_line_returns")
	op.drop_index("ix_ap_rework_product", table_name="ap_rework")
	op.drop_index("ix_ap_rework_business", table_name="ap_rework")
	op.drop_table("ap_rework")
	op.drop_index("ix_ap_wip_counts_order", table_name="ap_wip_counts")
	op.drop_index("ix_ap_wip_counts_business", table_name="ap_wip_counts")
	op.drop_table("ap_wip_counts")
	op.drop_index("ix_ap_order_lines_business", table_name="ap_order_lines")
	op.drop_table("ap_order_lines")
