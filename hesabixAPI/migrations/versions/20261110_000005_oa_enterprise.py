"""شعبه، نگهداری و امضای ارائه‌دهنده.

Revision ID: 20261110_000005_oa_enterprise
Revises: 20261110_000004_oa_mcp_confirmations
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261110_000005_oa_enterprise"
down_revision = "20261110_000004_oa_mcp_confirmations"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column("oa_secretariats", sa.Column("branch_id", sa.Integer(), nullable=True))
	op.add_column("oa_letters", sa.Column("branch_id", sa.Integer(), nullable=True))
	op.add_column("oa_letters", sa.Column("retain_until", sa.Date(), nullable=True))
	op.add_column("oa_letters", sa.Column("retention_status", sa.String(length=16), nullable=False, server_default="none"))
	op.add_column("oa_letters", sa.Column("qualified_sign_status", sa.String(length=16), nullable=False, server_default="none"))
	op.add_column("oa_documents", sa.Column("retain_until", sa.Date(), nullable=True))
	op.add_column("oa_documents", sa.Column("retention_status", sa.String(length=16), nullable=False, server_default="none"))
	op.create_table(
		"oa_branches",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("code", sa.String(length=64), nullable=False),
		sa.Column("name_i18n", sa.JSON(), nullable=False),
		sa.Column("is_active", sa.Boolean(), nullable=False),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "code", name="uq_oa_branches_biz_code"),
	)
	op.create_table(
		"oa_retention_policies",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("confidentiality", sa.String(length=32), nullable=False),
		sa.Column("retain_days", sa.Integer(), nullable=False),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "confidentiality", name="uq_oa_retention_policy"),
	)
	op.create_table(
		"oa_signature_providers",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("code", sa.String(length=64), nullable=False),
		sa.Column("name", sa.String(length=160), nullable=False),
		sa.Column("is_active", sa.Boolean(), nullable=False),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "code", name="uq_oa_signature_providers"),
	)
	op.create_table(
		"oa_qualified_sign_requests",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("letter_id", sa.Integer(), nullable=False),
		sa.Column("provider_id", sa.Integer(), nullable=False),
		sa.Column("requested_by_user_id", sa.Integer(), nullable=False),
		sa.Column("status", sa.String(length=24), nullable=False),
		sa.Column("external_ref", sa.String(length=120), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("completed_at", sa.DateTime(), nullable=True),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["letter_id"], ["oa_letters.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["provider_id"], ["oa_signature_providers.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["requested_by_user_id"], ["users.id"], ondelete="RESTRICT"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_oa_qualified_sign_letter", "oa_qualified_sign_requests", ["letter_id"])
	op.create_table(
		"oa_letter_exchanges",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("source_business_id", sa.Integer(), nullable=False),
		sa.Column("source_letter_id", sa.Integer(), nullable=False),
		sa.Column("target_business_id", sa.Integer(), nullable=False),
		sa.Column("target_letter_id", sa.Integer(), nullable=False),
		sa.Column("created_by_user_id", sa.Integer(), nullable=False),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["source_letter_id"], ["oa_letters.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["target_letter_id"], ["oa_letters.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="RESTRICT"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_oa_letter_exchanges_source", "oa_letter_exchanges", ["source_business_id", "source_letter_id"])


def downgrade() -> None:
	op.drop_index("ix_oa_letter_exchanges_source", table_name="oa_letter_exchanges")
	op.drop_table("oa_letter_exchanges")
	op.drop_index("ix_oa_qualified_sign_letter", table_name="oa_qualified_sign_requests")
	op.drop_table("oa_qualified_sign_requests")
	op.drop_table("oa_signature_providers")
	op.drop_table("oa_retention_policies")
	op.drop_table("oa_branches")
	op.drop_column("oa_documents", "retention_status")
	op.drop_column("oa_documents", "retain_until")
	op.drop_column("oa_letters", "qualified_sign_status")
	op.drop_column("oa_letters", "retention_status")
	op.drop_column("oa_letters", "retain_until")
	op.drop_column("oa_letters", "branch_id")
	op.drop_column("oa_secretariats", "branch_id")
