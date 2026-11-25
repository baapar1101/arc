"""سوابق نگهداری و تعمیرات افزونه تولید پیشرفته.

Revision ID: 20261105_000002_advanced_production_maintenance
Revises: 20261105_000001_advanced_production_master
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261105_000002_advanced_production_maintenance"
down_revision = "20261105_000001_advanced_production_master"
branch_labels = None
depends_on = None


def upgrade() -> None:
	conn = op.get_bind()
	insp = sa.inspect(conn)
	if "ap_maintenance" in insp.get_table_names():
		return
	op.create_table(
		"ap_maintenance",
		sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
		sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
		sa.Column("machine_id", sa.Integer(), sa.ForeignKey("ap_machines.id", ondelete="CASCADE"), nullable=False),
		sa.Column("line_id", sa.Integer(), sa.ForeignKey("ap_lines.id", ondelete="SET NULL"), nullable=True),
		sa.Column("kind", sa.String(16), nullable=False),
		sa.Column("opened_on", sa.Date(), nullable=False),
		sa.Column("closed_on", sa.Date(), nullable=True),
		sa.Column("repair_minutes", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("cost_amount", sa.Numeric(18, 2), nullable=False, server_default="0"),
		sa.Column("spare_product_id", sa.Integer(), sa.ForeignKey("products.id", ondelete="SET NULL"), nullable=True),
		sa.Column("spare_quantity", sa.Numeric(18, 6), nullable=False, server_default="0"),
		sa.Column("notes", sa.Text(), nullable=True),
	)


def downgrade() -> None:
	op.drop_table("ap_maintenance")
