"""جدول ترجیحات هشدار درون‌برنامه‌ای کاربر

Revision ID: 20260610_000001_user_inapp_alert_preferences
Revises: 20260609_000001_product_general_barcodes
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260610_000001_user_inapp_alert_preferences"
down_revision = "20260609_000001_product_general_barcodes"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"user_inapp_alert_preferences",
		sa.Column("user_id", sa.Integer(), nullable=False),
		sa.Column("alert_mode", sa.String(length=32), nullable=False, server_default="normal"),
		sa.Column("sound_enabled", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("sound_asset_id", sa.String(length=64), nullable=False, server_default="default"),
		sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.text("now()")),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("user_id"),
	)


def downgrade() -> None:
	op.drop_table("user_inapp_alert_preferences")
