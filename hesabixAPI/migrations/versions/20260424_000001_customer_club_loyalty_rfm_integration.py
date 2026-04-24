"""باشگاه مشتریان: حالت یکپارچگی امتیاز با RFM و آستانهٔ سطح RFM

Revision ID: 20260424_000001_customer_club_loyalty_rfm_integration
Revises: 20260423_000001_invoice_global_discount_settings
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260424_000001_customer_club_loyalty_rfm_integration"
down_revision = "20260423_000001_invoice_global_discount_settings"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"customer_club_settings",
		sa.Column(
			"loyalty_rfm_integration_mode",
			sa.String(length=32),
			nullable=False,
			server_default="decoupled",
			comment="decoupled | rfm_based_tiers",
		),
	)
	op.add_column(
		"customer_club_tiers",
		sa.Column(
			"min_rfm_normalized",
			sa.Numeric(10, 6),
			nullable=True,
			comment="حداقل نمرهٔ نرمال‌شدهٔ RFM (۰ تا ۱) برای این سطح وقتی حالت rfm_based_tiers فعال است",
		),
	)


def downgrade() -> None:
	op.drop_column("customer_club_tiers", "min_rfm_normalized")
	op.drop_column("customer_club_settings", "loyalty_rfm_integration_mode")
