"""پل فاکتور خرید سرمایه‌ای: پیوند کارت دارایی به فاکتور/سطر.

Revision ID: 20261030_000001_fixed_assets_purchase_invoice_bridge
Revises: 20261028_000006_fixed_assets_legal_settings
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261030_000001_fixed_assets_purchase_invoice_bridge"
down_revision = "20261028_000006_fixed_assets_legal_settings"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"fa_assets",
		sa.Column("invoice_id", sa.Integer(), nullable=True),
	)
	op.add_column(
		"fa_assets",
		sa.Column("invoice_item_line_id", sa.Integer(), nullable=True),
	)
	op.create_index("ix_fa_assets_invoice_id", "fa_assets", ["invoice_id"])
	op.create_index(
		"uq_fa_assets_invoice_item_line_id",
		"fa_assets",
		["invoice_item_line_id"],
		unique=True,
		postgresql_where=sa.text("invoice_item_line_id IS NOT NULL"),
	)
	op.create_foreign_key(
		"fk_fa_assets_invoice_id_documents",
		"fa_assets",
		"documents",
		["invoice_id"],
		["id"],
		ondelete="SET NULL",
	)
	op.create_foreign_key(
		"fk_fa_assets_invoice_item_line_id",
		"fa_assets",
		"invoice_item_lines",
		["invoice_item_line_id"],
		["id"],
		ondelete="SET NULL",
	)


def downgrade() -> None:
	op.drop_constraint("fk_fa_assets_invoice_item_line_id", "fa_assets", type_="foreignkey")
	op.drop_constraint("fk_fa_assets_invoice_id_documents", "fa_assets", type_="foreignkey")
	op.drop_index("uq_fa_assets_invoice_item_line_id", table_name="fa_assets")
	op.drop_index("ix_fa_assets_invoice_id", table_name="fa_assets")
	op.drop_column("fa_assets", "invoice_item_line_id")
	op.drop_column("fa_assets", "invoice_id")
