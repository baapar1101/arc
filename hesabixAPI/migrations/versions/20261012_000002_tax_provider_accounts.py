"""Add extensible tax provider credentials and broker-provisioned business accounts.

Revision ID: 20261012_000002_tax_provider_accounts
Revises: 20261012_000001_quick_sales_stock_shortage
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261012_000002_tax_provider_accounts"
down_revision = "20261012_000001_quick_sales_stock_shortage"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "tax_settings",
        sa.Column("submission_provider", sa.String(length=40), nullable=False, server_default="moadian_direct"),
    )
    op.create_table(
        "tax_provider_credentials",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("provider_code", sa.String(length=40), nullable=False),
        sa.Column("display_name", sa.String(length=120), nullable=False),
        sa.Column("base_url", sa.String(length=500), nullable=False),
        sa.Column("username_encrypted", sa.Text(), nullable=True),
        sa.Column("password_encrypted", sa.Text(), nullable=True),
        sa.Column("broker_code", sa.BigInteger(), nullable=True),
        sa.Column("contract_duration_days", sa.Integer(), nullable=False, server_default="365"),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("provider_code", name="uq_tax_provider_credentials_provider"),
    )
    op.create_index("ix_tax_provider_credentials_provider_code", "tax_provider_credentials", ["provider_code"])
    op.create_table(
        "business_tax_provider_accounts",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("business_id", sa.Integer(), nullable=False),
        sa.Column("provider_code", sa.String(length=40), nullable=False),
        sa.Column("status", sa.String(length=32), nullable=False, server_default="not_connected"),
        sa.Column("cartable_id", sa.BigInteger(), nullable=True),
        sa.Column("memory_id", sa.BigInteger(), nullable=True),
        sa.Column("memory_number", sa.String(length=128), nullable=True),
        sa.Column("consented_by_user_id", sa.Integer(), nullable=True),
        sa.Column("consented_at", sa.DateTime(), nullable=True),
        sa.Column("username_encrypted", sa.Text(), nullable=True),
        sa.Column("password_encrypted", sa.Text(), nullable=True),
        sa.Column("access_token_encrypted", sa.Text(), nullable=True),
        sa.Column("token_expires_at", sa.DateTime(), nullable=True),
        sa.Column("last_error", sa.Text(), nullable=True),
        sa.Column("registered_at", sa.DateTime(), nullable=True),
        sa.Column("last_synced_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["consented_by_user_id"], ["users.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("business_id", "provider_code", name="uq_business_tax_provider_account"),
    )
    op.create_index("ix_business_tax_provider_accounts_business_id", "business_tax_provider_accounts", ["business_id"])
    op.create_index("ix_business_tax_provider_accounts_provider_code", "business_tax_provider_accounts", ["provider_code"])


def downgrade() -> None:
    op.drop_index("ix_business_tax_provider_accounts_provider_code", table_name="business_tax_provider_accounts")
    op.drop_index("ix_business_tax_provider_accounts_business_id", table_name="business_tax_provider_accounts")
    op.drop_table("business_tax_provider_accounts")
    op.drop_index("ix_tax_provider_credentials_provider_code", table_name="tax_provider_credentials")
    op.drop_table("tax_provider_credentials")
    op.drop_column("tax_settings", "submission_provider")
