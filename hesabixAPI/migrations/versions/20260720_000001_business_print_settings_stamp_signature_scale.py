"""تنظیمات چاپ: مقیاس درصد مهر و امضا در PDF

Revision ID: 20260720_000001_business_print_settings_stamp_signature_scale
Revises: 20260718_000002_business_fx_auto_sync
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260720_000001_business_print_settings_stamp_signature_scale"
down_revision = "20260718_000002_business_fx_auto_sync"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.add_column(
		"business_print_settings",
		sa.Column(
			"stamp_scale_percent",
			sa.Integer(),
			nullable=False,
			server_default=sa.text("100"),
		),
	)
	op.add_column(
		"business_print_settings",
		sa.Column(
			"signature_scale_percent",
			sa.Integer(),
			nullable=False,
			server_default=sa.text("100"),
		),
	)


def downgrade() -> None:
	op.drop_column("business_print_settings", "signature_scale_percent")
	op.drop_column("business_print_settings", "stamp_scale_percent")
