"""merge_heads

Revision ID: 4b2ea782bcb3
Revises: 20250120_000003, 20250927_000022_add_person_commission_fields
Create Date: 2025-09-28 20:59:14.557570

"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect


# revision identifiers, used by Alembic.
revision = '4b2ea782bcb3'
down_revision = ('20250120_000002', '20250927_000022_add_person_commission_fields')
branch_labels = None
depends_on = None


def upgrade() -> None:
    # این migration صرفاً برای ادغام شاخه‌ها است و تغییری در اسکیما ایجاد نمی‌کند
    pass


def downgrade() -> None:
    # بدون تغییر
    pass
