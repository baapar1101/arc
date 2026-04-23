"""ستون show_share_qr برای تنظیمات چاپ کسب‌وکار

Revision ID: 20260429_000001_business_print_settings_show_share_qr
Revises: 20260428_000001_sms_destination_rate_limit_log
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260429_000001_business_print_settings_show_share_qr"
down_revision = "20260428_000001_sms_destination_rate_limit_log"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"business_print_settings",
		sa.Column(
			"show_share_qr",
			sa.Boolean(),
			nullable=False,
			server_default=sa.text("false"),
		),
	)


def downgrade() -> None:
	op.drop_column("business_print_settings", "show_share_qr")
