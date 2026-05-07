"""ایجاد جدول رخدادهای تغییر وضعیت قالب گزارش

Revision ID: 20260611_000002_report_template_status_events
Revises: 20260611_000001_notification_send_logs_and_daily_stats
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260611_000002_report_template_status_events"
down_revision = "20260611_000001_notification_send_logs_and_daily_stats"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"report_template_status_events",
		sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
		sa.Column(
			"report_template_id",
			sa.Integer(),
			sa.ForeignKey("report_templates.id", ondelete="CASCADE"),
			nullable=False,
		),
		sa.Column(
			"business_id",
			sa.Integer(),
			sa.ForeignKey("businesses.id", ondelete="CASCADE"),
			nullable=False,
		),
		sa.Column("from_status", sa.String(length=32), nullable=True),
		sa.Column("to_status", sa.String(length=32), nullable=False),
		sa.Column("reason", sa.Text(), nullable=True),
		sa.Column(
			"actor_user_id",
			sa.Integer(),
			sa.ForeignKey("users.id", ondelete="SET NULL"),
			nullable=True,
		),
		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
	)
	op.create_index(
		"ix_report_template_status_events_report_template_id",
		"report_template_status_events",
		["report_template_id"],
	)
	op.create_index(
		"ix_report_template_status_events_business_id",
		"report_template_status_events",
		["business_id"],
	)
	op.create_index(
		"ix_report_template_status_events_actor_user_id",
		"report_template_status_events",
		["actor_user_id"],
	)
	op.create_index(
		"ix_report_template_status_events_created_at",
		"report_template_status_events",
		["created_at"],
	)


def downgrade() -> None:
	op.drop_index("ix_report_template_status_events_created_at", table_name="report_template_status_events")
	op.drop_index("ix_report_template_status_events_actor_user_id", table_name="report_template_status_events")
	op.drop_index("ix_report_template_status_events_business_id", table_name="report_template_status_events")
	op.drop_index("ix_report_template_status_events_report_template_id", table_name="report_template_status_events")
	op.drop_table("report_template_status_events")

