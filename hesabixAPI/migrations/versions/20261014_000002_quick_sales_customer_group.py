"""Add the default person group for quick-created sales customers.

Revision ID: 20261014_000002_quick_sales_customer_group
Revises: 20261014_000001_merge_tax_and_quick_sales_heads
"""

import sqlalchemy as sa
from alembic import op


revision = "20261014_000002_quick_sales_customer_group"
down_revision = "20261014_000001_merge_tax_and_quick_sales_heads"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "quick_sales_settings",
        sa.Column(
            "quick_customer_group_id",
            sa.Integer(),
            nullable=True,
            comment="گروه پیش‌فرض مشتریانی که در فروش سریع ثبت می‌شوند",
        ),
    )
    op.create_foreign_key(
        "fk_quick_sales_settings_quick_customer_group_id_person_groups",
        "quick_sales_settings",
        "person_groups",
        ["quick_customer_group_id"],
        ["id"],
        ondelete="SET NULL",
    )


def downgrade() -> None:
    op.drop_constraint(
        "fk_quick_sales_settings_quick_customer_group_id_person_groups",
        "quick_sales_settings",
        type_="foreignkey",
    )
    op.drop_column("quick_sales_settings", "quick_customer_group_id")
