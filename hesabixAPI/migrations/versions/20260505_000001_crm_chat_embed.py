"""CRM embeddable web chat: widgets, conversations, messages

Revision ID: 20260505_000001_crm_chat_embed
Revises: 20260504_000002_data_table_user_column_settings
Create Date: 2026-05-05
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260505_000001_crm_chat_embed"
down_revision = "20260504_000002_data_table_user_column_settings"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"crm_chat_widgets",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("name", sa.String(length=255), nullable=False),
		sa.Column("public_key", sa.String(length=64), nullable=False),
		sa.Column("allowed_origins", sa.JSON(), nullable=True),
		sa.Column("settings", sa.JSON(), nullable=True),
		sa.Column("is_active", sa.Boolean(), nullable=False, server_default="1"),
		sa.Column("created_at", sa.DateTime(), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=False),
		sa.Column("updated_at", sa.DateTime(), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("public_key", name="uq_crm_chat_widgets_public_key"),
	)
	op.create_index("ix_crm_chat_widgets_business_id", "crm_chat_widgets", ["business_id"], unique=False)

	op.create_table(
		"crm_chat_conversations",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("widget_id", sa.Integer(), nullable=False),
		sa.Column("status", sa.String(length=32), nullable=False, server_default="open"),
		sa.Column("visitor_first_name", sa.String(length=120), nullable=False),
		sa.Column("visitor_last_name", sa.String(length=120), nullable=False),
		sa.Column("visitor_email", sa.String(length=255), nullable=False),
		sa.Column("visitor_phone", sa.String(length=64), nullable=False),
		sa.Column("visitor_token_hash", sa.String(length=64), nullable=False),
		sa.Column("page_url", sa.Text(), nullable=True),
		sa.Column("extra_metadata", sa.JSON(), nullable=True),
		sa.Column("lead_id", sa.Integer(), nullable=True),
		sa.Column("person_id", sa.Integer(), nullable=True),
		sa.Column("assigned_to_user_id", sa.Integer(), nullable=True),
		sa.Column("last_message_at", sa.DateTime(), nullable=True),
		sa.Column("created_at", sa.DateTime(), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=False),
		sa.Column("updated_at", sa.DateTime(), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=False),
		sa.ForeignKeyConstraint(["assigned_to_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["lead_id"], ["crm_leads.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["person_id"], ["persons.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["widget_id"], ["crm_chat_widgets.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("visitor_token_hash", name="uq_crm_chat_conversations_visitor_token_hash"),
	)
	op.create_index("ix_crm_chat_conversations_business_id", "crm_chat_conversations", ["business_id"], unique=False)
	op.create_index("ix_crm_chat_conversations_widget_id", "crm_chat_conversations", ["widget_id"], unique=False)
	op.create_index("ix_crm_chat_conversations_last_message_at", "crm_chat_conversations", ["last_message_at"], unique=False)
	op.create_index("ix_crm_chat_conversations_status", "crm_chat_conversations", ["status"], unique=False)

	op.create_table(
		"crm_chat_messages",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("conversation_id", sa.Integer(), nullable=False),
		sa.Column("sender_role", sa.String(length=20), nullable=False),
		sa.Column("body", sa.Text(), nullable=False),
		sa.Column("user_id", sa.Integer(), nullable=True),
		sa.Column("created_at", sa.DateTime(), server_default=sa.text("CURRENT_TIMESTAMP"), nullable=False),
		sa.ForeignKeyConstraint(["conversation_id"], ["crm_chat_conversations.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_crm_chat_messages_conversation_id", "crm_chat_messages", ["conversation_id"], unique=False)
	op.create_index("ix_crm_chat_messages_created_at", "crm_chat_messages", ["created_at"], unique=False)


def downgrade() -> None:
	op.drop_index("ix_crm_chat_messages_created_at", table_name="crm_chat_messages")
	op.drop_index("ix_crm_chat_messages_conversation_id", table_name="crm_chat_messages")
	op.drop_table("crm_chat_messages")
	op.drop_index("ix_crm_chat_conversations_status", table_name="crm_chat_conversations")
	op.drop_index("ix_crm_chat_conversations_last_message_at", table_name="crm_chat_conversations")
	op.drop_index("ix_crm_chat_conversations_widget_id", table_name="crm_chat_conversations")
	op.drop_index("ix_crm_chat_conversations_business_id", table_name="crm_chat_conversations")
	op.drop_table("crm_chat_conversations")
	op.drop_index("ix_crm_chat_widgets_business_id", table_name="crm_chat_widgets")
	op.drop_table("crm_chat_widgets")
