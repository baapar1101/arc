"""Merge heads: document_invoice_tags + messenger_operator_sessions

Revision ID: 20260602_000002_merge_heads_document_invoice_tags_and_messenger_operator_sessions
Revises: 20260427_000001_document_invoice_tags, 20260602_000001_messenger_operator_sessions
Create Date: 2026-06-02

"""

from __future__ import annotations

from alembic import op  # noqa: F401

revision = "20260602_000002_merge_heads_document_invoice_tags_and_messenger_operator_sessions"
down_revision = (
	"20260427_000001_document_invoice_tags",
	"20260602_000001_messenger_operator_sessions",
)
branch_labels = None
depends_on = None


def upgrade() -> None:
	pass


def downgrade() -> None:
	pass

