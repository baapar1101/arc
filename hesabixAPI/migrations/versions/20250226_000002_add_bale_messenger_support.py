"""add bale messenger support

- Add bale_chat_id, bale_connected_at to users
- Create bale_link_tokens table

Revision ID: 20250226_000002
Revises: 20250226_000001_backfill_receipt_payment_person_id_extra_info
Create Date: 2025-02-26

"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "20250226_000002_add_bale_messenger_support"
down_revision = "20250226_000001_backfill_receipt_payment_person_id_extra_info"
branch_labels = None
depends_on = None


def upgrade() -> None:
	# Add Bale columns to users
	op.add_column("users", sa.Column("bale_chat_id", sa.BigInteger(), nullable=True))
	op.add_column("users", sa.Column("bale_connected_at", sa.DateTime(), nullable=True))
	op.create_index(op.f("ix_users_bale_chat_id"), "users", ["bale_chat_id"], unique=False)

	# Create bale_link_tokens table
	op.create_table(
		"bale_link_tokens",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("user_id", sa.Integer(), nullable=False),
		sa.Column("token", sa.String(128), nullable=False),
		sa.Column("expires_at", sa.DateTime(), nullable=False),
		sa.Column("used_at", sa.DateTime(), nullable=True),
		sa.Column("created_ip", sa.String(64), nullable=True),
		sa.Column("user_agent", sa.String(255), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index(op.f("ix_bale_link_tokens_user_id"), "bale_link_tokens", ["user_id"], unique=False)
	op.create_index(op.f("ix_bale_link_tokens_token"), "bale_link_tokens", ["token"], unique=True)
	op.create_index(op.f("ix_bale_link_tokens_expires_at"), "bale_link_tokens", ["expires_at"], unique=False)
	op.create_index("ix_bale_link_validity", "bale_link_tokens", ["expires_at", "used_at"], unique=False)


def downgrade() -> None:
	op.drop_index("ix_bale_link_validity", "bale_link_tokens")
	op.drop_index(op.f("ix_bale_link_tokens_expires_at"), "bale_link_tokens")
	op.drop_index(op.f("ix_bale_link_tokens_token"), "bale_link_tokens")
	op.drop_index(op.f("ix_bale_link_tokens_user_id"), "bale_link_tokens")
	op.drop_table("bale_link_tokens")

	op.drop_index(op.f("ix_users_bale_chat_id"), "users")
	op.drop_column("users", "bale_connected_at")
	op.drop_column("users", "bale_chat_id")
