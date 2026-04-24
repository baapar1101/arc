"""جدول تنظیمات ستون DataTable (کاربر/کسب‌وکار)

Revision ID: 20260504_000002_data_table_user_column_settings
Revises: 20260504_000001_business_dashboard_layout_tables
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260504_000002_data_table_user_column_settings"
down_revision = "20260504_000001_business_dashboard_layout_tables"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"data_table_user_column_settings",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("user_id", sa.Integer(), nullable=False),
		sa.Column("table_id", sa.String(length=255), nullable=False),
		sa.Column("settings", sa.JSON(), nullable=False),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "user_id", "table_id", name="uq_dtucs_business_user_table"),
	)
	op.create_index(
		"ix_data_table_user_column_settings_business_id", "data_table_user_column_settings", ["business_id"], unique=False
	)
	op.create_index(
		"ix_data_table_user_column_settings_user_id", "data_table_user_column_settings", ["user_id"], unique=False
	)
	op.create_index(
		"ix_data_table_user_column_settings_table_id", "data_table_user_column_settings", ["table_id"], unique=False
	)


def downgrade() -> None:
	op.drop_index("ix_data_table_user_column_settings_table_id", table_name="data_table_user_column_settings")
	op.drop_index("ix_data_table_user_column_settings_user_id", table_name="data_table_user_column_settings")
	op.drop_index("ix_data_table_user_column_settings_business_id", table_name="data_table_user_column_settings")
	op.drop_table("data_table_user_column_settings")
