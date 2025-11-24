"""add product tax codes table

Revision ID: 20251124_150001_add_product_tax_codes
Revises: 20251124_000001_seed_tax_types_list, 20241120_000001_add_document_numbering_settings
Create Date: 2025-11-24 13:30:00.000000

"""

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "20251124_150001_add_product_tax_codes"
down_revision = ("20251124_000001_seed_tax_types_list", "20241120_000001_add_document_numbering_settings")
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "product_tax_codes",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("code", sa.String(length=32), nullable=False, unique=True),
        sa.Column("description", sa.String(length=1024), nullable=False),
        sa.Column("vat_rate", sa.String(length=16), nullable=True),
        sa.Column("taxable_status", sa.String(length=64), nullable=True),
        sa.Column("run_date", sa.String(length=32), nullable=True),
        sa.Column("expiration_date", sa.String(length=32), nullable=True),
        sa.Column("create_date", sa.String(length=32), nullable=True),
        sa.Column("last_edit_date", sa.String(length=32), nullable=True),
        sa.Column("source_type", sa.String(length=128), nullable=True),
        sa.Column("pricing_description", sa.String(length=1024), nullable=True),
        sa.Column("source_filename", sa.String(length=255), nullable=True),
        sa.Column("source_checksum", sa.String(length=64), nullable=True),
        sa.Column("imported_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column(
            "updated_at",
            sa.DateTime(),
            nullable=False,
            server_default=sa.func.now(),
            onupdate=sa.func.now(),
        ),
        mysql_charset="utf8mb4",
    )
    op.create_index("ix_product_tax_codes_code", "product_tax_codes", ["code"], unique=True)


def downgrade() -> None:
    op.drop_index("ix_product_tax_codes_code", table_name="product_tax_codes")
    op.drop_table("product_tax_codes")


