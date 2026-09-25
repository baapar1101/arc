"""گالری تصاویر کاتالوگ شبکهٔ تأمین

Revision ID: 20260710_000001_product_catalog_gallery
Revises: 20260709_000001_product_supply_network_catalog
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260710_000001_product_catalog_gallery"
down_revision = "20260709_000001_product_supply_network_catalog"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"products",
		sa.Column(
			"catalog_gallery_file_ids",
			sa.JSON(),
			nullable=True,
			comment="شناسه‌های فایل گالری کاتالوگ (ترتیب نمایش)",
		),
	)


def downgrade() -> None:
	op.drop_column("products", "catalog_gallery_file_ids")
