"""Optional per-variant sales/purchase price override.

Revision ID: 20261101_000003_product_variant_prices
Revises: 20261101_000002_product_variants_core
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261101_000003_product_variant_prices"
down_revision = "20261101_000002_product_variants_core"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "product_variants",
        sa.Column("sales_price", sa.Numeric(18, 2), nullable=True),
    )
    op.add_column(
        "product_variants",
        sa.Column("purchase_price", sa.Numeric(18, 2), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("product_variants", "purchase_price")
    op.drop_column("product_variants", "sales_price")
