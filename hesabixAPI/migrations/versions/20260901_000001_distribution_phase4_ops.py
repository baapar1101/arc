"""فاز ۴ پخش مویرگی: هدف فروش، تسویه روزانه، جداول پشتیبان چاپ.

Revision ID: 20260901_000001_distribution_phase4_ops
Revises: 20260821_000001_ai_subagent_runs
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260901_000001_distribution_phase4_ops"
down_revision = "20260821_000001_ai_subagent_runs"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"distribution_sales_targets",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("user_id", sa.Integer(), nullable=False),
		sa.Column("period_type", sa.String(length=16), nullable=False),
		sa.Column("period_start", sa.Date(), nullable=False),
		sa.Column("target_amount", sa.Numeric(18, 2), nullable=False),
		sa.Column("notes", sa.Text(), nullable=True),
		sa.Column("created_by_user_id", sa.Integer(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
		sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint(
			"business_id",
			"user_id",
			"period_type",
			"period_start",
			name="uq_distribution_sales_target_period",
		),
		mysql_charset="utf8mb4",
	)
	op.create_index("ix_distribution_sales_targets_business_id", "distribution_sales_targets", ["business_id"])
	op.create_index("ix_distribution_sales_targets_user_id", "distribution_sales_targets", ["user_id"])

	op.create_table(
		"distribution_daily_settlements",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("user_id", sa.Integer(), nullable=False),
		sa.Column("settlement_date", sa.Date(), nullable=False),
		sa.Column("status", sa.String(length=32), nullable=False, server_default="draft"),
		sa.Column("expected_sales", sa.Numeric(18, 2), nullable=False, server_default="0"),
		sa.Column("cash_collected", sa.Numeric(18, 2), nullable=False, server_default="0"),
		sa.Column("cheque_collected", sa.Numeric(18, 2), nullable=False, server_default="0"),
		sa.Column("card_collected", sa.Numeric(18, 2), nullable=False, server_default="0"),
		sa.Column("other_collected", sa.Numeric(18, 2), nullable=False, server_default="0"),
		sa.Column("expenses", sa.Numeric(18, 2), nullable=False, server_default="0"),
		sa.Column("variance", sa.Numeric(18, 2), nullable=False, server_default="0"),
		sa.Column("visit_snapshot", sa.JSON(), nullable=True),
		sa.Column("notes", sa.Text(), nullable=True),
		sa.Column("receipt_document_id", sa.Integer(), nullable=True),
		sa.Column("cash_register_id", sa.Integer(), nullable=True),
		sa.Column("created_by_user_id", sa.Integer(), nullable=False),
		sa.Column("confirmed_by_user_id", sa.Integer(), nullable=True),
		sa.Column("confirmed_at", sa.DateTime(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
		sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.text("CURRENT_TIMESTAMP")),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["receipt_document_id"], ["documents.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["confirmed_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint(
			"business_id",
			"user_id",
			"settlement_date",
			name="uq_distribution_daily_settlement",
		),
		mysql_charset="utf8mb4",
	)
	op.create_index("ix_distribution_daily_settlements_business_id", "distribution_daily_settlements", ["business_id"])
	op.create_index("ix_distribution_daily_settlements_user_id", "distribution_daily_settlements", ["user_id"])
	op.create_index(
		"ix_distribution_daily_settlements_date",
		"distribution_daily_settlements",
		["settlement_date"],
	)


def downgrade() -> None:
	op.drop_index("ix_distribution_daily_settlements_date", table_name="distribution_daily_settlements")
	op.drop_index("ix_distribution_daily_settlements_user_id", table_name="distribution_daily_settlements")
	op.drop_index("ix_distribution_daily_settlements_business_id", table_name="distribution_daily_settlements")
	op.drop_table("distribution_daily_settlements")
	op.drop_index("ix_distribution_sales_targets_user_id", table_name="distribution_sales_targets")
	op.drop_index("ix_distribution_sales_targets_business_id", table_name="distribution_sales_targets")
	op.drop_table("distribution_sales_targets")
