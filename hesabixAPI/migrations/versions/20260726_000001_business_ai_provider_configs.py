"""جدول تنظیمات ارائه‌دهنده AI اختصاصی کسب‌وکار (BYOK)

Revision ID: 20260726_000001_business_ai_provider_configs
Revises: 20260725_000002_product_fx_prices
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260726_000001_business_ai_provider_configs"
down_revision = "20260725_000002_product_fx_prices"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "business_ai_provider_configs",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("business_id", sa.Integer(), nullable=False),
        sa.Column("provider", sa.String(50), nullable=False, server_default="openai"),
        sa.Column("display_name", sa.String(120), nullable=True),
        sa.Column("api_base_url", sa.String(500), nullable=True),
        sa.Column("api_key", sa.Text(), nullable=True),
        sa.Column("models_json", sa.Text(), nullable=True),
        sa.Column("default_model", sa.String(120), nullable=True),
        sa.Column(
            "function_calling_enabled",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("true"),
        ),
        sa.Column(
            "is_active",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("true"),
        ),
        sa.Column("last_tested_at", sa.DateTime(), nullable=True),
        sa.Column("last_test_ok", sa.Boolean(), nullable=True),
        sa.Column("last_test_error", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.ForeignKeyConstraint(
            ["business_id"],
            ["businesses.id"],
            ondelete="CASCADE",
        ),
        sa.UniqueConstraint("business_id", name="uq_business_ai_provider_configs_business"),
    )
    op.create_index(
        "ix_business_ai_provider_configs_business_id",
        "business_ai_provider_configs",
        ["business_id"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_business_ai_provider_configs_business_id",
        table_name="business_ai_provider_configs",
    )
    op.drop_table("business_ai_provider_configs")
