"""برنامهٔ کاری موقت agent در جلسات چت AI

Revision ID: 20260619_000003_ai_session_todos
Revises: 20260619_000002_ai_chat_session_execution_mode
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260619_000003_ai_session_todos"
down_revision = "20260619_000002_ai_chat_session_execution_mode"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "ai_session_todos",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("public_id", sa.String(length=16), nullable=False),
        sa.Column(
            "session_id",
            sa.Integer(),
            sa.ForeignKey("ai_chat_sessions.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "origin_message_id",
            sa.Integer(),
            sa.ForeignKey("ai_chat_messages.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("title", sa.String(length=512), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column(
            "status",
            sa.String(length=32),
            nullable=False,
            server_default="pending",
        ),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("linked_tool", sa.String(length=128), nullable=True),
        sa.Column("error_message", sa.Text(), nullable=True),
        sa.Column("extra_json", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("NOW()")),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.text("NOW()")),
        sa.Column("started_at", sa.DateTime(), nullable=True),
        sa.Column("completed_at", sa.DateTime(), nullable=True),
    )
    op.create_index("ix_ai_session_todos_public_id", "ai_session_todos", ["public_id"])
    op.create_index("ix_ai_session_todos_session_id", "ai_session_todos", ["session_id"])
    op.create_index(
        "ix_ai_session_todos_session_status_order",
        "ai_session_todos",
        ["session_id", "status", "sort_order"],
    )


def downgrade() -> None:
    op.drop_index("ix_ai_session_todos_session_status_order", table_name="ai_session_todos")
    op.drop_index("ix_ai_session_todos_session_id", table_name="ai_session_todos")
    op.drop_index("ix_ai_session_todos_public_id", table_name="ai_session_todos")
    op.drop_table("ai_session_todos")
