"""افزودن باندل‌های کالا برای ورود سریع اقلام فاکتور فروش.

Revision ID: 20261003_000001_product_bundles
Revises: 20260907_000002_distribution_field_ops_upgrade
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261003_000001_product_bundles"
down_revision = "20260907_000002_distribution_field_ops_upgrade"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "product_bundles",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("business_id", sa.Integer(), nullable=False),
        sa.Column("name", sa.String(length=255), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("business_id", "name", name="uq_product_bundles_business_name"),
    )
    op.create_index("ix_product_bundles_business_id", "product_bundles", ["business_id"])
    op.create_index("ix_product_bundles_name", "product_bundles", ["name"])
    op.create_index("ix_product_bundles_is_active", "product_bundles", ["is_active"])

    op.create_table(
        "product_bundle_items",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("bundle_id", sa.Integer(), nullable=False),
        sa.Column("product_id", sa.Integer(), nullable=False),
        sa.Column("quantity", sa.Numeric(precision=18, scale=6), nullable=False),
        sa.Column("line_order", sa.Integer(), nullable=False),
        sa.ForeignKeyConstraint(["bundle_id"], ["product_bundles.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["product_id"], ["products.id"], ondelete="RESTRICT"),
        sa.CheckConstraint("quantity > 0", name="ck_product_bundle_items_quantity_positive"),
        sa.CheckConstraint("line_order > 0", name="ck_product_bundle_items_line_order_positive"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("bundle_id", "product_id", name="uq_product_bundle_items_product"),
        sa.UniqueConstraint("bundle_id", "line_order", name="uq_product_bundle_items_line_order"),
    )
    op.create_index("ix_product_bundle_items_bundle_id", "product_bundle_items", ["bundle_id"])
    op.create_index("ix_product_bundle_items_product_id", "product_bundle_items", ["product_id"])


def downgrade() -> None:
    op.drop_index("ix_product_bundle_items_product_id", table_name="product_bundle_items")
    op.drop_index("ix_product_bundle_items_bundle_id", table_name="product_bundle_items")
    op.drop_table("product_bundle_items")
    op.drop_index("ix_product_bundles_is_active", table_name="product_bundles")
    op.drop_index("ix_product_bundles_name", table_name="product_bundles")
    op.drop_index("ix_product_bundles_business_id", table_name="product_bundles")
    op.drop_table("product_bundles")
