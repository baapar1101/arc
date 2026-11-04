"""افزونه تولید پیشرفته: تنظیمات و ثبت بازار.

Revision ID: 20261104_000004_advanced_production_plugin
Revises: 20261104_000003_ai_mcp_server_plugin
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.orm import sessionmaker

from adapters.db.seed_data.marketplace_plugins_seed import ensure_default_marketplace_plugins

revision = "20261104_000004_advanced_production_plugin"
down_revision = "20261104_000003_ai_mcp_server_plugin"
branch_labels = None
depends_on = None


def upgrade() -> None:
	conn = op.get_bind()
	insp = sa.inspect(conn)
	tables = set(insp.get_table_names())
	if "advanced_production_settings" not in tables:
		op.create_table(
			"advanced_production_settings",
			sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
			sa.Column("business_id", sa.Integer(), sa.ForeignKey("businesses.id", ondelete="CASCADE"), nullable=False),
			sa.Column("costing_method", sa.String(length=32), nullable=False, server_default="actual"),
			sa.Column("overhead_mode", sa.String(length=32), nullable=False, server_default="bom_operations"),
			sa.Column("wip_account_id", sa.Integer(), sa.ForeignKey("accounts.id", ondelete="SET NULL"), nullable=True),
			sa.Column("finished_goods_account_id", sa.Integer(), sa.ForeignKey("accounts.id", ondelete="SET NULL"), nullable=True),
			sa.Column("scrap_expense_account_id", sa.Integer(), sa.ForeignKey("accounts.id", ondelete="SET NULL"), nullable=True),
			sa.Column("cost_variance_account_id", sa.Integer(), sa.ForeignKey("accounts.id", ondelete="SET NULL"), nullable=True),
			sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
			sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
			sa.UniqueConstraint("business_id", name="uq_advanced_production_settings_business"),
		)
		op.create_index(
			"ix_advanced_production_settings_business_id",
			"advanced_production_settings",
			["business_id"],
		)
	else:
		columns = {col["name"] for col in insp.get_columns("advanced_production_settings")}
		if "cost_variance_account_id" not in columns:
			op.add_column(
				"advanced_production_settings",
				sa.Column("cost_variance_account_id", sa.Integer(), sa.ForeignKey("accounts.id", ondelete="SET NULL"), nullable=True),
			)
	if "marketplace_plugins" not in tables:
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
	conn = op.get_bind()
	insp = sa.inspect(conn)
	if "advanced_production_settings" in insp.get_table_names():
		op.drop_index("ix_advanced_production_settings_business_id", table_name="advanced_production_settings")
		op.drop_table("advanced_production_settings")
