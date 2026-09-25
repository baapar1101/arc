"""زمان‌بندی خودکار ثبت نرخ تسعیر کسب‌وکار + آفست per ارز.

Revision ID: 20260718_000002_business_fx_auto_sync
Revises: 20260718_000001_fx_rate_providers_global_rates
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "20260718_000002_business_fx_auto_sync"
down_revision = "20260718_000001_fx_rate_providers_global_rates"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"business_fx_auto_sync_settings",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.text("false")),
		sa.Column("schedule_mode", sa.String(length=20), nullable=False, server_default="interval"),
		sa.Column("interval_hours", sa.Integer(), nullable=True, server_default="6"),
		sa.Column("daily_times", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
		sa.Column("timezone", sa.String(length=64), nullable=True),
		sa.Column("skip_if_unchanged", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("min_change_percent", sa.Numeric(10, 6), nullable=False, server_default="0.01"),
		sa.Column("block_if_stale", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("stale_after_hours", sa.Integer(), nullable=False, server_default="24"),
		sa.Column("updated_by_user_id", sa.Integer(), nullable=True),
		sa.Column("last_run_at", sa.DateTime(timezone=True), nullable=True),
		sa.Column("last_run_status", sa.String(length=32), nullable=True),
		sa.Column("last_run_message", sa.Text(), nullable=True),
		sa.Column("next_run_at", sa.DateTime(timezone=True), nullable=True),
		sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
		sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["updated_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", name="uq_fx_auto_sync_settings_business"),
	)
	op.create_index("ix_fx_auto_sync_settings_business_id", "business_fx_auto_sync_settings", ["business_id"])
	op.create_index("ix_fx_auto_sync_settings_next_run_at", "business_fx_auto_sync_settings", ["next_run_at"])

	op.create_table(
		"business_fx_auto_sync_currency_rules",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("settings_id", sa.Integer(), nullable=False),
		sa.Column("currency_id", sa.Integer(), nullable=False),
		sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("offset_type", sa.String(length=16), nullable=False, server_default="none"),
		sa.Column("offset_direction", sa.String(length=8), nullable=False, server_default="up"),
		sa.Column("offset_value", sa.Numeric(24, 10), nullable=False, server_default="0"),
		sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
		sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["settings_id"], ["business_fx_auto_sync_settings.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["currency_id"], ["currencies.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "currency_id", name="uq_fx_auto_sync_rule_business_currency"),
	)
	op.create_index("ix_fx_auto_sync_rules_business_id", "business_fx_auto_sync_currency_rules", ["business_id"])
	op.create_index("ix_fx_auto_sync_rules_settings_id", "business_fx_auto_sync_currency_rules", ["settings_id"])
	op.create_index("ix_fx_auto_sync_rules_currency_id", "business_fx_auto_sync_currency_rules", ["currency_id"])


def downgrade() -> None:
	op.drop_index("ix_fx_auto_sync_rules_currency_id", table_name="business_fx_auto_sync_currency_rules")
	op.drop_index("ix_fx_auto_sync_rules_settings_id", table_name="business_fx_auto_sync_currency_rules")
	op.drop_index("ix_fx_auto_sync_rules_business_id", table_name="business_fx_auto_sync_currency_rules")
	op.drop_table("business_fx_auto_sync_currency_rules")
	op.drop_index("ix_fx_auto_sync_settings_next_run_at", table_name="business_fx_auto_sync_settings")
	op.drop_index("ix_fx_auto_sync_settings_business_id", table_name="business_fx_auto_sync_settings")
	op.drop_table("business_fx_auto_sync_settings")
