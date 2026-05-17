"""تنظیمات پیش‌فرض پرداخت آنلاین لینک عمومی فاکتور روی کسب‌وکار

Revision ID: 20260616_000002_business_invoice_share_settings
Revises: 20260616_000001_person_mobile_2_3
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260616_000002_business_invoice_share_settings"
down_revision = "20260616_000001_person_mobile_2_3"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"businesses",
		sa.Column(
			"invoice_share_settings",
			sa.JSON(),
			nullable=True,
			comment="پیش‌فرض‌های لینک اشتراک فاکتور (مثلاً پرداخت آنلاین)",
		),
	)


def downgrade() -> None:
	op.drop_column("businesses", "invoice_share_settings")
