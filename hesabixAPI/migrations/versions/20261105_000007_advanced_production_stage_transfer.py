"""انتقال ثبت‌شده بین دو خط تولید.

Revision ID: 20261105_000007_advanced_production_stage_transfer
Revises: 20261105_000006_advanced_production_capacity_count
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261105_000007_advanced_production_stage_transfer"
down_revision = "20261105_000006_advanced_production_capacity_count"
branch_labels = None
depends_on = None


def upgrade() -> None:
	conn = op.get_bind()
	if "ap_stage_transfers" in set(sa.inspect(conn).get_table_names()):
		return
	op.create_table(
		"ap_stage_transfers",
		sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
		sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
		sa.Column("from_line_id", sa.Integer(), sa.ForeignKey("ap_lines.id", ondelete="RESTRICT"), nullable=False),
		sa.Column("to_line_id", sa.Integer(), sa.ForeignKey("ap_lines.id", ondelete="RESTRICT"), nullable=False),
		sa.Column("product_id", sa.Integer(), sa.ForeignKey("products.id", ondelete="RESTRICT"), nullable=False),
		sa.Column("transferred_on", sa.Date(), nullable=False),
		sa.Column("quantity", sa.Numeric(18, 6), nullable=False),
	)
	op.create_index("ix_ap_stage_transfers_business", "ap_stage_transfers", ["business_id"])
	op.create_index("ix_ap_stage_transfers_product", "ap_stage_transfers", ["product_id"])
	op.create_index("ix_ap_stage_transfers_date", "ap_stage_transfers", ["transferred_on"])


def downgrade() -> None:
	op.drop_index("ix_ap_stage_transfers_date", table_name="ap_stage_transfers")
	op.drop_index("ix_ap_stage_transfers_product", table_name="ap_stage_transfers")
	op.drop_index("ix_ap_stage_transfers_business", table_name="ap_stage_transfers")
	op.drop_table("ap_stage_transfers")
