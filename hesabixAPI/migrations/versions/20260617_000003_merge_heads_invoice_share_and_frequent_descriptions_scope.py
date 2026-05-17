"""Merge heads: business_invoice_share_settings + business_frequent_descriptions_scope

Revision ID: 20260617_000003_merge_heads_invoice_share_and_frequent_descriptions_scope
Revises: 20260616_000002_business_invoice_share_settings, 20260617_000002_business_frequent_descriptions_scope
Create Date: 2026-06-17

"""

from __future__ import annotations

from alembic import op  # noqa: F401

revision = "20260617_000003_merge_heads_invoice_share_and_frequent_descriptions_scope"
down_revision = (
	"20260616_000002_business_invoice_share_settings",
	"20260617_000002_business_frequent_descriptions_scope",
)
branch_labels = None
depends_on = None


def upgrade() -> None:
	pass


def downgrade() -> None:
	pass
