"""Customer club v2: redemption, tiers, expiry setting, snapshot redeemed_points

Revision ID: 20260419_000001_customer_club_v2_enhancements
Revises: 20260418_000004_warehouse_document_line_location
Create Date: 2026-04-19
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260419_000001_customer_club_v2_enhancements"
down_revision = "20260418_000004_warehouse_document_line_location"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"customer_club_settings",
		sa.Column(
			"currency_value_per_point",
			sa.Numeric(precision=18, scale=8),
			nullable=True,
			comment="مبلغ تخفیف به ازای هر امتیاز (در ارز فاکتور)",
		),
	)
	op.add_column(
		"customer_club_settings",
		sa.Column(
			"max_redeem_points_per_invoice",
			sa.Numeric(precision=18, scale=4),
			nullable=True,
			comment="سقف امتیاز قابل مصرف در هر فاکتور فروش",
		),
	)
	op.add_column(
		"customer_club_settings",
		sa.Column(
			"points_expire_after_days",
			sa.Integer(),
			nullable=True,
			comment="انقضای امتیاز پس از N روز از آخرین تراکنش مثبت (NULL=غیرفعال در Job)",
		),
	)

	op.add_column(
		"customer_club_invoice_snapshots",
		sa.Column(
			"redeemed_points",
			sa.Numeric(precision=18, scale=6),
			nullable=False,
			server_default=sa.text("0"),
			comment="امتیاز مصرف‌شده در این فاکتور",
		),
	)

	op.create_table(
		"customer_club_tiers",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("sort_order", sa.Integer(), nullable=False, server_default=sa.text("0")),
		sa.Column("name", sa.String(length=120), nullable=False),
		sa.Column(
			"min_balance_points",
			sa.Numeric(precision=18, scale=6),
			nullable=False,
			server_default=sa.text("0"),
			comment="حداقل مانده امتیاز برای ورود به این سطح",
		),
		sa.Column(
			"earn_multiplier",
			sa.Numeric(precision=18, scale=6),
			nullable=False,
			server_default=sa.text("1"),
			comment="ضریب امتیاز کسب‌شده نسبت به پایه",
		),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		mysql_charset="utf8mb4",
	)
	op.create_index(op.f("ix_customer_club_tiers_business_id"), "customer_club_tiers", ["business_id"], unique=False)


def downgrade() -> None:
	op.drop_index(op.f("ix_customer_club_tiers_business_id"), table_name="customer_club_tiers")
	op.drop_table("customer_club_tiers")
	op.drop_column("customer_club_invoice_snapshots", "redeemed_points")
	op.drop_column("customer_club_settings", "points_expire_after_days")
	op.drop_column("customer_club_settings", "max_redeem_points_per_invoice")
	op.drop_column("customer_club_settings", "currency_value_per_point")
