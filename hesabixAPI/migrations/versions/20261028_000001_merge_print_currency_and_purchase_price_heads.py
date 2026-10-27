"""Merge print currency symbol and purchase-price profit contract heads.

Revision ID: 20261028_000001_merge_print_currency_and_purchase_price_heads
Revises: 20261027_000001_sync_print_currency_symbol_per_type, 20261026_000001_purchase_price_profit_contracts
"""

from __future__ import annotations

revision = "20261028_000001_merge_print_currency_and_purchase_price_heads"
down_revision = (
    "20261027_000001_sync_print_currency_symbol_per_type",
    "20261026_000001_purchase_price_profit_contracts",
)
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
