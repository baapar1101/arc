"""CRM web chat: file attachments + business_crm_settings

Revision ID: 20260525_000001_crm_chat_files_settings
Revises: 20260505_000001_crm_chat_embed
Create Date: 2026-05-25
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260525_000001_crm_chat_files_settings"
down_revision = "20260505_000001_crm_chat_embed"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"business_crm_settings",
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("allow_web_chat_file_upload", sa.Boolean(), nullable=False, server_default="0"),
		sa.Column("updated_at", sa.DateTime(), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("business_id"),
	)
	op.add_column(
		"crm_chat_messages",
		sa.Column("file_storage_id", sa.String(length=36), nullable=True),
	)
	op.create_index("ix_crm_chat_messages_file_storage_id", "crm_chat_messages", ["file_storage_id"], unique=False)
	op.create_foreign_key(
		"fk_crm_chat_messages_file_storage",
		"crm_chat_messages",
		"file_storage",
		["file_storage_id"],
		["id"],
		ondelete="SET NULL",
	)


def downgrade() -> None:
	op.drop_constraint("fk_crm_chat_messages_file_storage", "crm_chat_messages", type_="foreignkey")
	op.drop_index("ix_crm_chat_messages_file_storage_id", table_name="crm_chat_messages")
	op.drop_column("crm_chat_messages", "file_storage_id")
	op.drop_table("business_crm_settings")
