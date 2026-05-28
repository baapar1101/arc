"""ستون structured برای حافظه AI

Revision ID: 20260530_000001_ai_memory_structured
Revises: 20260528_000001_distribution_phase3_advanced
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260530_000001_ai_memory_structured"
down_revision = "20260528_000001_distribution_phase3_advanced"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "ai_business_memories",
        sa.Column("structured", sa.Text(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("ai_business_memories", "structured")
