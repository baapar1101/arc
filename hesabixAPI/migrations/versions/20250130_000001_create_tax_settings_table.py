"""create tax_settings table

Revision ID: 20250130_000001_create_tax_settings_table
Revises: 20251120_053716_add_ai_tables
Create Date: 2025-01-30 10:00:00.000000

Note: This migration was created on 2025-01-30 but depends on a later migration (20251120).
This is intentional as it was merged after the later migration was created.

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect


# revision identifiers, used by Alembic.
revision = "20250130_000001_create_tax_settings_table"
down_revision = "20251120_053716_add_ai_tables"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = inspect(bind)
    created_table = False

    if not inspector.has_table("tax_settings"):
        op.create_table(
            "tax_settings",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("business_id", sa.Integer(), nullable=False),
            sa.Column("created_by_user_id", sa.Integer(), nullable=True),
            sa.Column("tax_memory_id", sa.String(length=128), nullable=True),
            sa.Column("economic_code", sa.String(length=64), nullable=True),
            sa.Column("private_key", sa.Text(), nullable=True),
            sa.Column("public_key", sa.Text(), nullable=True),
            sa.Column("certificate", sa.Text(), nullable=True),
            sa.Column("certificate_request", sa.Text(), nullable=True),
            sa.Column("sandbox_mode", sa.Boolean(), nullable=False, server_default=sa.text("0")),
            sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
            sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
            sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
            sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="SET NULL"),
            sa.UniqueConstraint("business_id", name="uq_tax_settings_business"),
        )
        created_table = True

    existing_indexes = {idx["name"] for idx in inspector.get_indexes("tax_settings")}

    if created_table or "ix_tax_settings_business_id" not in existing_indexes:
        try:
            op.create_index(op.f("ix_tax_settings_business_id"), "tax_settings", ["business_id"], unique=False)
        except Exception:
            pass

    if created_table or "ix_tax_settings_created_by_user_id" not in existing_indexes:
        try:
            op.create_index(op.f("ix_tax_settings_created_by_user_id"), "tax_settings", ["created_by_user_id"], unique=False)
        except Exception:
            pass


def downgrade() -> None:
    bind = op.get_bind()
    inspector = inspect(bind)

    if inspector.has_table("tax_settings"):
        existing_indexes = {idx["name"] for idx in inspector.get_indexes("tax_settings")}
        if "ix_tax_settings_created_by_user_id" in existing_indexes:
            try:
                op.drop_index(op.f("ix_tax_settings_created_by_user_id"), table_name="tax_settings")
            except Exception:
                pass
        if "ix_tax_settings_business_id" in existing_indexes:
            try:
                op.drop_index(op.f("ix_tax_settings_business_id"), table_name="tax_settings")
            except Exception:
                pass
        op.drop_table("tax_settings")


