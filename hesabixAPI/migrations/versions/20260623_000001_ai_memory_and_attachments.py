"""حافظه AI کسب‌وکار و پیوست‌های گفت‌وگو

Revision ID: 20260623_000001_ai_memory_and_attachments
Revises: 20260622_000001_invoice_purchase_accounting_mode
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260623_000001_ai_memory_and_attachments"
down_revision = "20260622_000001_invoice_purchase_accounting_mode"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "ai_business_memories",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("content", sa.Text(), nullable=False, server_default=""),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("NOW()")),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.text("NOW()")),
        sa.UniqueConstraint("business_id", "user_id", name="uq_ai_business_memory_business_user"),
    )
    op.create_index("ix_ai_business_memories_business_id", "ai_business_memories", ["business_id"])
    op.create_index("ix_ai_business_memories_user_id", "ai_business_memories", ["user_id"])

    op.create_table(
        "ai_chat_attachments",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column(
            "session_id",
            sa.Integer(),
            sa.ForeignKey("ai_chat_sessions.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("filename", sa.String(512), nullable=False),
        sa.Column("mime_type", sa.String(128), nullable=True),
        sa.Column("extracted_text", sa.Text(), nullable=False),
        sa.Column("char_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("NOW()")),
    )
    op.create_index("ix_ai_chat_attachments_session_id", "ai_chat_attachments", ["session_id"])


def downgrade() -> None:
    op.drop_index("ix_ai_chat_attachments_session_id", table_name="ai_chat_attachments")
    op.drop_table("ai_chat_attachments")
    op.drop_index("ix_ai_business_memories_user_id", table_name="ai_business_memories")
    op.drop_index("ix_ai_business_memories_business_id", table_name="ai_business_memories")
    op.drop_table("ai_business_memories")
