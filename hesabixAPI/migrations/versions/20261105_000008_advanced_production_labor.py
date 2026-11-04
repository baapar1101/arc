"""ثبت مستقل ساعت و نرخ دستمزد مستقیم تولید.

Revision ID: 20261105_000008_advanced_production_labor
Revises: 20261105_000007_advanced_production_stage_transfer
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261105_000008_advanced_production_labor"
down_revision = "20261105_000007_advanced_production_stage_transfer"
branch_labels = None
depends_on = None


def upgrade() -> None:
	conn = op.get_bind()
	if "ap_labor" in set(sa.inspect(conn).get_table_names()):
		return
	op.create_table(
		"ap_labor",
		sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
		sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
		sa.Column("production_order_id", sa.Integer(), sa.ForeignKey("production_orders.id", ondelete="SET NULL"), nullable=True),
		sa.Column("person_id", sa.Integer(), sa.ForeignKey("persons.id", ondelete="SET NULL"), nullable=True),
		sa.Column("worked_on", sa.Date(), nullable=False),
		sa.Column("actual_hours", sa.Numeric(18, 6), nullable=False),
		sa.Column("standard_hours", sa.Numeric(18, 6), nullable=True),
		sa.Column("standard_hourly_rate", sa.Numeric(18, 6), nullable=True),
		sa.Column("actual_hourly_rate", sa.Numeric(18, 6), nullable=True),
	)
	op.create_index("ix_ap_labor_business", "ap_labor", ["business_id"])
	op.create_index("ix_ap_labor_worked", "ap_labor", ["worked_on"])


def downgrade() -> None:
	op.drop_index("ix_ap_labor_worked", table_name="ap_labor")
	op.drop_index("ix_ap_labor_business", table_name="ap_labor")
	op.drop_table("ap_labor")
