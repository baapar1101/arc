"""ستون‌های موبایل ۲ و ۳ برای جدول اشخاص

Revision ID: 20260616_000001_person_mobile_2_3
Revises: 20260615_000002_business_permission_membership_expires_at
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260616_000001_person_mobile_2_3"
down_revision = "20260615_000002_business_permission_membership_expires_at"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"persons",
		sa.Column("mobile_2", sa.String(length=20), nullable=True, comment="موبایل ۲"),
	)
	op.add_column(
		"persons",
		sa.Column("mobile_3", sa.String(length=20), nullable=True, comment="موبایل ۳"),
	)


def downgrade() -> None:
	op.drop_column("persons", "mobile_3")
	op.drop_column("persons", "mobile_2")
