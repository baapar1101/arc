"""Merge heads: business_user_menu_preferences + notification_send_logs_and_daily_stats

Revision ID: 20260611_000002_merge_heads_business_user_menu_preferences_and_notification_stats
Revises: 20260611_000001_business_user_menu_preferences, 20260611_000001_notification_send_logs_and_daily_stats
Create Date: 2026-06-11

"""

from __future__ import annotations

from alembic import op  # noqa: F401

revision = "20260611_000002_merge_heads_business_user_menu_preferences_and_notification_stats"
down_revision = (
	"20260611_000001_business_user_menu_preferences",
	"20260611_000001_notification_send_logs_and_daily_stats",
)
branch_labels = None
depends_on = None


def upgrade() -> None:
	pass


def downgrade() -> None:
	pass
