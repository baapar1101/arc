"""پیوند نامه به سند حسابداری یا فرصت فروش همان کسب‌وکار.

Revision ID: 20261110_000007_oa_letter_commercial_links
Revises: 20261110_000006_oa_signature_provider_endpoint
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261110_000007_oa_letter_commercial_links"
down_revision = "20261110_000006_oa_signature_provider_endpoint"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"oa_letter_commercial_links",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("letter_id", sa.Integer(), nullable=False),
		sa.Column("target_kind", sa.String(length=16), nullable=False),
		sa.Column("target_id", sa.Integer(), nullable=False),
		sa.Column("created_by_user_id", sa.Integer(), nullable=False),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["letter_id"], ["oa_letters.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="RESTRICT"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("letter_id", "target_kind", "target_id", name="uq_oa_letter_commercial_target"),
	)
	op.create_index("ix_oa_letter_commercial_letter", "oa_letter_commercial_links", ["letter_id"])


def downgrade() -> None:
	op.drop_index("ix_oa_letter_commercial_letter", table_name="oa_letter_commercial_links")
	op.drop_table("oa_letter_commercial_links")
