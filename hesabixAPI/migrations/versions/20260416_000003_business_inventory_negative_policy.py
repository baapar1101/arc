"""Business policy: optional negative stock on warehouse post (bulk/unique/transfer)

Revision ID: 20260416_000003_business_inventory_negative_policy
Revises: 20260416_000002_crm_notes_calendar
Create Date: 2026-04-16
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260416_000003_business_inventory_negative_policy"
down_revision = "20260416_000002_crm_notes_calendar"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"businesses",
		sa.Column(
			"allow_negative_inventory_for_bulk",
			sa.Boolean(),
			nullable=False,
			server_default=sa.text("false"),
			comment="اجازه خروج با موجودی منفی برای کالاهای فله‌ای (غیر یونیک) هنگام قطعی حواله",
		),
	)
	op.add_column(
		"businesses",
		sa.Column(
			"allow_negative_inventory_for_unique",
			sa.Boolean(),
			nullable=False,
			server_default=sa.text("false"),
			comment="اجازه خروج با موجودی منفی برای کالاهای یونیک هنگام قطعی حواله",
		),
	)
	op.add_column(
		"businesses",
		sa.Column(
			"warehouse_transfer_require_positive_stock",
			sa.Boolean(),
			nullable=False,
			server_default=sa.text("true"),
			comment="اگر true باشد، حواله انتقال همیشه کنترل کسری کامل دارد (صرف‌نظر از اجازه منفی)",
		),
	)


def downgrade() -> None:
	op.drop_column("businesses", "warehouse_transfer_require_positive_stock")
	op.drop_column("businesses", "allow_negative_inventory_for_unique")
	op.drop_column("businesses", "allow_negative_inventory_for_bulk")
