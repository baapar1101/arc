"""کاتالوگ مدل‌های AI و ترجیح مدل در اشتراک

Revision ID: 20260628_000001_ai_models_catalog
Revises: 20260627_000001_ai_phase7_schedule
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260628_000001_ai_models_catalog"
down_revision = "20260627_000001_ai_phase7_schedule"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "ai_models",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("code", sa.String(80), nullable=False),
        sa.Column("display_name", sa.String(255), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("provider", sa.String(50), nullable=False, server_default="openai"),
        sa.Column("model_id", sa.String(120), nullable=False),
        sa.Column("tier", sa.String(50), nullable=True),
        sa.Column("supports_tools", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("max_tokens_default", sa.Integer(), nullable=False, server_default="4000"),
        sa.Column("reference_input_cost_per_1k", sa.Numeric(18, 4), nullable=True),
        sa.Column("reference_output_cost_per_1k", sa.Numeric(18, 4), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint("code", name="uq_ai_models_code"),
    )
    op.create_index("ix_ai_models_code", "ai_models", ["code"])
    op.create_index("ix_ai_models_is_active", "ai_models", ["is_active"])

    op.add_column(
        "user_ai_subscriptions",
        sa.Column("preferred_model_code", sa.String(80), nullable=True),
    )
    op.create_index(
        "ix_user_ai_subscriptions_preferred_model_code",
        "user_ai_subscriptions",
        ["preferred_model_code"],
    )


def downgrade() -> None:
    op.drop_index("ix_user_ai_subscriptions_preferred_model_code", table_name="user_ai_subscriptions")
    op.drop_column("user_ai_subscriptions", "preferred_model_code")
    op.drop_index("ix_ai_models_is_active", table_name="ai_models")
    op.drop_index("ix_ai_models_code", table_name="ai_models")
    op.drop_table("ai_models")
