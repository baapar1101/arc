"""business FTP backup settings per business

Revision ID: 20260415_000003_business_ftp_backup_settings
Revises: 20260415_000002_crm_activity_lead_and_indexes
Create Date: 2026-04-15
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260415_000003_business_ftp_backup_settings"
down_revision = "20260415_000002_crm_activity_lead_and_indexes"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"business_ftp_backup_settings",
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("host", sa.String(length=255), nullable=False),
		sa.Column("port", sa.Integer(), nullable=False, server_default="21"),
		sa.Column("username", sa.String(length=255), nullable=False),
		sa.Column("password_encrypted", sa.Text(), nullable=True),
		sa.Column("remote_path", sa.String(length=1024), nullable=False, server_default="/"),
		sa.Column("passive", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("use_ftps", sa.Boolean(), nullable=False, server_default=sa.text("false")),
		sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
		sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("business_id"),
	)


def downgrade() -> None:
	op.drop_table("business_ftp_backup_settings")
