"""ستون pgvector اختیاری برای chunks (در صورت نصب extension)

Revision ID: 20260626_000002_ai_pgvector_optional
Revises: 20260626_000001_ai_phase6_eval_connectors_feedback
"""
from __future__ import annotations

import logging

from alembic import op
from sqlalchemy import text

logger = logging.getLogger(__name__)

revision = "20260626_000002_ai_pgvector_optional"
down_revision = "20260626_000001_ai_phase6_eval_connectors_feedback"
branch_labels = None
depends_on = None


def upgrade() -> None:
    conn = op.get_bind()
    try:
        conn.execute(text("CREATE EXTENSION IF NOT EXISTS vector"))
        conn.execute(
            text(
                "ALTER TABLE ai_knowledge_chunks "
                "ADD COLUMN IF NOT EXISTS embedding_vector vector(1536)"
            )
        )
        conn.execute(
            text(
                "CREATE INDEX IF NOT EXISTS ix_ai_knowledge_chunks_embedding_vector "
                "ON ai_knowledge_chunks USING hnsw (embedding_vector vector_cosine_ops)"
            )
        )
        logger.info("pgvector enabled for ai_knowledge_chunks")
    except Exception as exc:
        logger.warning("pgvector migration skipped (extension unavailable): %s", exc)


def downgrade() -> None:
    conn = op.get_bind()
    try:
        conn.execute(text("DROP INDEX IF EXISTS ix_ai_knowledge_chunks_embedding_vector"))
        conn.execute(text("ALTER TABLE ai_knowledge_chunks DROP COLUMN IF EXISTS embedding_vector"))
    except Exception:
        pass
