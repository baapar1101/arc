"""ستون‌های نمایش زمان چاپ و تهیه‌کننده در پاورقی PDF

Revision ID: 20260610_000002_business_print_settings_footer_meta
Revises: 20260610_000001_user_inapp_alert_preferences
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260610_000002_business_print_settings_footer_meta"
down_revision = "20260610_000001_user_inapp_alert_preferences"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"business_print_settings",
		sa.Column(
			"show_footer_print_time",
			sa.Boolean(),
			nullable=False,
			server_default=sa.text("true"),
		),
	)
	op.add_column(
		"business_print_settings",
		sa.Column(
			"show_footer_preparer",
			sa.Boolean(),
			nullable=False,
			server_default=sa.text("true"),
		),
	)


def downgrade() -> None:
	op.drop_column("business_print_settings", "show_footer_preparer")
	op.drop_column("business_print_settings", "show_footer_print_time")
