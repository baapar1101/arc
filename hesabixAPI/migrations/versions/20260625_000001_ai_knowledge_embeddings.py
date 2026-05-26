"""بخش‌های دانشنامه با embedding

Revision ID: 20260625_000001_ai_knowledge_embeddings
Revises: 20260624_000001_ai_knowledge_documents
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260625_000001_ai_knowledge_embeddings"
down_revision = "20260624_000001_ai_knowledge_documents"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "ai_knowledge_chunks",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column(
            "document_id",
            sa.Integer(),
            sa.ForeignKey("ai_knowledge_documents.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("chunk_index", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("content", sa.Text(), nullable=False),
        sa.Column("embedding_json", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("NOW()")),
    )
    op.create_index("ix_ai_knowledge_chunks_document_id", "ai_knowledge_chunks", ["document_id"])


def downgrade() -> None:
    op.drop_index("ix_ai_knowledge_chunks_document_id", table_name="ai_knowledge_chunks")
    op.drop_table("ai_knowledge_chunks")
