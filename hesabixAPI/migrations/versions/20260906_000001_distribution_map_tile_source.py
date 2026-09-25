"""منبع تایل نقشه پخش مویرگی: OSM جهانی یا می‌مپس با کلید API.

Revision ID: 20260906_000001_distribution_map_tile_source
Revises: 20260902_000002_distribution_target_product_key
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260906_000001_distribution_map_tile_source"
down_revision = "20260902_000002_distribution_target_product_key"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"distribution_business_settings",
		sa.Column(
			"map_tile_source",
			sa.String(length=32),
			nullable=False,
			server_default="osm",
			comment="منبع تایل نقشه: osm یا memaps",
		),
	)
	op.add_column(
		"distribution_business_settings",
		sa.Column(
			"memaps_api_key",
			sa.String(length=255),
			nullable=True,
			comment="کلید API می‌مپس (query key یا هدر X-Memaps-Key)",
		),
	)


def downgrade() -> None:
	op.drop_column("distribution_business_settings", "memaps_api_key")
	op.drop_column("distribution_business_settings", "map_tile_source")
