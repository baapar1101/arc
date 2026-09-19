"""Add durable AI agent run checkpoints.

Revision ID: 20260817_000002_ai_agent_runs
Revises: 20260817_000001_quick_sales_print_paper_size
Create Date: 2026-08-17
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260817_000002_ai_agent_runs"
down_revision = "20260817_000001_quick_sales_print_paper_size"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "ai_agent_runs",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("run_id", sa.String(length=16), nullable=False),
        sa.Column("session_id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("business_id", sa.Integer(), nullable=True),
        sa.Column("origin_message_id", sa.Integer(), nullable=True),
        sa.Column(
            "status",
            sa.String(length=32),
            nullable=False,
            server_default="running",
        ),
        sa.Column(
            "phase",
            sa.String(length=32),
            nullable=False,
            server_default="gather_context",
        ),
        sa.Column("iteration", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("needs_tools", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("stop_reason", sa.String(length=64), nullable=True),
        sa.Column("tools_called_json", sa.Text(), nullable=True),
        sa.Column("budget_json", sa.Text(), nullable=True),
        sa.Column("last_event_id", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("extra_json", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(
            ["session_id"], ["ai_chat_sessions.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(
            ["business_id"], ["businesses.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["origin_message_id"], ["ai_chat_messages.id"], ondelete="SET NULL"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_ai_agent_runs_run_id", "ai_agent_runs", ["run_id"], unique=True)
    op.create_index("ix_ai_agent_runs_session_id", "ai_agent_runs", ["session_id"])
    op.create_index("ix_ai_agent_runs_user_id", "ai_agent_runs", ["user_id"])
    op.create_index("ix_ai_agent_runs_business_id", "ai_agent_runs", ["business_id"])


def downgrade() -> None:
    op.drop_index("ix_ai_agent_runs_business_id", table_name="ai_agent_runs")
    op.drop_index("ix_ai_agent_runs_user_id", table_name="ai_agent_runs")
    op.drop_index("ix_ai_agent_runs_session_id", table_name="ai_agent_runs")
    op.drop_index("ix_ai_agent_runs_run_id", table_name="ai_agent_runs")
    op.drop_table("ai_agent_runs")
