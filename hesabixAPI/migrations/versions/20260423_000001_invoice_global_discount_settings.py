"""تنظیمات تخفیف کلی فاکتور روی کسب‌وکار

Revision ID: 20260423_000001_invoice_global_discount_settings
Revises: 20260422_000001_customer_club_rfm_analytics
Create Date: 2026-04-23
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260423_000001_invoice_global_discount_settings"
down_revision = "20260422_000001_customer_club_rfm_analytics"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"businesses",
		sa.Column(
			"invoice_global_discount_percent_basis",
			sa.String(length=64),
			nullable=False,
			server_default=sa.text("'subtotal_after_line_discount'"),
			comment=(
				"مبنای درصد تخفیف کلی: subtotal_after_line_discount | gross_before_line_discount | "
				"total_after_lines_including_tax"
			),
		),
	)
	op.add_column(
		"businesses",
		sa.Column(
			"invoice_global_discount_tax_mode",
			sa.String(length=64),
			nullable=False,
			server_default=sa.text("'recalculate_tax_proportional'"),
			comment=(
				"اثر تخفیف کلی بر مالیات: recalculate_tax_proportional | keep_line_taxes"
			),
		),
	)
	op.add_column(
		"businesses",
		sa.Column(
			"invoice_global_discount_max_percent",
			sa.Numeric(precision=5, scale=2),
			nullable=True,
			comment="سقف درصد تخفیف کلی نسبت به مبنا (اختیاری)",
		),
	)
	op.add_column(
		"businesses",
		sa.Column(
			"invoice_global_discount_max_amount",
			sa.Numeric(precision=18, scale=2),
			nullable=True,
			comment="سقف مبلغ تخفیف کلی (اختیاری)",
		),
	)


def downgrade() -> None:
	op.drop_column("businesses", "invoice_global_discount_max_amount")
	op.drop_column("businesses", "invoice_global_discount_max_percent")
	op.drop_column("businesses", "invoice_global_discount_tax_mode")
	op.drop_column("businesses", "invoice_global_discount_percent_basis")
