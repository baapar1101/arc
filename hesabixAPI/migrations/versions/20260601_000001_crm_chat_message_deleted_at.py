# noqa: D100
"""soft-delete برای پیام چت CRM."""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260601_000001_crm_chat_message_deleted_at"
down_revision = "20260529_000001_crm_chat_message_read_at"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"crm_chat_messages",
		sa.Column("deleted_at", sa.DateTime(), nullable=True),
	)
	op.create_index("ix_crm_chat_messages_deleted_at", "crm_chat_messages", ["deleted_at"])


def downgrade() -> None:
	op.drop_index("ix_crm_chat_messages_deleted_at", table_name="crm_chat_messages")
	op.drop_column("crm_chat_messages", "deleted_at")
