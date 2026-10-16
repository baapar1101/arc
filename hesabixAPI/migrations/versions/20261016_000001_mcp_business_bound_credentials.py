"""Bind MCP credentials to a single business.

Revision ID: 20261016_000001_mcp_business_bound_credentials
Revises: 20261014_000002_quick_sales_customer_group
"""

import sqlalchemy as sa
from alembic import op


revision = "20261016_000001_mcp_business_bound_credentials"
down_revision = "20261014_000002_quick_sales_customer_group"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("api_keys", sa.Column("business_id", sa.Integer(), nullable=True))
    op.create_index("ix_api_keys_business_id", "api_keys", ["business_id"])
    op.create_foreign_key(
        "fk_api_keys_business_id_businesses",
        "api_keys",
        "businesses",
        ["business_id"],
        ["id"],
        ondelete="CASCADE",
    )


def downgrade() -> None:
    op.drop_constraint("fk_api_keys_business_id_businesses", "api_keys", type_="foreignkey")
    op.drop_index("ix_api_keys_business_id", table_name="api_keys")
    op.drop_column("api_keys", "business_id")
