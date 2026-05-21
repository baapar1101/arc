"""Merge heads: business_backup_import_security + public_catalog_price_flag

Revision ID: 20260621_000002_merge_heads_backup_import_security_and_public_catalog_price_flag
Revises: 20260621_000001_backup_import_security, 20260621_000001_public_catalog_price_flag
Create Date: 2026-06-21

"""

from __future__ import annotations

from alembic import op  # noqa: F401

revision = "20260621_000002_merge_heads_backup_import_security_and_public_catalog_price_flag"
down_revision = (
	"20260621_000001_backup_import_security",
	"20260621_000001_public_catalog_price_flag",
)
branch_labels = None
depends_on = None


def upgrade() -> None:
	pass


def downgrade() -> None:
	pass
