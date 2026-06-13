"""پیش‌فرض اشتراک‌گذاری فاکتور در تنظیمات فروش سریع.

Revision ID: 20260630_000002_quick_sales_share_defaults
Revises: 20260630_000001_invoice_share_link_notification_event
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260630_000002_quick_sales_share_defaults"
down_revision = "20260630_000001_invoice_share_link_notification_event"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "quick_sales_settings",
        sa.Column(
            "default_share_online_payment",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("1"),
            comment="پرداخت آنلاین در لینک اشتراک فاکتور",
        ),
    )
    op.add_column(
        "quick_sales_settings",
        sa.Column(
            "default_share_gateway_id",
            sa.Integer(),
            nullable=True,
            comment="درگاه پیش‌فرض برای لینک پرداخت فاکتور",
        ),
    )
    op.add_column(
        "quick_sales_settings",
        sa.Column(
            "default_share_channels",
            sa.JSON(),
            nullable=True,
            comment="کانال‌های پیش‌فرض ارسال: sms, email, native",
        ),
    )
    op.add_column(
        "quick_sales_settings",
        sa.Column(
            "default_share_expiry_hours",
            sa.Integer(),
            nullable=False,
            server_default=sa.text("168"),
            comment="مدت اعتبار لینک اشتراک (ساعت)",
        ),
    )


def downgrade() -> None:
    op.drop_column("quick_sales_settings", "default_share_expiry_hours")
    op.drop_column("quick_sales_settings", "default_share_channels")
    op.drop_column("quick_sales_settings", "default_share_gateway_id")
    op.drop_column("quick_sales_settings", "default_share_online_payment")
