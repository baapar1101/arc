"""P6: قیمت ارزی کالا + همگام‌سازی اختیاری با نرخ

Revision ID: 20260725_000002_product_fx_prices
Revises: 20260725_000001_document_lines_fx_base_amounts
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260725_000002_product_fx_prices"
down_revision = "20260725_000001_document_lines_fx_base_amounts"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"products",
		sa.Column(
			"sales_price_fx",
			sa.Numeric(18, 6),
			nullable=True,
			comment="قیمت فروش به ارز فرعی (price_fx_currency_id)",
		),
	)
	op.add_column(
		"products",
		sa.Column(
			"purchase_price_fx",
			sa.Numeric(18, 6),
			nullable=True,
			comment="قیمت خرید به ارز فرعی (price_fx_currency_id)",
		),
	)
	op.add_column(
		"products",
		sa.Column(
			"price_fx_currency_id",
			sa.Integer(),
			sa.ForeignKey("currencies.id", ondelete="SET NULL"),
			nullable=True,
			comment="ارز قیمت‌های *_price_fx",
		),
	)
	op.add_column(
		"products",
		sa.Column(
			"auto_update_base_from_fx",
			sa.Boolean(),
			nullable=False,
			server_default=sa.text("false"),
			comment="در صورت true، قیمت پایه از قیمت ارزی × نرخ روز به‌روز می‌شود",
		),
	)
	op.create_index(
		"ix_products_price_fx_currency_id",
		"products",
		["price_fx_currency_id"],
		unique=False,
	)


def downgrade() -> None:
	op.drop_index("ix_products_price_fx_currency_id", table_name="products")
	op.drop_column("products", "auto_update_base_from_fx")
	op.drop_column("products", "price_fx_currency_id")
	op.drop_column("products", "purchase_price_fx")
	op.drop_column("products", "sales_price_fx")
