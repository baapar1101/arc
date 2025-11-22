"""add default_warehouse_id to products table

Revision ID: 20251120_000001_add_default_warehouse_to_products
Revises: 20251119_000001_add_person_share_links
Create Date: 2025-11-20 00:00:01.000001

"""

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "20251120_000001_add_default_warehouse_to_products"
down_revision = "20251119_000001_add_person_share_links"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    table_name = "products"

    if table_name in inspector.get_table_names():
        columns = {col["name"] for col in inspector.get_columns(table_name)}
        indexes = {idx["name"] for idx in inspector.get_indexes(table_name)}
        if "default_warehouse_id" not in columns:
            op.add_column(
                table_name,
                sa.Column(
                    "default_warehouse_id",
                    sa.Integer(),
                    sa.ForeignKey("warehouses.id", ondelete="SET NULL"),
                    nullable=True,
                    comment="انبار پیش‌فرض برای کالا",
                ),
            )
        if "ix_products_default_warehouse_id" not in indexes:
            op.create_index(
                "ix_products_default_warehouse_id",
                table_name,
                ["default_warehouse_id"],
                unique=False,
            )


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    table_name = "products"

    if table_name in inspector.get_table_names():
        columns = {col["name"] for col in inspector.get_columns(table_name)}
        if "default_warehouse_id" in columns:
            op.drop_index("ix_products_default_warehouse_id", table_name=table_name)
            op.drop_column(table_name, "default_warehouse_id")

