"""Seed افزونه سرور MCP هوش مصنوعی در بازار.

Revision ID: 20261104_000003_ai_mcp_server_plugin
Revises: 20261104_000002_advanced_accounting_plugin
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.orm import sessionmaker

from adapters.db.seed_data.marketplace_plugins_seed import ensure_default_marketplace_plugins

revision = "20261104_000003_ai_mcp_server_plugin"
down_revision = "20261104_000002_advanced_accounting_plugin"
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
	# حذف خودکار ردیف بازار خطرناک است (سفارش/لایسنس).
	pass
