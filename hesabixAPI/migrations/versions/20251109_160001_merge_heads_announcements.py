"""merge multiple heads after adding announcements

Revision ID: 20251109_160001_merge_heads_announcements
Revises: 20251021_000601_add_bom_and_warehouses, 20251102_120001_add_check_status_fields, 20251108_230001_add_report_templates, 20251109_150001_add_announcements_tables, 9a06b0cb880a
Create Date: 2025-11-09 16:00:01
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20251109_160001_merge_heads_announcements'
down_revision = (
    '20251021_000601_add_bom_and_warehouses',
    '20251102_120001_add_check_status_fields',
    '20251108_230001_add_report_templates',
    '20251109_150001_add_announcements_tables',
    '9a06b0cb880a',
)
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Merge migration - no schema changes
    pass


def downgrade() -> None:
    # Merge migration - no schema changes
    pass


