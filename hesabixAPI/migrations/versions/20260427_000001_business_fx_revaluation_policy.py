"""سیاست تسعیر فاکتور/اسناد (JSON روی کسب‌وکار)

Revision ID: 20260427_000001_business_fx_revaluation_policy
Revises: 20260426_000001_business_currency_rates
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260427_000001_business_fx_revaluation_policy"
down_revision = "20260426_000001_business_currency_rates"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"businesses",
		sa.Column(
			"fx_revaluation_policy",
			sa.JSON(),
			nullable=True,
			comment=(
				"سیاست تسعیر: as_of_source، document_date_effective، when_no_rate — "
				"مقادیر پیش‌فرض در کد اگر null"
			),
		),
	)


def downgrade() -> None:
	op.drop_column("businesses", "fx_revaluation_policy")
