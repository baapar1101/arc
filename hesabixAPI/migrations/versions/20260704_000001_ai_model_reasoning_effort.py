"""افزودن کنترل استدلال درون‌مدلی به کاتالوگ مدل‌های AI

Revision ID: 20260704_000001_ai_model_reasoning_effort
Revises: 20260703_000001_merge_heads_seed_ai_prompts_and_ai_skill_publisher_revenue
Create Date: 2026-07-04
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260704_000001_ai_model_reasoning_effort"
down_revision = (
    "20260703_000001_merge_heads_seed_ai_prompts_and_ai_skill_publisher_revenue"
)
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    if bind is None:
        return

    insp = sa.inspect(bind)
    ai_model_columns = {col["name"] for col in insp.get_columns("ai_models")}

    if "supports_reasoning" not in ai_model_columns:
        op.add_column(
            "ai_models",
            sa.Column(
                "supports_reasoning",
                sa.Boolean(),
                nullable=False,
                server_default=sa.text("false"),
            ),
        )
    if "reasoning_effort" not in ai_model_columns:
        op.add_column(
            "ai_models",
            sa.Column("reasoning_effort", sa.String(20), nullable=True),
        )


def downgrade() -> None:
    op.drop_column("ai_models", "reasoning_effort")
    op.drop_column("ai_models", "supports_reasoning")
