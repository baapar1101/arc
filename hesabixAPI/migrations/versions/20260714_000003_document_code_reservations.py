"""رزرو شماره سند برای نمایش قطعی در فرم ایجاد فاکتور.

Revision ID: 20260714_000003_document_code_reservations
Revises: 20260714_000002_fix_ai_chat_message_trace_content
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260714_000003_document_code_reservations"
down_revision = "20260714_000002_fix_ai_chat_message_trace_content"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "document_code_reservations",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("business_id", sa.Integer(), nullable=False),
        sa.Column("reserved_by_user_id", sa.Integer(), nullable=False),
        sa.Column("document_type", sa.String(length=50), nullable=False),
        sa.Column("document_date", sa.Date(), nullable=False),
        sa.Column("code", sa.String(length=64), nullable=False),
        sa.Column("status", sa.String(length=20), nullable=False, server_default="active"),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("used_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("cancelled_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["reserved_by_user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_document_code_reservations_business_id",
        "document_code_reservations",
        ["business_id"],
        unique=False,
    )
    op.create_index(
        "ix_document_code_reservations_reserved_by_user_id",
        "document_code_reservations",
        ["reserved_by_user_id"],
        unique=False,
    )
    op.create_index(
        "ix_document_code_reservations_document_type",
        "document_code_reservations",
        ["document_type"],
        unique=False,
    )
    op.create_index(
        "ix_document_code_reservations_code",
        "document_code_reservations",
        ["code"],
        unique=False,
    )
    op.create_index(
        "ix_document_code_reservations_expires_at",
        "document_code_reservations",
        ["expires_at"],
        unique=False,
    )
    op.create_index(
        "uq_doc_code_reservation_active_business_code",
        "document_code_reservations",
        ["business_id", "code"],
        unique=True,
        postgresql_where=sa.text("status = 'active'"),
    )


def downgrade() -> None:
    op.drop_index(
        "uq_doc_code_reservation_active_business_code",
        table_name="document_code_reservations",
    )
    op.drop_index("ix_document_code_reservations_expires_at", table_name="document_code_reservations")
    op.drop_index("ix_document_code_reservations_code", table_name="document_code_reservations")
    op.drop_index("ix_document_code_reservations_document_type", table_name="document_code_reservations")
    op.drop_index("ix_document_code_reservations_reserved_by_user_id", table_name="document_code_reservations")
    op.drop_index("ix_document_code_reservations_business_id", table_name="document_code_reservations")
    op.drop_table("document_code_reservations")
