"""Barcode label printer settings table.

Revision ID: 20260806_000002_barcode_label_printer_settings
Revises: 20260806_000001_barcode_label_studio
Create Date: 2026-08-06
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260806_000002_barcode_label_printer_settings"
down_revision = "20260806_000001_barcode_label_studio"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"barcode_label_settings",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("settings_json", sa.JSON(), nullable=False),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", name="uq_barcode_label_settings_business"),
	)
	op.create_index("ix_barcode_label_settings_business_id", "barcode_label_settings", ["business_id"])


def downgrade() -> None:
	op.drop_table("barcode_label_settings")
