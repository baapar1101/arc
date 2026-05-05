"""پیکربندی منوی پنل کسب‌وکار به‌ازای کاربر

Revision ID: 20260611_000001_business_user_menu_preferences
Revises: 20260610_000002_business_print_settings_footer_meta
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260611_000001_business_user_menu_preferences"
down_revision = "20260610_000002_business_print_settings_footer_meta"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"business_user_menu_preferences",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("user_id", sa.Integer(), nullable=False),
		sa.Column("preferences", sa.JSON(), nullable=False),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "user_id", name="uq_bump_business_user"),
	)
	op.create_index(
		"ix_business_user_menu_preferences_business_id",
		"business_user_menu_preferences",
		["business_id"],
		unique=False,
	)
	op.create_index(
		"ix_business_user_menu_preferences_user_id",
		"business_user_menu_preferences",
		["user_id"],
		unique=False,
	)


def downgrade() -> None:
	op.drop_index("ix_business_user_menu_preferences_user_id", table_name="business_user_menu_preferences")
	op.drop_index("ix_business_user_menu_preferences_business_id", table_name="business_user_menu_preferences")
	op.drop_table("business_user_menu_preferences")
