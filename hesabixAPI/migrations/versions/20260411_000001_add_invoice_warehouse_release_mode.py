"""add invoice_warehouse_release_mode to businesses

Revision ID: 20260411_000001_add_invoice_warehouse_release_mode
Revises: 20260410_000001_invoice_sync_product_prices
Create Date: 2026-04-11
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260411_000001_add_invoice_warehouse_release_mode"
down_revision = "20260410_000001_invoice_sync_product_prices"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"businesses",
		sa.Column(
			"invoice_warehouse_release_mode",
			sa.String(length=20),
			nullable=False,
			server_default="draft",
			comment="حواله پس از ثبت فاکتور: none, draft, posted",
		),
	)


def downgrade() -> None:
	op.drop_column("businesses", "invoice_warehouse_release_mode")
