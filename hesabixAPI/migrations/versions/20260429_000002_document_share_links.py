"""جدول لینک اشتراک فاکتور/سند (document_share_links)

Revision ID: 20260429_000002_document_share_links
Revises: 20260429_000001_business_print_settings_show_share_qr
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260429_000002_document_share_links"
down_revision = "20260429_000001_business_print_settings_show_share_qr"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"document_share_links",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("document_id", sa.Integer(), nullable=False),
		sa.Column("created_by_user_id", sa.Integer(), nullable=True),
		sa.Column("revoked_by_user_id", sa.Integer(), nullable=True),
		sa.Column("code", sa.String(length=16), nullable=False),
		sa.Column("token_hash", sa.String(length=128), nullable=False),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("expires_at", sa.DateTime(), nullable=True),
		sa.Column("revoked_at", sa.DateTime(), nullable=True),
		sa.Column("last_view_at", sa.DateTime(), nullable=True),
		sa.Column("view_count", sa.Integer(), nullable=False, server_default=sa.text("0")),
		sa.Column("max_view_count", sa.Integer(), nullable=True),
		sa.Column("options", sa.JSON(), nullable=True),
		sa.Column("meta", sa.JSON(), nullable=True),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["document_id"], ["documents.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["revoked_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("code", name="uq_document_share_links_code"),
	)
	op.create_index("ix_document_share_links_code", "document_share_links", ["code"], unique=False)
	op.create_index(
		"ix_document_share_links_document_id",
		"document_share_links",
		["document_id"],
		unique=False,
	)
	op.create_index(
		"ix_document_share_links_business_id",
		"document_share_links",
		["business_id"],
		unique=False,
	)


def downgrade() -> None:
	op.drop_index("ix_document_share_links_business_id", table_name="document_share_links")
	op.drop_index("ix_document_share_links_document_id", table_name="document_share_links")
	op.drop_index("ix_document_share_links_code", table_name="document_share_links")
	op.drop_table("document_share_links")
