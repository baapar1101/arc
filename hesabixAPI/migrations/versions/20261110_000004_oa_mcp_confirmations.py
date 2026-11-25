"""تأیید سروری عمل پرریسک MCP اتوماسیون اداری.

Revision ID: 20261110_000004_oa_mcp_confirmations
Revises: 20261110_000003_oa_documents
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261110_000004_oa_mcp_confirmations"
down_revision = "20261110_000003_oa_documents"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"oa_mcp_confirmations",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("user_id", sa.Integer(), nullable=False),
		sa.Column("connection_id", sa.Integer(), nullable=True),
		sa.Column("tool_name", sa.String(length=80), nullable=False),
		sa.Column("arguments_hash", sa.String(length=64), nullable=False),
		sa.Column("arguments_json", sa.JSON(), nullable=False),
		sa.Column("summary", sa.String(length=300), nullable=False),
		sa.Column("status", sa.String(length=16), nullable=False),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("expires_at", sa.DateTime(), nullable=False),
		sa.Column("decided_at", sa.DateTime(), nullable=True),
		sa.Column("consumed_at", sa.DateTime(), nullable=True),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_oa_mcp_confirmations_user", "oa_mcp_confirmations", ["business_id", "user_id", "status"])


def downgrade() -> None:
	op.drop_index("ix_oa_mcp_confirmations_user", table_name="oa_mcp_confirmations")
	op.drop_table("oa_mcp_confirmations")
