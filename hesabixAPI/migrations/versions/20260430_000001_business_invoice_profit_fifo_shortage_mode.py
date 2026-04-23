"""سیاست کسری لایه در سود فاکتور (FIFO/LIFO)

Revision ID: 20260430_000001_business_invoice_profit_fifo_shortage_mode
Revises: 20260429_000002_document_share_links
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260430_000001_business_invoice_profit_fifo_shortage_mode"
down_revision = "20260429_000002_document_share_links"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"businesses",
		sa.Column(
			"invoice_profit_fifo_shortage_mode",
			sa.String(40),
			nullable=False,
			server_default=sa.text("'perpetual_mixed'"),
			comment="سود FIFO/LIFO: perpetual_mixed | average_purchase_on_shortage",
		),
	)


def downgrade() -> None:
	op.drop_column("businesses", "invoice_profit_fifo_shortage_mode")
