"""پایگاه دانش AI برای RAG

Revision ID: 20260624_000001_ai_knowledge_documents
Revises: 20260623_000001_ai_memory_and_attachments
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260624_000001_ai_knowledge_documents"
down_revision = "20260623_000001_ai_memory_and_attachments"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "ai_knowledge_documents",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("title", sa.String(512), nullable=False),
        sa.Column("content", sa.Text(), nullable=False),
        sa.Column("source_filename", sa.String(512), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("NOW()")),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.text("NOW()")),
    )
    op.create_index("ix_ai_knowledge_documents_business_id", "ai_knowledge_documents", ["business_id"])


def downgrade() -> None:
    op.drop_index("ix_ai_knowledge_documents_business_id", table_name="ai_knowledge_documents")
    op.drop_table("ai_knowledge_documents")
