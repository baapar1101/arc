"""Merge heads: ai_memory_items + quick_sales_share_defaults

Revision ID: 20260630_000003_merge_heads_ai_memory_items_and_quick_sales_share_defaults
Revises: 20260531_000001_ai_memory_items, 20260630_000002_quick_sales_share_defaults
Create Date: 2026-06-30

"""

from __future__ import annotations

from alembic import op  # noqa: F401

revision = "20260630_000003_merge_heads_ai_memory_items_and_quick_sales_share_defaults"
down_revision = (
	"20260531_000001_ai_memory_items",
	"20260630_000002_quick_sales_share_defaults",
)
branch_labels = None
depends_on = None


def upgrade() -> None:
	pass


def downgrade() -> None:
	pass
