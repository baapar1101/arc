"""Persist AI subagent runs for restore after refresh.

Revision ID: 20260821_000001_ai_subagent_runs
Revises: 20260819_000001_ai_memory_identity_prompt
Create Date: 2026-08-21
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260821_000001_ai_subagent_runs"
down_revision = "20260819_000001_ai_memory_identity_prompt"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "ai_subagent_runs",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("subagent_id", sa.String(length=16), nullable=False),
        sa.Column("session_id", sa.Integer(), nullable=False),
        sa.Column("business_id", sa.Integer(), nullable=True),
        sa.Column("goal", sa.Text(), nullable=False, server_default=""),
        sa.Column(
            "status",
            sa.String(length=32),
            nullable=False,
            server_default="running",
        ),
        sa.Column("error", sa.String(length=128), nullable=True),
        sa.Column("result_json", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(
            ["session_id"], ["ai_chat_sessions.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["business_id"], ["businesses.id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_ai_subagent_runs_subagent_id",
        "ai_subagent_runs",
        ["subagent_id"],
        unique=True,
    )
    op.create_index(
        "ix_ai_subagent_runs_session_id", "ai_subagent_runs", ["session_id"]
    )
    op.create_index(
        "ix_ai_subagent_runs_business_id", "ai_subagent_runs", ["business_id"]
    )


def downgrade() -> None:
    op.drop_index("ix_ai_subagent_runs_business_id", table_name="ai_subagent_runs")
    op.drop_index("ix_ai_subagent_runs_session_id", table_name="ai_subagent_runs")
    op.drop_index("ix_ai_subagent_runs_subagent_id", table_name="ai_subagent_runs")
    op.drop_table("ai_subagent_runs")
