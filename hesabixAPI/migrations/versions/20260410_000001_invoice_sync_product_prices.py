"""invoice sync product base prices from finalized invoices

Revision ID: 20260410_000001_invoice_sync_product_prices
Revises: 20260409_000001_add_admin_script_runs_tables
Create Date: 2026-04-10
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260410_000001_invoice_sync_product_prices"
down_revision = "20260409_000001_add_admin_script_runs_tables"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"businesses",
		sa.Column(
			"invoice_sync_update_sales_price_enabled",
			sa.Boolean(),
			nullable=False,
			server_default="0",
			comment="به‌روزرسانی خودکار قیمت فروش کالا از فاکتور فروش قطعی",
		),
	)
	op.add_column(
		"businesses",
		sa.Column(
			"invoice_sync_update_purchase_price_enabled",
			sa.Boolean(),
			nullable=False,
			server_default="0",
			comment="به‌روزرسانی خودکار قیمت خرید کالا از فاکتور خرید قطعی",
		),
	)
	op.add_column(
		"businesses",
		sa.Column(
			"invoice_sync_sales_price_basis",
			sa.String(length=40),
			nullable=True,
			server_default=sa.text("'net_after_line_discount'"),
			comment="مبنای محاسبه قیمت فروش: unit_price, net_after_line_discount, net_with_tax, cost_price",
		),
	)
	op.add_column(
		"businesses",
		sa.Column(
			"invoice_sync_purchase_price_basis",
			sa.String(length=40),
			nullable=True,
			server_default=sa.text("'net_after_line_discount'"),
			comment="مبنای محاسبه قیمت خرید: unit_price, net_after_line_discount, net_with_tax, cost_price",
		),
	)


def downgrade() -> None:
	op.drop_column("businesses", "invoice_sync_purchase_price_basis")
	op.drop_column("businesses", "invoice_sync_sales_price_basis")
	op.drop_column("businesses", "invoice_sync_update_purchase_price_enabled")
	op.drop_column("businesses", "invoice_sync_update_sales_price_enabled")
