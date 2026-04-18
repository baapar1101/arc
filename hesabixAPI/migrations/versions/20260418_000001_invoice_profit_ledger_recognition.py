"""Invoice profit ledger recognition (analytical vs recognized COGS)

Revision ID: 20260418_000001_invoice_profit_ledger_recognition
Revises: 20260417_000002_workflow_marketplace
Create Date: 2026-04-18
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260418_000001_invoice_profit_ledger_recognition"
down_revision = "20260417_000002_workflow_marketplace"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"businesses",
		sa.Column(
			"invoice_profit_ledger_recognition_basis",
			sa.String(length=40),
			nullable=False,
			server_default=sa.text("'warehouse_document_posting'"),
			comment=(
				"زمان شناسایی بهای تمام‌شده قطعی در دفتر: "
				"warehouse_document_posting | sales_invoice_document"
			),
		),
	)
	op.add_column(
		"invoice_item_lines",
		sa.Column(
			"ledger_unit_cogs",
			sa.Numeric(precision=18, scale=6),
			nullable=True,
			comment="بهای تمام‌شده واحد کالای فروش رفته — شناسایی‌شده (قطعی دفتر)",
		),
	)
	op.add_column(
		"invoice_item_lines",
		sa.Column(
			"ledger_line_cogs",
			sa.Numeric(precision=18, scale=2),
			nullable=True,
			comment="جمع بهای تمام‌شده خط — شناسایی‌شده (قطعی دفتر)",
		),
	)
	op.add_column(
		"invoice_item_lines",
		sa.Column(
			"ledger_line_gross_profit",
			sa.Numeric(precision=18, scale=2),
			nullable=True,
			comment="سود ناخالص خط پس از شناسایی بهای تمام‌شده قطعی",
		),
	)
	op.add_column(
		"invoice_item_lines",
		sa.Column(
			"ledger_recognized_at",
			sa.DateTime(),
			nullable=True,
			comment="زمان شناسایی بهای تمام‌شده قطعی برای این خط",
		),
	)
	op.add_column(
		"invoice_item_lines",
		sa.Column(
			"ledger_recognition_event",
			sa.String(length=40),
			nullable=True,
			comment="رویداد شناسایی: warehouse_document_posting | sales_invoice_document",
		),
	)


def downgrade() -> None:
	op.drop_column("invoice_item_lines", "ledger_recognition_event")
	op.drop_column("invoice_item_lines", "ledger_recognized_at")
	op.drop_column("invoice_item_lines", "ledger_line_gross_profit")
	op.drop_column("invoice_item_lines", "ledger_line_cogs")
	op.drop_column("invoice_item_lines", "ledger_unit_cogs")
	op.drop_column("businesses", "invoice_profit_ledger_recognition_basis")
