"""CRM web chat: read receipt timestamp on messages

Revision ID: 20260529_000001_crm_chat_message_read_at
Revises: 20260528_000001_firewall_rate_policies
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260529_000001_crm_chat_message_read_at"
down_revision = "20260528_000001_firewall_rate_policies"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"crm_chat_messages",
		sa.Column("read_at", sa.DateTime(), nullable=True),
	)
	op.create_index("ix_crm_chat_messages_read_at", "crm_chat_messages", ["read_at"], unique=False)


def downgrade() -> None:
	op.drop_index("ix_crm_chat_messages_read_at", table_name="crm_chat_messages")
	op.drop_column("crm_chat_messages", "read_at")
