"""علت و رویداد ضایعات، و علت اختیاری بازرسی.

Revision ID: 20261105_000004_advanced_production_scrap
Revises: 20261105_000003_advanced_production_operator
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261105_000004_advanced_production_scrap"
down_revision = "20261105_000003_advanced_production_operator"
branch_labels = None
depends_on = None


def upgrade() -> None:
	conn = op.get_bind()
	insp = sa.inspect(conn)
	tables = set(insp.get_table_names())
	if "ap_scrap_reasons" not in tables:
		op.create_table(
			"ap_scrap_reasons",
			sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
			sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
			sa.Column("code", sa.String(64), nullable=False),
			sa.Column("name", sa.String(255), nullable=False),
			sa.Column("recyclable", sa.Boolean(), nullable=False),
			sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
			sa.UniqueConstraint("business_id", "code", name="uq_ap_scrap_reasons_code"),
		)
		op.create_index("ix_ap_scrap_reasons_business", "ap_scrap_reasons", ["business_id"])
	if "ap_scrap_events" not in tables:
		op.create_table(
			"ap_scrap_events",
			sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
			sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
			sa.Column("reason_id", sa.Integer(), sa.ForeignKey("ap_scrap_reasons.id", ondelete="RESTRICT"), nullable=False),
			sa.Column("product_id", sa.Integer(), sa.ForeignKey("products.id", ondelete="RESTRICT"), nullable=False),
			sa.Column("line_id", sa.Integer(), sa.ForeignKey("ap_lines.id", ondelete="SET NULL"), nullable=True),
			sa.Column("occurred_on", sa.Date(), nullable=False),
			sa.Column("quantity", sa.Numeric(18, 6), nullable=False),
		)
		op.create_index("ix_ap_scrap_events_business", "ap_scrap_events", ["business_id"])
		op.create_index("ix_ap_scrap_events_reason", "ap_scrap_events", ["reason_id"])
		op.create_index("ix_ap_scrap_events_product", "ap_scrap_events", ["product_id"])
		op.create_index("ix_ap_scrap_events_occurred", "ap_scrap_events", ["occurred_on"])
	if "ap_qc_inspections" in tables:
		columns = {col["name"] for col in insp.get_columns("ap_qc_inspections")}
		if "reason_code" not in columns:
			op.add_column("ap_qc_inspections", sa.Column("reason_code", sa.String(64), nullable=True))


def downgrade() -> None:
	op.drop_index("ix_ap_scrap_events_occurred", table_name="ap_scrap_events")
	op.drop_index("ix_ap_scrap_events_product", table_name="ap_scrap_events")
	op.drop_index("ix_ap_scrap_events_reason", table_name="ap_scrap_events")
	op.drop_index("ix_ap_scrap_events_business", table_name="ap_scrap_events")
	op.drop_table("ap_scrap_events")
	op.drop_index("ix_ap_scrap_reasons_business", table_name="ap_scrap_reasons")
	op.drop_table("ap_scrap_reasons")
	op.drop_column("ap_qc_inspections", "reason_code")
