"""جدول‌های notification_send_logs و notification_daily_stats (PostgreSQL)

مدل‌ها از قبل در adapters/db/models/business_notification.py بودند ولی migration اضافه نشده بود.

Revision ID: 20260611_000001_notification_send_logs_and_daily_stats
Revises: 20260610_000002_business_print_settings_footer_meta
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "20260611_000001_notification_send_logs_and_daily_stats"
down_revision = "20260610_000002_business_print_settings_footer_meta"
branch_labels = None
depends_on = None


def upgrade() -> None:
	conn = op.get_bind()
	insp = sa.inspect(conn)

	enum_recipient = postgresql.ENUM("person", "user", name="recipient_type_enum")
	enum_send_channel = postgresql.ENUM("sms", "email", name="send_channel")
	enum_send_status = postgresql.ENUM(
		"pending", "sent", "failed", "rejected", name="send_status"
	)
	enum_stats_channel = postgresql.ENUM("sms", "email", name="stats_channel")

	for e in (enum_recipient, enum_send_channel, enum_send_status, enum_stats_channel):
		e.create(conn, checkfirst=True)

	col_recipient = postgresql.ENUM(
		"person", "user", name="recipient_type_enum", create_type=False
	)
	col_send_channel = postgresql.ENUM(
		"sms", "email", name="send_channel", create_type=False
	)
	col_send_status = postgresql.ENUM(
		"pending", "sent", "failed", "rejected", name="send_status", create_type=False
	)
	col_stats_channel = postgresql.ENUM(
		"sms", "email", name="stats_channel", create_type=False
	)

	if "notification_send_logs" not in insp.get_table_names():
		op.create_table(
			"notification_send_logs",
			sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
			sa.Column("business_id", sa.Integer(), nullable=False),
			sa.Column("template_id", sa.Integer(), nullable=True),
			sa.Column("recipient_type", col_recipient, nullable=False),
			sa.Column("recipient_id", sa.Integer(), nullable=False),
			sa.Column("recipient_identifier", sa.String(length=100), nullable=True),
			sa.Column("channel", col_send_channel, nullable=False),
			sa.Column("subject", sa.String(length=200), nullable=True),
			sa.Column("body", sa.Text(), nullable=False),
			sa.Column("context_data", sa.JSON(), nullable=True),
			sa.Column("status", col_send_status, nullable=False),
			sa.Column("sent_at", sa.DateTime(), nullable=True),
			sa.Column("failed_at", sa.DateTime(), nullable=True),
			sa.Column("failure_reason", sa.Text(), nullable=True),
			sa.Column("provider_name", sa.String(length=50), nullable=True),
			sa.Column("provider_message_id", sa.String(length=200), nullable=True),
			sa.Column("cost", sa.Numeric(10, 2), nullable=True),
			sa.Column("triggered_by_user_id", sa.Integer(), nullable=True),
			sa.Column("event_type", sa.String(length=100), nullable=True),
			sa.Column("created_at", sa.DateTime(), nullable=False),
			sa.ForeignKeyConstraint(
				["business_id"],
				["businesses.id"],
				ondelete="CASCADE",
			),
			sa.ForeignKeyConstraint(
				["template_id"],
				["business_notification_templates.id"],
				ondelete="SET NULL",
			),
			sa.PrimaryKeyConstraint("id"),
		)
		op.create_index(
			"ix_notification_send_logs_business_id",
			"notification_send_logs",
			["business_id"],
		)
		op.create_index(
			"ix_notification_send_logs_template_id",
			"notification_send_logs",
			["template_id"],
		)
		op.create_index(
			"ix_notification_send_logs_recipient_id",
			"notification_send_logs",
			["recipient_id"],
		)
		op.create_index(
			"ix_notification_send_logs_status",
			"notification_send_logs",
			["status"],
		)

	if "notification_daily_stats" not in insp.get_table_names():
		op.create_table(
			"notification_daily_stats",
			sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
			sa.Column("business_id", sa.Integer(), nullable=False),
			sa.Column("template_id", sa.Integer(), nullable=True),
			sa.Column("date", sa.Date(), nullable=False),
			sa.Column("channel", col_stats_channel, nullable=False),
			sa.Column("total_sent", sa.Integer(), nullable=False),
			sa.Column("total_failed", sa.Integer(), nullable=False),
			sa.Column("total_cost", sa.Numeric(10, 2), nullable=False),
			sa.Column("created_at", sa.DateTime(), nullable=False),
			sa.Column("updated_at", sa.DateTime(), nullable=False),
			sa.ForeignKeyConstraint(
				["business_id"],
				["businesses.id"],
				ondelete="CASCADE",
			),
			sa.ForeignKeyConstraint(
				["template_id"],
				["business_notification_templates.id"],
				ondelete="SET NULL",
			),
			sa.PrimaryKeyConstraint("id"),
			sa.UniqueConstraint(
				"business_id",
				"template_id",
				"date",
				"channel",
				name="uk_daily_stats",
			),
		)
		op.create_index(
			"ix_notification_daily_stats_business_id",
			"notification_daily_stats",
			["business_id"],
		)


def downgrade() -> None:
	conn = op.get_bind()
	insp = sa.inspect(conn)

	if "notification_daily_stats" in insp.get_table_names():
		op.drop_index(
			"ix_notification_daily_stats_business_id",
			table_name="notification_daily_stats",
		)
		op.drop_table("notification_daily_stats")

	if "notification_send_logs" in insp.get_table_names():
		op.drop_index("ix_notification_send_logs_status", table_name="notification_send_logs")
		op.drop_index(
			"ix_notification_send_logs_recipient_id",
			table_name="notification_send_logs",
		)
		op.drop_index(
			"ix_notification_send_logs_template_id",
			table_name="notification_send_logs",
		)
		op.drop_index(
			"ix_notification_send_logs_business_id",
			table_name="notification_send_logs",
		)
		op.drop_table("notification_send_logs")

	postgresql.ENUM(name="stats_channel").drop(conn, checkfirst=True)
	postgresql.ENUM(name="send_status").drop(conn, checkfirst=True)
	postgresql.ENUM(name="send_channel").drop(conn, checkfirst=True)
	postgresql.ENUM(name="recipient_type_enum").drop(conn, checkfirst=True)
