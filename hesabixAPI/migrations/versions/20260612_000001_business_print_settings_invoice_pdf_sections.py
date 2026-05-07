"""تنظیمات چاپ: تراز مشتری و بلوک امضای فروشنده/خریدار در PDF فاکتور

Revision ID: 20260612_000001_business_print_settings_invoice_pdf_sections
Revises: 20260611_000002_merge_heads_business_user_menu_preferences_and_notification_stats
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260612_000001_business_print_settings_invoice_pdf_sections"
down_revision = "20260611_000002_merge_heads_business_user_menu_preferences_and_notification_stats"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"business_print_settings",
		sa.Column(
			"show_customer_balance",
			sa.Boolean(),
			nullable=False,
			server_default=sa.text("true"),
		),
	)
	op.add_column(
		"business_print_settings",
		sa.Column(
			"show_seller_signature_area",
			sa.Boolean(),
			nullable=False,
			server_default=sa.text("true"),
		),
	)
	op.add_column(
		"business_print_settings",
		sa.Column(
			"show_buyer_signature_area",
			sa.Boolean(),
			nullable=False,
			server_default=sa.text("true"),
		),
	)


def downgrade() -> None:
	op.drop_column("business_print_settings", "show_buyer_signature_area")
	op.drop_column("business_print_settings", "show_seller_signature_area")
	op.drop_column("business_print_settings", "show_customer_balance")
