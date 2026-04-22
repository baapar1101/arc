"""تاریخچه نرخ تسعیر ارز نسبت به ارز اصلی کسب‌وکار (چند نرخ در یک روز مجاز)

Revision ID: 20260426_000001_business_currency_rates
Revises: 20260425_000001_currency_decimal_places
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260426_000001_business_currency_rates"
down_revision = "20260425_000001_currency_decimal_places"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"business_currency_rates",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("currency_id", sa.Integer(), nullable=False),
		sa.Column(
			"effective_at",
			sa.DateTime(timezone=True),
			nullable=False,
			comment="زمان مؤثر نرخ؛ چند رکورد در یک روز با زمان‌های متفاوت مجاز است",
		),
		sa.Column(
			"rate",
			sa.Numeric(24, 10),
			nullable=False,
			comment="۱ واحد currency_id معادل چند واحد از ارز اصلی کسب‌وکار (پایه)",
		),
		sa.Column("note", sa.Text(), nullable=True),
		sa.Column("created_by_user_id", sa.Integer(), nullable=False),
		sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
		sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["currency_id"], ["currencies.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="RESTRICT"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_business_currency_rates_business_id", "business_currency_rates", ["business_id"], unique=False)
	op.create_index("ix_business_currency_rates_currency_id", "business_currency_rates", ["currency_id"], unique=False)
	op.create_index(
		"ix_business_currency_rates_business_currency_effective",
		"business_currency_rates",
		["business_id", "currency_id", "effective_at"],
		unique=False,
	)


def downgrade() -> None:
	op.drop_index("ix_business_currency_rates_business_currency_effective", table_name="business_currency_rates")
	op.drop_index("ix_business_currency_rates_currency_id", table_name="business_currency_rates")
	op.drop_index("ix_business_currency_rates_business_id", table_name="business_currency_rates")
	op.drop_table("business_currency_rates")
