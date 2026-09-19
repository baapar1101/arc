"""جدول زمان‌بندی گزارش‌های HScript

Revision ID: 20260726_000002_hscript_schedules
Revises: 20260726_000001_business_ai_provider_configs
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260726_000002_hscript_schedules"
down_revision = "20260726_000001_business_ai_provider_configs"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"hscript_report_schedules",
		sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
		sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
		sa.Column("report_id", sa.Integer(), sa.ForeignKey("hscript_reports.id", ondelete="CASCADE"), nullable=False),
		sa.Column("title", sa.String(255), nullable=False, server_default=""),
		sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("schedule_mode", sa.String(32), nullable=False, server_default="simple"),
		sa.Column("simple_repeat", sa.String(32), nullable=True),
		sa.Column("simple_time", sa.String(8), nullable=True),
		sa.Column("simple_weekday", sa.Integer(), nullable=True),
		sa.Column("simple_interval", sa.Integer(), nullable=True),
		sa.Column("cron_expression", sa.String(120), nullable=True),
		sa.Column("timezone", sa.String(64), nullable=False, server_default="Asia/Tehran"),
		sa.Column("output_format", sa.String(16), nullable=False, server_default="pdf"),
		sa.Column("channels", sa.JSON(), nullable=True),
		sa.Column("recipient_user_ids", sa.JSON(), nullable=True),
		sa.Column("params", sa.JSON(), nullable=True),
		sa.Column("next_run_at", sa.DateTime(timezone=True), nullable=True),
		sa.Column("last_run_at", sa.DateTime(timezone=True), nullable=True),
		sa.Column("last_run_status", sa.String(32), nullable=True),
		sa.Column("last_run_message", sa.Text(), nullable=True),
		sa.Column("created_by_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
		sa.Column("updated_by_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
		sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
		sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
	)
	op.create_index("ix_hscript_report_schedules_business_id", "hscript_report_schedules", ["business_id"])
	op.create_index("ix_hscript_report_schedules_report_id", "hscript_report_schedules", ["report_id"])
	op.create_index("ix_hscript_report_schedules_enabled", "hscript_report_schedules", ["enabled"])
	op.create_index("ix_hscript_report_schedules_next_run_at", "hscript_report_schedules", ["next_run_at"])


def downgrade() -> None:
	op.drop_index("ix_hscript_report_schedules_next_run_at", table_name="hscript_report_schedules")
	op.drop_index("ix_hscript_report_schedules_enabled", table_name="hscript_report_schedules")
	op.drop_index("ix_hscript_report_schedules_report_id", table_name="hscript_report_schedules")
	op.drop_index("ix_hscript_report_schedules_business_id", table_name="hscript_report_schedules")
	op.drop_table("hscript_report_schedules")
