# noqa: D100
"""edited_at برای پیام چت CRM (ویرایش توسط اپراتور)."""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260603_000001_crm_chat_message_edited_at"
down_revision = "20260602_000002_merge_heads_document_invoice_tags_and_messenger_operator_sessions"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"crm_chat_messages",
		sa.Column("edited_at", sa.DateTime(), nullable=True),
	)
	op.create_index("ix_crm_chat_messages_edited_at", "crm_chat_messages", ["edited_at"])


def downgrade() -> None:
	op.drop_index("ix_crm_chat_messages_edited_at", table_name="crm_chat_messages")
	op.drop_column("crm_chat_messages", "edited_at")
