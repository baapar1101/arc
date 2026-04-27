"""messenger operator sessions for telegram/bale CRM flows

Revision ID: 20260602_000001
Revises:
Create Date: 2026-06-02

"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "20260602_000001_messenger_operator_sessions"
down_revision = "20260601_000001_crm_chat_message_deleted_at"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"messenger_operator_sessions",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("user_id", sa.Integer(), nullable=False),
		sa.Column("platform", sa.String(length=16), nullable=False),
		sa.Column("flow_key", sa.String(length=64), server_default="crm_web_chat", nullable=False),
		sa.Column("mode", sa.String(length=32), server_default="idle", nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=True),
		sa.Column("active_conversation_id", sa.Integer(), nullable=True),
		sa.Column("context_json", sa.JSON(), nullable=True),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["active_conversation_id"], ["crm_chat_conversations.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("user_id", "platform", name="uq_messenger_operator_session_user_platform"),
	)
	op.create_index(op.f("ix_messenger_operator_sessions_user_id"), "messenger_operator_sessions", ["user_id"], unique=False)
	op.create_index(op.f("ix_messenger_operator_sessions_platform"), "messenger_operator_sessions", ["platform"], unique=False)
	op.create_index(op.f("ix_messenger_operator_sessions_business_id"), "messenger_operator_sessions", ["business_id"], unique=False)
	op.create_index(
		op.f("ix_messenger_operator_sessions_active_conversation_id"),
		"messenger_operator_sessions",
		["active_conversation_id"],
		unique=False,
	)


def downgrade() -> None:
	op.drop_index(op.f("ix_messenger_operator_sessions_active_conversation_id"), table_name="messenger_operator_sessions")
	op.drop_index(op.f("ix_messenger_operator_sessions_business_id"), table_name="messenger_operator_sessions")
	op.drop_index(op.f("ix_messenger_operator_sessions_platform"), table_name="messenger_operator_sessions")
	op.drop_index(op.f("ix_messenger_operator_sessions_user_id"), table_name="messenger_operator_sessions")
	op.drop_table("messenger_operator_sessions")
