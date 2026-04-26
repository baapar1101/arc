# noqa: D100
"""برچسب‌های فاکتور (چندبرچسبی به‌ازای هر سند)."""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260427_000001_document_invoice_tags"
down_revision = "20260601_000001_crm_chat_message_deleted_at"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"document_invoice_tags",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("name", sa.String(length=120), nullable=False),
		sa.Column("color", sa.String(length=32), nullable=True),
		# PostgreSQL: boolean columns need false/true, not 0/1
		sa.Column("is_system", sa.Boolean(), nullable=False, server_default=sa.text("false")),
		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("sort_order", sa.Integer(), nullable=False, server_default=sa.text("0")),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "name", name="uq_document_invoice_tags_business_name"),
	)
	op.create_index("ix_document_invoice_tags_business_id", "document_invoice_tags", ["business_id"], unique=False)
	op.create_table(
		"document_invoice_tag_links",
		sa.Column("document_id", sa.Integer(), nullable=False),
		sa.Column("tag_id", sa.Integer(), nullable=False),
		sa.ForeignKeyConstraint(["document_id"], ["documents.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["tag_id"], ["document_invoice_tags.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("document_id", "tag_id"),
	)
	op.create_index("ix_document_invoice_tag_links_tag_id", "document_invoice_tag_links", ["tag_id"], unique=False)


def downgrade() -> None:
	op.drop_index("ix_document_invoice_tag_links_tag_id", table_name="document_invoice_tag_links")
	op.drop_table("document_invoice_tag_links")
	op.drop_index("ix_document_invoice_tags_business_id", table_name="document_invoice_tags")
	op.drop_table("document_invoice_tags")
