"""Merge heads: upgrade_ai_prompts_accounting_domain + ai_model_reasoning_effort

Revision ID: 20260619_000001_merge_heads_ai_prompts_accounting_domain_and_ai_model_reasoning_effort
Revises: 20260618_000001_upgrade_ai_prompts_accounting_domain, 20260704_000001_ai_model_reasoning_effort
Create Date: 2026-06-19

"""

from __future__ import annotations

from alembic import op  # noqa: F401

revision = (
	"20260619_000001_merge_heads_ai_prompts_accounting_domain_and_ai_model_reasoning_effort"
)
down_revision = (
	"20260618_000001_upgrade_ai_prompts_accounting_domain",
	"20260704_000001_ai_model_reasoning_effort",
)
branch_labels = None
depends_on = None


def upgrade() -> None:
	pass


def downgrade() -> None:
	pass
