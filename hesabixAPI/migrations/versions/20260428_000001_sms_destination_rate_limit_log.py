"""جدول لاگ ارسال SMS به مقصد برای سقف نرخ به‌ازای شماره

Revision ID: 20260428_000001_sms_destination_rate_limit_log
Revises: 20260427_000001_business_fx_revaluation_policy
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260428_000001_sms_destination_rate_limit_log"
down_revision = "20260427_000001_business_fx_revaluation_policy"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"sms_destination_send_logs",
		sa.Column("id", sa.BigInteger(), autoincrement=True, nullable=False),
		sa.Column("destination_phone", sa.String(length=32), nullable=False),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index(
		"ix_sms_destination_send_logs_destination_phone",
		"sms_destination_send_logs",
		["destination_phone"],
	)
	op.create_index(
		"ix_sms_destination_send_logs_created_at",
		"sms_destination_send_logs",
		["created_at"],
	)
	op.create_index(
		"ix_sms_dest_phone_created",
		"sms_destination_send_logs",
		["destination_phone", "created_at"],
	)


def downgrade() -> None:
	op.drop_index("ix_sms_dest_phone_created", table_name="sms_destination_send_logs")
	op.drop_index("ix_sms_destination_send_logs_created_at", table_name="sms_destination_send_logs")
	op.drop_index("ix_sms_destination_send_logs_destination_phone", table_name="sms_destination_send_logs")
	op.drop_table("sms_destination_send_logs")
