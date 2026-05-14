"""ستون membership_expires_at برای عضویت زمان‌دار در کسب‌وکار

Revision ID: 20260615_000002_business_permission_membership_expires_at
Revises: 20260615_000001_seed_woocommerce_hesabix_marketplace
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260615_000002_business_permission_membership_expires_at"
down_revision = "20260615_000001_seed_woocommerce_hesabix_marketplace"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"business_permissions",
		sa.Column("membership_expires_at", sa.DateTime(), nullable=True),
	)
	op.create_index(
		"ix_business_permissions_membership_expires_at",
		"business_permissions",
		["membership_expires_at"],
		unique=False,
	)


def downgrade() -> None:
	op.drop_index("ix_business_permissions_membership_expires_at", table_name="business_permissions")
	op.drop_column("business_permissions", "membership_expires_at")
