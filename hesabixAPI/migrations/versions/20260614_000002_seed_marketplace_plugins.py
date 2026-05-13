"""seed افزونه‌های پیش‌فرض بازار (باسلام، تعمیرگاه، گارانتی، پخش، باشگاه مشتریان)

Revision ID: 20260614_000002_seed_marketplace_plugins
Revises: 20260614_000001_business_invoice_missing_line_warehouse_policy
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.orm import sessionmaker

from adapters.db.seed_data.marketplace_plugins_seed import ensure_default_marketplace_plugins

revision = "20260614_000002_seed_marketplace_plugins"
down_revision = "20260614_000001_business_invoice_missing_line_warehouse_policy"
branch_labels = None
depends_on = None


def upgrade() -> None:
	conn = op.get_bind()
	insp = sa.inspect(conn)
	if "marketplace_plugins" not in insp.get_table_names():
		return

	Session = sessionmaker(bind=conn)
	db = Session()
	try:
		result = ensure_default_marketplace_plugins(db)
		if result.get("ok"):
			db.commit()
		else:
			db.rollback()
			raise RuntimeError(result.get("message") or "marketplace_plugins seed failed")
	except Exception:
		db.rollback()
		raise
	finally:
		db.close()


def downgrade() -> None:
	# حذف خودکار رکوردهای مارکت‌پلیس خطرناک است (سفارش/لایسنس).
	pass
