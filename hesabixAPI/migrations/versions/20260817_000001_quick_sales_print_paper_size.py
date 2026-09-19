"""Add print_paper_size to quick sales settings.

Revision ID: 20260817_000001_quick_sales_print_paper_size
Revises: 20260806_000003_telephony_softphone_media_relay
Create Date: 2026-08-17
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260817_000001_quick_sales_print_paper_size"
down_revision = "20260806_000003_telephony_softphone_media_relay"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"quick_sales_settings",
		sa.Column(
			"print_paper_size",
			sa.String(length=16),
			nullable=True,
			comment="سایز کاغذ چاپ: A4/A5/A6 یا 60mm/80mm/100mm",
		),
	)


def downgrade() -> None:
	op.drop_column("quick_sales_settings", "print_paper_size")
