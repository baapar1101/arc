"""دسترسی سریع (کاشی‌های داشبورد) به‌ازای کاربر و کسب‌وکار

Revision ID: 20260527_000001_business_user_quick_links
Revises: 20260526_000001_person_social_contacts
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260527_000001_business_user_quick_links"
down_revision = "20260526_000001_person_social_contacts"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"business_user_quick_links",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("user_id", sa.Integer(), nullable=False),
		sa.Column("items", sa.JSON(), nullable=False),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "user_id", name="uq_buql_business_user"),
	)
	op.create_index("ix_business_user_quick_links_business_id", "business_user_quick_links", ["business_id"], unique=False)
	op.create_index("ix_business_user_quick_links_user_id", "business_user_quick_links", ["user_id"], unique=False)


def downgrade() -> None:
	op.drop_index("ix_business_user_quick_links_user_id", table_name="business_user_quick_links")
	op.drop_index("ix_business_user_quick_links_business_id", table_name="business_user_quick_links")
	op.drop_table("business_user_quick_links")
