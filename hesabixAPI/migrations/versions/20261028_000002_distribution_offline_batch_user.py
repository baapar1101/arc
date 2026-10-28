"""Scope offline sync batch uniqueness to the acting user.

Revision ID: 20261028_000002_distribution_offline_batch_user
Revises: 20261028_000001_merge_print_currency_and_purchase_price_heads
"""

from __future__ import annotations

from alembic import op

revision = "20261028_000002_distribution_offline_batch_user"
down_revision = "20261028_000001_merge_print_currency_and_purchase_price_heads"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.drop_constraint("uq_distribution_offline_batch", "distribution_offline_sync_batches", type_="unique")
	op.create_unique_constraint(
		"uq_distribution_offline_batch_user",
		"distribution_offline_sync_batches",
		["business_id", "user_id", "client_batch_id"],
	)


def downgrade() -> None:
	op.drop_constraint("uq_distribution_offline_batch_user", "distribution_offline_sync_batches", type_="unique")
	op.create_unique_constraint(
		"uq_distribution_offline_batch",
		"distribution_offline_sync_batches",
		["business_id", "client_batch_id"],
	)
