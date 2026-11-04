"""مراکز، خطوط، دستگاه، شیفت، توقف، خروجی خط و کنترل کیفیت افزونه تولید.

Revision ID: 20261105_000001_advanced_production_master
Revises: 20261104_000004_advanced_production_plugin
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261105_000001_advanced_production_master"
down_revision = "20261104_000004_advanced_production_plugin"
branch_labels = None
depends_on = None


def upgrade() -> None:
	conn = op.get_bind()
	insp = sa.inspect(conn)
	tables = set(insp.get_table_names())

	def need(name: str) -> bool:
		return name not in tables

	if need("ap_work_centers"):
		op.create_table(
			"ap_work_centers",
			sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
			sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
			sa.Column("code", sa.String(64), nullable=False),
			sa.Column("name", sa.String(255), nullable=False),
			sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
			sa.UniqueConstraint("business_id", "code", name="uq_ap_work_centers_code"),
		)
	if need("ap_lines"):
		op.create_table(
			"ap_lines",
			sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
			sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
			sa.Column("work_center_id", sa.Integer(), sa.ForeignKey("ap_work_centers.id", ondelete="SET NULL"), nullable=True),
			sa.Column("code", sa.String(64), nullable=False),
			sa.Column("name", sa.String(255), nullable=False),
			sa.Column("nominal_units_per_hour", sa.Numeric(18, 6), nullable=False, server_default="0"),
			sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
			sa.UniqueConstraint("business_id", "code", name="uq_ap_lines_code"),
		)
	if need("ap_machines"):
		op.create_table(
			"ap_machines",
			sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
			sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
			sa.Column("line_id", sa.Integer(), sa.ForeignKey("ap_lines.id", ondelete="SET NULL"), nullable=True),
			sa.Column("fixed_asset_id", sa.Integer(), sa.ForeignKey("fa_assets.id", ondelete="SET NULL"), nullable=True),
			sa.Column("code", sa.String(64), nullable=False),
			sa.Column("name", sa.String(255), nullable=False),
			sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
			sa.UniqueConstraint("business_id", "code", name="uq_ap_machines_code"),
		)
	if need("ap_shifts"):
		op.create_table(
			"ap_shifts",
			sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
			sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
			sa.Column("code", sa.String(64), nullable=False),
			sa.Column("name", sa.String(255), nullable=False),
			sa.Column("start_time", sa.String(5), nullable=True),
			sa.Column("end_time", sa.String(5), nullable=True),
			sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
			sa.UniqueConstraint("business_id", "code", name="uq_ap_shifts_code"),
		)
	if need("ap_downtime"):
		op.create_table(
			"ap_downtime",
			sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
			sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
			sa.Column("line_id", sa.Integer(), sa.ForeignKey("ap_lines.id", ondelete="CASCADE"), nullable=False),
			sa.Column("machine_id", sa.Integer(), sa.ForeignKey("ap_machines.id", ondelete="SET NULL"), nullable=True),
			sa.Column("started_on", sa.Date(), nullable=False),
			sa.Column("ended_on", sa.Date(), nullable=True),
			sa.Column("minutes", sa.Integer(), nullable=False),
			sa.Column("reason_code", sa.String(64), nullable=False),
			sa.Column("notes", sa.Text(), nullable=True),
		)
	if need("ap_output_logs"):
		op.create_table(
			"ap_output_logs",
			sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
			sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
			sa.Column("line_id", sa.Integer(), sa.ForeignKey("ap_lines.id", ondelete="CASCADE"), nullable=False),
			sa.Column("shift_id", sa.Integer(), sa.ForeignKey("ap_shifts.id", ondelete="SET NULL"), nullable=True),
			sa.Column("operator_person_id", sa.Integer(), sa.ForeignKey("persons.id", ondelete="SET NULL"), nullable=True),
			sa.Column("product_id", sa.Integer(), sa.ForeignKey("products.id", ondelete="RESTRICT"), nullable=False),
			sa.Column("produced_on", sa.Date(), nullable=False),
			sa.Column("run_minutes", sa.Integer(), nullable=False),
			sa.Column("quantity_good", sa.Numeric(18, 6), nullable=False),
			sa.Column("quantity_scrap", sa.Numeric(18, 6), nullable=False, server_default="0"),
		)
	if need("ap_qc_inspections"):
		op.create_table(
			"ap_qc_inspections",
			sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
			sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
			sa.Column("product_id", sa.Integer(), sa.ForeignKey("products.id", ondelete="RESTRICT"), nullable=False),
			sa.Column("stage", sa.String(16), nullable=False),
			sa.Column("inspected_on", sa.Date(), nullable=False),
			sa.Column("quantity_checked", sa.Numeric(18, 6), nullable=False),
			sa.Column("quantity_rejected", sa.Numeric(18, 6), nullable=False, server_default="0"),
			sa.Column("result", sa.String(16), nullable=False),
			sa.Column("notes", sa.Text(), nullable=True),
		)


def downgrade() -> None:
	for name in (
		"ap_qc_inspections",
		"ap_output_logs",
		"ap_downtime",
		"ap_shifts",
		"ap_machines",
		"ap_lines",
		"ap_work_centers",
	):
		op.drop_table(name)
