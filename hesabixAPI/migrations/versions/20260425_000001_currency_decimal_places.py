"""تنظیمات اعشار و گرد کردن مبلغ برای هر ارز

Revision ID: 20260425_000001_currency_decimal_places
Revises: 20260424_000001_customer_club_loyalty_rfm_integration
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260425_000001_currency_decimal_places"
down_revision = "20260424_000001_customer_club_loyalty_rfm_integration"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"currencies",
		sa.Column(
			"decimal_places",
			sa.SmallInteger(),
			nullable=False,
			server_default="2",
			comment="تعداد اعشار مبلغ (۰=بدون اعشار مثل ریال، ۲=مثل دلار)",
		),
	)
	op.add_column(
		"currencies",
		sa.Column(
			"round_monetary_amounts",
			sa.Boolean(),
			nullable=False,
			server_default=sa.text("true"),
			comment="اگر true باشد مبالغ در محاسبات به decimal_places گرد می‌شوند",
		),
	)
	op.execute(
		sa.text(
			"UPDATE currencies SET decimal_places = 0 WHERE UPPER(TRIM(code)) = 'IRR'"
		)
	)


def downgrade() -> None:
	op.drop_column("currencies", "round_monetary_amounts")
	op.drop_column("currencies", "decimal_places")
