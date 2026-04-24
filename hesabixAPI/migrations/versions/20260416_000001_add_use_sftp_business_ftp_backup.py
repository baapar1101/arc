"""add use_sftp flag for SFTP backup transport

Revision ID: 20260416_000001_add_use_sftp_business_ftp_backup
Revises: 20260415_000003_business_ftp_backup_settings
Create Date: 2026-04-16
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260416_000001_add_use_sftp_business_ftp_backup"
down_revision = "20260415_000003_business_ftp_backup_settings"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"business_ftp_backup_settings",
		sa.Column("use_sftp", sa.Boolean(), nullable=False, server_default=sa.text("false")),
	)


def downgrade() -> None:
	op.drop_column("business_ftp_backup_settings", "use_sftp")
