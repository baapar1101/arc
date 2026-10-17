"""Merge tax provider and quick-sales payment button migration heads.

Revision ID: 20261014_000001_merge_tax_and_quick_sales_heads
Revises: 20261012_000002_tax_provider_accounts, 20261013_000001_quick_sales_payment_buttons
"""

revision = "20261014_000001_merge_tax_and_quick_sales_heads"
down_revision = (
    "20261012_000002_tax_provider_accounts",
    "20261013_000001_quick_sales_payment_buttons",
)
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
