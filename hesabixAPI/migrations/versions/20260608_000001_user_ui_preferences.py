"""جدول ترجیحات رابط کاربر (کاربر)

Revision ID: 20260608_000001_user_ui_preferences
Revises: 20260607_000001_users_last_activity_signature
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260608_000001_user_ui_preferences"
down_revision = "20260607_000001_users_last_activity_signature"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"user_ui_preferences",
		sa.Column("user_id", sa.Integer(), nullable=False),
		sa.Column("preferences", sa.JSON(), nullable=False),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("user_id"),
	)


def downgrade() -> None:
	op.drop_table("user_ui_preferences")
