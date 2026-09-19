"""P2.5: مبالغ پایه و نرخ تسعیر روی خطوط سند (nullable، سازگار با گذشته)

Revision ID: 20260725_000001_document_lines_fx_base_amounts
Revises: 20260724_000004_telegram_link_tokens_timestamps

ستون‌ها اختیاری‌اند تا کسب‌وکارهای تک‌ارزی و اسناد قدیمی بدون تغییر اجباری بمانند.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260725_000001_document_lines_fx_base_amounts"
down_revision = "20260724_000004_telegram_link_tokens_timestamps"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"document_lines",
		sa.Column(
			"exchange_rate",
			sa.Numeric(24, 10),
			nullable=True,
			comment="نرخ قفل‌شده: ۱ واحد ارز سند = exchange_rate × ارز پایه",
		),
	)
	op.add_column(
		"document_lines",
		sa.Column(
			"debit_base",
			sa.Numeric(24, 6),
			nullable=True,
			comment="بدهکار به ارز پایه کسب‌وکار (پس از تسعیر)",
		),
	)
	op.add_column(
		"document_lines",
		sa.Column(
			"credit_base",
			sa.Numeric(24, 6),
			nullable=True,
			comment="بستانکار به ارز پایه کسب‌وکار (پس از تسعیر)",
		),
	)


def downgrade() -> None:
	op.drop_column("document_lines", "credit_base")
	op.drop_column("document_lines", "debit_base")
	op.drop_column("document_lines", "exchange_rate")
