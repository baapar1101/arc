"""support attachments and response templates

Revision ID: 20260628_000001_support_phase2
Revises: 20260627_000001_support_ticket_events
Create Date: 2026-06-28
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260628_000001_support_phase2"
down_revision = "20260627_000001_support_ticket_events"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "support_attachments",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("ticket_id", sa.Integer(), nullable=False),
        sa.Column("message_id", sa.Integer(), nullable=True),
        sa.Column("file_storage_id", sa.String(length=36), nullable=False),
        sa.Column("original_name", sa.String(length=512), nullable=False),
        sa.Column("mime_type", sa.String(length=128), nullable=True),
        sa.Column("size_bytes", sa.BigInteger(), nullable=False, server_default="0"),
        sa.Column("uploaded_by", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("NOW()")),
        sa.ForeignKeyConstraint(["message_id"], ["support_messages.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["ticket_id"], ["support_tickets.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["uploaded_by"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_support_attachments_ticket_id", "support_attachments", ["ticket_id"])
    op.create_index("ix_support_attachments_message_id", "support_attachments", ["message_id"])
    op.create_index("ix_support_attachments_file_storage_id", "support_attachments", ["file_storage_id"])

    op.create_table(
        "support_response_templates",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("name", sa.String(length=100), nullable=False),
        sa.Column("content", sa.Text(), nullable=False),
        sa.Column("category_id", sa.Integer(), nullable=True),
        sa.Column("is_global", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("created_by", sa.Integer(), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("usage_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("NOW()")),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.text("NOW()")),
        sa.ForeignKeyConstraint(["category_id"], ["support_categories.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["created_by"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )


def downgrade() -> None:
    op.drop_table("support_response_templates")
    op.drop_index("ix_support_attachments_file_storage_id", table_name="support_attachments")
    op.drop_index("ix_support_attachments_message_id", table_name="support_attachments")
    op.drop_index("ix_support_attachments_ticket_id", table_name="support_attachments")
    op.drop_table("support_attachments")
