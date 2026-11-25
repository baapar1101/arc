"""فیلتر ذخیره‌شده کارتابل اتوماسیون اداری.

Revision ID: 20261110_000001_oa_cartable_saved_filters
Revises: 20261107_000001_pay_page_requests
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261110_000001_oa_cartable_saved_filters"
down_revision = "20261107_000001_pay_page_requests"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"oa_cartable_saved_filters",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("user_id", sa.Integer(), nullable=False),
		sa.Column("name", sa.String(length=80), nullable=False),
		sa.Column("folder", sa.String(length=32), nullable=False),
		sa.Column("query_text", sa.String(length=200), nullable=True),
		sa.Column("date_from", sa.String(length=32), nullable=True),
		sa.Column("date_to", sa.String(length=32), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "user_id", "name", name="uq_oa_cartable_saved_filters_name"),
	)
	op.create_index(
		"ix_oa_cartable_saved_filters_business_user",
		"oa_cartable_saved_filters",
		["business_id", "user_id"],
	)


def downgrade() -> None:
	op.drop_index("ix_oa_cartable_saved_filters_business_user", table_name="oa_cartable_saved_filters")
	op.drop_table("oa_cartable_saved_filters")
