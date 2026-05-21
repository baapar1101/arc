"""امنیت بکاپ: لاگ ایمپورت و جلوگیری از تکرار فایل پشتیبان

Revision ID: 20260621_000001_backup_import_security
Revises: 20260620_000001_product_public_catalog
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260621_000001_backup_import_security"
down_revision = "20260620_000001_product_public_catalog"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "business_backup_import_logs",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("backup_checksum", sa.String(64), nullable=False),
        sa.Column("import_mode", sa.String(32), nullable=False, server_default="new_business"),
        sa.Column("source_business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="SET NULL"), nullable=True),
        sa.Column("target_business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("now()")),
        sa.UniqueConstraint(
            "user_id",
            "backup_checksum",
            "import_mode",
            name="uq_business_backup_import_user_checksum_mode",
        ),
    )
    op.create_index("ix_business_backup_import_logs_user_id", "business_backup_import_logs", ["user_id"])
    op.create_index("ix_business_backup_import_logs_backup_checksum", "business_backup_import_logs", ["backup_checksum"])
    op.create_index("ix_business_backup_import_logs_target_business_id", "business_backup_import_logs", ["target_business_id"])


def downgrade() -> None:
    op.drop_table("business_backup_import_logs")
