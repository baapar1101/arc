"""Purchase-price profit contracts and line snapshots.

Revision ID: 20261026_000001_purchase_price_profit_contracts
Revises: 20261025_000001_customer_club_rewards_campaigns
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261026_000001_purchase_price_profit_contracts"
down_revision = "20261025_000001_customer_club_rewards_campaigns"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"businesses",
		sa.Column(
			"invoice_profit_missing_purchase_price_policy",
			sa.String(length=40),
			nullable=False,
			server_default="zero_cost",
		),
	)
	op.add_column(
		"businesses",
		sa.Column(
			"invoice_sync_purchase_price_multi_line_policy",
			sa.String(length=40),
			nullable=False,
			server_default="weighted_average",
		),
	)
	op.add_column("invoice_item_lines", sa.Column("purchase_price_snapshot_unit_cost_base", sa.Numeric(18, 6), nullable=True))
	op.add_column("invoice_item_lines", sa.Column("purchase_price_snapshot_currency_id", sa.Integer(), nullable=True))
	op.add_column("invoice_item_lines", sa.Column("purchase_price_snapshot_unit", sa.String(length=32), nullable=True))
	op.add_column("invoice_item_lines", sa.Column("purchase_price_snapshot_factor", sa.Numeric(18, 6), nullable=True))
	op.add_column("invoice_item_lines", sa.Column("purchase_price_snapshot_source", sa.String(length=40), nullable=True))
	op.add_column("invoice_item_lines", sa.Column("purchase_price_snapshot_at", sa.DateTime(), nullable=True))
	op.add_column("products", sa.Column("base_purchase_price_sync_meta", sa.JSON(), nullable=True))


def downgrade() -> None:
	op.drop_column("products", "base_purchase_price_sync_meta")
	op.drop_column("invoice_item_lines", "purchase_price_snapshot_at")
	op.drop_column("invoice_item_lines", "purchase_price_snapshot_source")
	op.drop_column("invoice_item_lines", "purchase_price_snapshot_factor")
	op.drop_column("invoice_item_lines", "purchase_price_snapshot_unit")
	op.drop_column("invoice_item_lines", "purchase_price_snapshot_currency_id")
	op.drop_column("invoice_item_lines", "purchase_price_snapshot_unit_cost_base")
	op.drop_column("businesses", "invoice_sync_purchase_price_multi_line_policy")
	op.drop_column("businesses", "invoice_profit_missing_purchase_price_policy")
