"""جدول چیدمان داشبورد پروفایل کاربر

Revision ID: 20260613_000003_profile_user_dashboard_layouts
Revises: 20260701_000001_backfill_notification_event_type_defaults
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260613_000003_profile_user_dashboard_layouts"
down_revision = "20260701_000001_backfill_notification_event_type_defaults"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"profile_user_dashboard_layouts",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("user_id", sa.Integer(), nullable=False),
		sa.Column("breakpoint", sa.String(length=8), nullable=False),
		sa.Column("items", sa.JSON(), nullable=False),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("user_id", "breakpoint", name="uq_pudl_user_bp"),
	)
	op.create_index(
		"ix_profile_user_dashboard_layouts_user_id",
		"profile_user_dashboard_layouts",
		["user_id"],
		unique=False,
	)
	op.create_index(
		"ix_profile_user_dashboard_layouts_breakpoint",
		"profile_user_dashboard_layouts",
		["breakpoint"],
		unique=False,
	)


def downgrade() -> None:
	op.drop_index("ix_profile_user_dashboard_layouts_breakpoint", table_name="profile_user_dashboard_layouts")
	op.drop_index("ix_profile_user_dashboard_layouts_user_id", table_name="profile_user_dashboard_layouts")
	op.drop_table("profile_user_dashboard_layouts")
