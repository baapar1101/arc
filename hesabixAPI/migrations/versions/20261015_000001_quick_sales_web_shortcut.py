"""Add web shortcuts to quick-sales payment buttons.

Revision ID: 20261015_000001_quick_sales_web_shortcut
Revises: 20261014_000002_quick_sales_customer_group
"""

import sqlalchemy as sa
from alembic import op


revision = "20261015_000001_quick_sales_web_shortcut"
down_revision = "20261014_000002_quick_sales_customer_group"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "quick_sales_payment_buttons",
        sa.Column(
            "web_shortcut",
            sa.String(length=32),
            nullable=True,
            comment="میانبر پیش‌فرض دکمه پرداخت در رابط وب",
        ),
    )


def downgrade() -> None:
    op.drop_column("quick_sales_payment_buttons", "web_shortcut")
