"""جدول شرح‌های پرتکرار کسب‌وکار (بدون ارتباط با اسناد)

Revision ID: 20260617_000001_business_frequent_descriptions
Revises: 20260616_000001_person_mobile_2_3
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260617_000001_business_frequent_descriptions"
down_revision = "20260616_000001_person_mobile_2_3"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"business_frequent_descriptions",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("text", sa.Text(), nullable=False),
		sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index(
		"ix_business_frequent_descriptions_business_id",
		"business_frequent_descriptions",
		["business_id"],
		unique=False,
	)


def downgrade() -> None:
	op.drop_index("ix_business_frequent_descriptions_business_id", table_name="business_frequent_descriptions")
	op.drop_table("business_frequent_descriptions")
