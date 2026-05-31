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


def _vector_extension_available(conn) -> bool:
    """بدون اجرای CREATE EXTENSION — جلوگیری از abort تراکنش Alembic."""
    try:
        row = conn.execute(
            text(
                "SELECT 1 FROM pg_available_extensions "
                "WHERE name = 'vector' LIMIT 1"
            )
        ).first()
        return row is not None
    except Exception as exc:
        logger.warning("Could not check pg_available_extensions: %s", exc)
        return False


def upgrade() -> None:
    conn = op.get_bind()
    if not _vector_extension_available(conn):
        logger.warning(
            "pgvector is not available on this PostgreSQL server; skipping "
            "embedding_vector column (semantic search uses JSON embeddings only)"
        )
        return

    # CREATE EXTENSION باید خارج از تراکنش DDL معمولی باشد
    # از یک اتصال جدید با autocommit استفاده می‌کنیم تا SQLAlchemy transaction فعلی را تحت تأثیر قرار ندهیم.
    with conn.engine.connect().execution_options(isolation_level="AUTOCOMMIT") as autocommit_conn:
        autocommit_conn.execute(text("CREATE EXTENSION IF NOT EXISTS vector"))

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


def downgrade() -> None:
    conn = op.get_bind()
    if not _vector_extension_available(conn):
        return
    try:
        conn.execute(text("DROP INDEX IF EXISTS ix_ai_knowledge_chunks_embedding_vector"))
        conn.execute(
            text("ALTER TABLE ai_knowledge_chunks DROP COLUMN IF EXISTS embedding_vector")
        )
    except Exception as exc:
        logger.warning("pgvector downgrade skipped: %s", exc)
