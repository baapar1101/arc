"""جدا کردن نمایش بازار از فعال‌سازی سراسری افزونه.

Revision ID: 20261104_000001_plugin_global_enable
Revises: 20261102_000004_inventory_lots_expiry
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261104_000001_plugin_global_enable"
down_revision = "20261102_000004_inventory_lots_expiry"
branch_labels = None
depends_on = None


def _column_names(table: str) -> set[str]:
	bind = op.get_bind()
	insp = sa.inspect(bind)
	if table not in insp.get_table_names():
		return set()
	return {c["name"] for c in insp.get_columns(table)}


def upgrade() -> None:
	cols = _column_names("marketplace_plugins")
	if not cols:
		return
	if "listed_in_marketplace" not in cols:
		op.add_column(
			"marketplace_plugins",
			sa.Column(
				"listed_in_marketplace",
				sa.Boolean(),
				nullable=False,
				server_default=sa.true(),
			),
		)
	if "enabled_for_all_businesses" not in cols:
		op.add_column(
			"marketplace_plugins",
			sa.Column(
				"enabled_for_all_businesses",
				sa.Boolean(),
				nullable=False,
				server_default=sa.false(),
			),
		)


def downgrade() -> None:
	cols = _column_names("marketplace_plugins")
	if "enabled_for_all_businesses" in cols:
		op.drop_column("marketplace_plugins", "enabled_for_all_businesses")
	if "listed_in_marketplace" in cols:
		op.drop_column("marketplace_plugins", "listed_in_marketplace")
