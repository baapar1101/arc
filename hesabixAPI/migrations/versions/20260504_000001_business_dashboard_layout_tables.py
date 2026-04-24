"""جداول چیدمان داشبورد کسب‌وکار (پایدار برای وب و چند worker)

Revision ID: 20260504_000001_business_dashboard_layout_tables
Revises: 20260503_000001_ai_config_function_calling_enabled
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260504_000001_business_dashboard_layout_tables"
down_revision = "20260503_000001_ai_config_function_calling_enabled"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"business_user_dashboard_layouts",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("user_id", sa.Integer(), nullable=False),
		sa.Column("breakpoint", sa.String(length=8), nullable=False),
		sa.Column("items", sa.JSON(), nullable=False),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "user_id", "breakpoint", name="uq_budl_business_user_bp"),
	)
	op.create_index(
		"ix_business_user_dashboard_layouts_business_id",
		"business_user_dashboard_layouts",
		["business_id"],
		unique=False,
	)
	op.create_index(
		"ix_business_user_dashboard_layouts_user_id", "business_user_dashboard_layouts", ["user_id"], unique=False
	)
	op.create_index(
		"ix_business_user_dashboard_layouts_breakpoint", "business_user_dashboard_layouts", ["breakpoint"], unique=False
	)

	op.create_table(
		"business_dashboard_default_layouts",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("breakpoint", sa.String(length=8), nullable=False),
		sa.Column("items", sa.JSON(), nullable=False),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "breakpoint", name="uq_bddl_business_bp"),
	)
	op.create_index(
		"ix_business_dashboard_default_layouts_business_id",
		"business_dashboard_default_layouts",
		["business_id"],
		unique=False,
	)
	op.create_index(
		"ix_business_dashboard_default_layouts_breakpoint", "business_dashboard_default_layouts", ["breakpoint"], unique=False
	)


def downgrade() -> None:
	op.drop_index("ix_business_dashboard_default_layouts_breakpoint", table_name="business_dashboard_default_layouts")
	op.drop_index("ix_business_dashboard_default_layouts_business_id", table_name="business_dashboard_default_layouts")
	op.drop_table("business_dashboard_default_layouts")
	op.drop_index("ix_business_user_dashboard_layouts_breakpoint", table_name="business_user_dashboard_layouts")
	op.drop_index("ix_business_user_dashboard_layouts_user_id", table_name="business_user_dashboard_layouts")
	op.drop_index("ix_business_user_dashboard_layouts_business_id", table_name="business_user_dashboard_layouts")
	op.drop_table("business_user_dashboard_layouts")
