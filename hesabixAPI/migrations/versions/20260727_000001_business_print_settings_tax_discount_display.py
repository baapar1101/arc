"""تنظیمات چاپ: نمایش مالیات و تخفیف در PDF فاکتور

Revision ID: 20260727_000001_business_print_settings_tax_discount_display
Revises: 20260726_000002_hscript_schedules
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260727_000001_business_print_settings_tax_discount_display"
down_revision = "20260726_000002_hscript_schedules"
branch_labels = None
depends_on = None

_DISPLAY_COLUMNS = (
    "line_discount_display",
    "line_tax_display",
    "line_amount_before_discount_display",
    "line_amount_before_tax_display",
    "summary_discount_display",
    "summary_tax_display",
    "summary_amount_without_tax_display",
)


def upgrade() -> None:
    for column_name in _DISPLAY_COLUMNS:
        op.add_column(
            "business_print_settings",
            sa.Column(
                column_name,
                sa.String(length=16),
                nullable=False,
                server_default=sa.text("'smart'"),
            ),
        )


def downgrade() -> None:
    for column_name in reversed(_DISPLAY_COLUMNS):
        op.drop_column("business_print_settings", column_name)
