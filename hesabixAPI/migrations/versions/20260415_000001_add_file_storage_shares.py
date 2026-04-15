"""add file_storage_shares for public file sharing

Revision ID: 20260415_000001_add_file_storage_shares
Revises: 20260411_000002_seed_notification_templates_all_channels
Create Date: 2026-04-15
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260415_000001_add_file_storage_shares"
down_revision = "20260411_000002_seed_notification_templates_all_channels"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"file_storage_shares",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("file_storage_id", sa.String(length=36), nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("token_hash", sa.String(length=64), nullable=False),
		sa.Column("password_hash", sa.String(length=255), nullable=True),
		sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True),
		sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
		sa.Column("access_count", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("last_access_at", sa.DateTime(timezone=True), nullable=True),
		sa.Column("created_by", sa.Integer(), nullable=True),
		sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
		sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["created_by"], ["users.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["file_storage_id"], ["file_storage.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_file_storage_shares_business_id", "file_storage_shares", ["business_id"], unique=False)
	op.create_index("ix_file_storage_shares_file_storage_id", "file_storage_shares", ["file_storage_id"], unique=False)
	op.create_index("ix_file_storage_shares_token_hash", "file_storage_shares", ["token_hash"], unique=True)


def downgrade() -> None:
	op.drop_index("ix_file_storage_shares_token_hash", table_name="file_storage_shares")
	op.drop_index("ix_file_storage_shares_file_storage_id", table_name="file_storage_shares")
	op.drop_index("ix_file_storage_shares_business_id", table_name="file_storage_shares")
	op.drop_table("file_storage_shares")
