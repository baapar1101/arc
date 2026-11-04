"""اپراتور روی خروجی خط افزونه تولید پیشرفته.

Revision ID: 20261105_000003_advanced_production_operator
Revises: 20261105_000002_advanced_production_maintenance
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261105_000003_advanced_production_operator"
down_revision = "20261105_000002_advanced_production_maintenance"
branch_labels = None
depends_on = None


def upgrade() -> None:
	conn = op.get_bind()
	insp = sa.inspect(conn)
	if "ap_output_logs" not in insp.get_table_names():
		return
	columns = {col["name"] for col in insp.get_columns("ap_output_logs")}
	if "operator_person_id" in columns:
		return
	op.add_column(
		"ap_output_logs",
		sa.Column("operator_person_id", sa.Integer(), sa.ForeignKey("persons.id", ondelete="SET NULL"), nullable=True),
	)


def downgrade() -> None:
	op.drop_column("ap_output_logs", "operator_person_id")
