"""دستگاه روی خروجی خط، هزینه توقف، و توقف موقت سفارش.

Revision ID: 20261105_000005_advanced_production_machine_hold
Revises: 20261105_000004_advanced_production_scrap
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261105_000005_advanced_production_machine_hold"
down_revision = "20261105_000004_advanced_production_scrap"
branch_labels = None
depends_on = None


def upgrade() -> None:
	conn = op.get_bind()
	insp = sa.inspect(conn)
	tables = set(insp.get_table_names())
	if "ap_output_logs" in tables:
		columns = {col["name"] for col in insp.get_columns("ap_output_logs")}
		if "machine_id" not in columns:
			op.add_column(
				"ap_output_logs",
				sa.Column("machine_id", sa.Integer(), sa.ForeignKey("ap_machines.id", ondelete="SET NULL"), nullable=True),
			)
	if "ap_downtime" in tables:
		columns = {col["name"] for col in insp.get_columns("ap_downtime")}
		if "cost_amount" not in columns:
			op.add_column(
				"ap_downtime",
				sa.Column("cost_amount", sa.Numeric(18, 2), nullable=False, server_default="0"),
			)
	if "ap_order_holds" not in tables:
		op.create_table(
			"ap_order_holds",
			sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
			sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
			sa.Column("production_order_id", sa.Integer(), sa.ForeignKey("production_orders.id", ondelete="CASCADE"), nullable=False),
			sa.Column("held_on", sa.Date(), nullable=False),
			sa.Column("released_on", sa.Date(), nullable=True),
			sa.Column("reason", sa.String(255), nullable=False),
		)
		op.create_index("ix_ap_order_holds_business", "ap_order_holds", ["business_id"])
		op.create_index("ix_ap_order_holds_order", "ap_order_holds", ["production_order_id"])


def downgrade() -> None:
	op.drop_index("ix_ap_order_holds_order", table_name="ap_order_holds")
	op.drop_index("ix_ap_order_holds_business", table_name="ap_order_holds")
	op.drop_table("ap_order_holds")
	op.drop_column("ap_downtime", "cost_amount")
	op.drop_column("ap_output_logs", "machine_id")
