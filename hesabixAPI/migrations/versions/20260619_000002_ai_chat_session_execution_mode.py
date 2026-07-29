"""افزودن execution_mode به جلسات چت AI

Revision ID: 20260619_000002_ai_chat_session_execution_mode
Revises: 20260619_000001_merge_heads_ai_prompts_accounting_domain_and_ai_model_reasoning_effort
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260619_000002_ai_chat_session_execution_mode"
down_revision = (
    "20260619_000001_merge_heads_ai_prompts_accounting_domain_and_ai_model_reasoning_effort"
)
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "ai_chat_sessions",
        sa.Column(
            "execution_mode",
            sa.String(length=32),
            nullable=False,
            server_default="analyzer",
        ),
    )


def downgrade() -> None:
    op.drop_column("ai_chat_sessions", "execution_mode")
