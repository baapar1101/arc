"""Add optional currency symbols to printed invoice amounts."""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261026_000001_business_print_settings_currency_symbol"
down_revision = "20261025_000001_customer_club_rewards_campaigns"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"business_print_settings",
		sa.Column("show_currency_symbol", sa.Boolean(), nullable=False, server_default=sa.text("false")),
	)


def downgrade() -> None:
	op.drop_column("business_print_settings", "show_currency_symbol")
