"""merge support phase2 and documents indexes heads

Revision ID: 20260705_000001_merge_heads
Revises: 20260622_000002, 20260628_000001_support_phase2
Create Date: 2026-07-05
"""

from __future__ import annotations

from alembic import op

revision = "20260705_000001_merge_heads"
down_revision = ("20260622_000002", "20260628_000001_support_phase2")
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
