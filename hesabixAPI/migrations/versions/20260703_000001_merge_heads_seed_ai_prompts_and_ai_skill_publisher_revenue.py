"""Merge heads: seed_ai_default_prompts + ai_skill_publisher_revenue

Revision ID: 20260703_000001_merge_heads_seed_ai_prompts_and_ai_skill_publisher_revenue
Revises: 20260613_000004_seed_ai_default_prompts, 20260702_000004_ai_skill_publisher_revenue
Create Date: 2026-07-03

"""

from __future__ import annotations

from alembic import op  # noqa: F401

revision = "20260703_000001_merge_heads_seed_ai_prompts_and_ai_skill_publisher_revenue"
down_revision = (
	"20260613_000004_seed_ai_default_prompts",
	"20260702_000004_ai_skill_publisher_revenue",
)
branch_labels = None
depends_on = None


def upgrade() -> None:
	pass


def downgrade() -> None:
	pass
