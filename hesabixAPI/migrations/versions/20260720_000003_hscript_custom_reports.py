"""جداول گزارش سفارشی HScript

Revision ID: 20260720_000003_hscript_custom_reports
Revises: 20260720_000002_goods_expense_income
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260720_000003_hscript_custom_reports"
down_revision = "20260720_000002_goods_expense_income"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"hscript_reports",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("slug", sa.String(length=80), nullable=False),
		sa.Column("title", sa.String(length=255), nullable=False),
		sa.Column("description", sa.Text(), nullable=True),
		sa.Column("status", sa.String(length=32), nullable=False, server_default="draft"),
		sa.Column("source_code", sa.Text(), nullable=False, server_default=""),
		sa.Column("source_hash", sa.String(length=64), nullable=True),
		sa.Column("language_version", sa.String(length=16), nullable=False, server_default="1.0.0"),
		sa.Column("default_params", sa.JSON(), nullable=True),
		sa.Column("created_by_user_id", sa.Integer(), nullable=True),
		sa.Column("updated_by_user_id", sa.Integer(), nullable=True),
		sa.Column("published_at", sa.DateTime(timezone=True), nullable=True),
		sa.Column("is_deleted", sa.Boolean(), nullable=False, server_default=sa.text("false")),
		sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
		sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["updated_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "slug", name="uq_hscript_reports_business_slug"),
	)
	op.create_index("ix_hscript_reports_business_id", "hscript_reports", ["business_id"])
	op.create_index("ix_hscript_reports_status", "hscript_reports", ["status"])
	op.create_index("ix_hscript_reports_is_deleted", "hscript_reports", ["is_deleted"])

	op.create_table(
		"hscript_report_versions",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("report_id", sa.Integer(), nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("version_no", sa.Integer(), nullable=False),
		sa.Column("source_code", sa.Text(), nullable=False),
		sa.Column("source_hash", sa.String(length=64), nullable=False),
		sa.Column("language_version", sa.String(length=16), nullable=False, server_default="1.0.0"),
		sa.Column("changelog", sa.Text(), nullable=True),
		sa.Column("created_by_user_id", sa.Integer(), nullable=True),
		sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["report_id"], ["hscript_reports.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("report_id", "version_no", name="uq_hscript_report_versions_no"),
	)
	op.create_index("ix_hscript_report_versions_report_id", "hscript_report_versions", ["report_id"])
	op.create_index("ix_hscript_report_versions_business_id", "hscript_report_versions", ["business_id"])

	op.create_table(
		"hscript_report_runs",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("report_id", sa.Integer(), nullable=True),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("version_id", sa.Integer(), nullable=True),
		sa.Column("ran_by_user_id", sa.Integer(), nullable=True),
		sa.Column("status", sa.String(length=32), nullable=False),
		sa.Column("is_preview", sa.Boolean(), nullable=False, server_default=sa.text("false")),
		sa.Column("source_hash", sa.String(length=64), nullable=True),
		sa.Column("params", sa.JSON(), nullable=True),
		sa.Column("result_spec", sa.JSON(), nullable=True),
		sa.Column("error", sa.JSON(), nullable=True),
		sa.Column("stats", sa.JSON(), nullable=True),
		sa.Column("duration_ms", sa.Integer(), nullable=True),
		sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["ran_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["report_id"], ["hscript_reports.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["version_id"], ["hscript_report_versions.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_hscript_report_runs_business_id", "hscript_report_runs", ["business_id"])
	op.create_index("ix_hscript_report_runs_report_id", "hscript_report_runs", ["report_id"])
	op.create_index("ix_hscript_report_runs_status", "hscript_report_runs", ["status"])


def downgrade() -> None:
	op.drop_table("hscript_report_runs")
	op.drop_table("hscript_report_versions")
	op.drop_table("hscript_reports")
