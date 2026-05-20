"""کاتالوگ عمومی: فلگ نمایش قیمت فروش پایه برای کسب‌وکار

Revision ID: 20260621_000001_public_catalog_price_flag
Revises: 20260620_000001_product_public_catalog
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy import true as sql_true

revision = "20260621_000001_public_catalog_price_flag"
down_revision = "20260620_000001_product_public_catalog"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"businesses",
		sa.Column(
			"public_catalog_show_base_sales_price",
			sa.Boolean(),
			nullable=False,
			server_default=sql_true(),
			comment="نمایش قیمت فروش پایه در API عمومی کاتالوگ",
		),
	)


def downgrade() -> None:
	op.drop_column("businesses", "public_catalog_show_base_sales_price")
