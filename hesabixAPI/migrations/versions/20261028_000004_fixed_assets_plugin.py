"""افزونه کنترل اموال و دارایی ثابت: جداول + برگ‌های دفتر کل در صورت وجود والد.

Revision ID: 20261028_000004_fixed_assets_plugin
Revises: 20261028_000003_distribution_org_territory
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261028_000004_fixed_assets_plugin"
down_revision = "20261028_000003_distribution_org_territory"
branch_labels = None
depends_on = None

_COA_LEAVES = (
	("10701", "زمین", "107"),
	("10702", "ساختمان", "107"),
	("10703", "وسایل نقلیه", "107"),
	("10704", "اثاثیه", "107"),
	("10802", "استهلاک انباشته ساختمان", "108"),
	("10803", "استهلاک انباشته وسایل نقلیه", "108"),
	("10804", "استهلاک انباشته اثاثیه", "108"),
	("70409", "هزینه استهلاک ساختمان", "704"),
	("70410", "هزینه استهلاک وسایل نقلیه", "704"),
	("70411", "هزینه استهلاک اثاثیه", "704"),
)


def _seed_coa_leaves() -> None:
	conn = op.get_bind()

	def _parent(code: str) -> tuple:
		row = conn.execute(
			sa.text(
				"SELECT id, account_type FROM accounts WHERE business_id IS NULL AND code = :pc LIMIT 1"
			),
			{"pc": code},
		).first()
		if row is None:
			raise RuntimeError(
				f"میگریشن اموال: حساب والد با کد {code} در accounts یافت نشد."
			)
		return int(row[0]), str(row[1])

	parents = {code: _parent(code) for _, _, code in _COA_LEAVES}
	for code, name, parent_code in _COA_LEAVES:
		pid, atype = parents[parent_code]
		conn.execute(
			sa.text(
				"""
				INSERT INTO accounts (name, business_id, account_type, code, parent_id, created_at, updated_at)
				SELECT :name, NULL, :atype, :code, :pid, NOW(), NOW()
				WHERE NOT EXISTS (
					SELECT 1 FROM accounts WHERE business_id IS NULL AND code = :code
				)
				"""
			),
			{"name": name, "atype": atype, "code": code, "pid": pid},
		)


def upgrade() -> None:
	_seed_coa_leaves()

	op.create_table(
		"fa_settings",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("default_currency_id", sa.Integer(), nullable=True),
		sa.Column("vat_account_id", sa.Integer(), nullable=True),
		sa.Column("opening_equity_account_id", sa.Integer(), nullable=True),
		sa.Column("accounting_convention", sa.String(length=32), nullable=False, server_default=sa.text("'from_ready_date'")),
		sa.Column("require_custodian", sa.Boolean(), nullable=False, server_default=sa.text("false")),
		sa.Column("plaque_prefix", sa.String(length=16), nullable=False, server_default=sa.text("'FA'")),
		sa.Column("extra_settings", sa.JSON(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["default_currency_id"], ["currencies.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["vat_account_id"], ["accounts.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["opening_equity_account_id"], ["accounts.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", name="uq_fa_settings_business"),
	)
	op.create_index("ix_fa_settings_business_id", "fa_settings", ["business_id"], unique=False)

	op.create_table(
		"fa_classes",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("code", sa.String(length=64), nullable=False),
		sa.Column("name", sa.String(length=200), nullable=False),
		sa.Column("cost_account_id", sa.Integer(), nullable=True),
		sa.Column("accum_dep_account_id", sa.Integer(), nullable=True),
		sa.Column("dep_expense_account_id", sa.Integer(), nullable=True),
		sa.Column("cost_account_code", sa.String(length=50), nullable=True),
		sa.Column("accum_dep_account_code", sa.String(length=50), nullable=True),
		sa.Column("dep_expense_account_code", sa.String(length=50), nullable=True),
		sa.Column("depreciable", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("default_method", sa.String(length=32), nullable=False, server_default=sa.text("'straight_line'")),
		sa.Column("default_useful_life_months", sa.Integer(), nullable=True),
		sa.Column("default_declining_rate", sa.Numeric(8, 6), nullable=True),
		sa.Column("tax_table_key", sa.String(length=64), nullable=True),
		sa.Column("is_system", sa.Boolean(), nullable=False, server_default=sa.text("false")),
		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("sort_order", sa.Integer(), nullable=False, server_default=sa.text("0")),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["cost_account_id"], ["accounts.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["accum_dep_account_id"], ["accounts.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["dep_expense_account_id"], ["accounts.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "code", name="uq_fa_classes_biz_code"),
	)
	op.create_index("ix_fa_classes_business_id", "fa_classes", ["business_id"], unique=False)

	op.create_table(
		"fa_locations",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("parent_id", sa.Integer(), nullable=True),
		sa.Column("code", sa.String(length=64), nullable=False),
		sa.Column("name", sa.String(length=200), nullable=False),
		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["parent_id"], ["fa_locations.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "code", name="uq_fa_locations_biz_code"),
	)
	op.create_index("ix_fa_locations_business_id", "fa_locations", ["business_id"], unique=False)

	op.create_table(
		"fa_assets",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("class_id", sa.Integer(), nullable=False),
		sa.Column("code", sa.String(length=64), nullable=False),
		sa.Column("name", sa.String(length=255), nullable=False),
		sa.Column("description", sa.Text(), nullable=True),
		sa.Column("serial_number", sa.String(length=128), nullable=True),
		sa.Column("status", sa.String(length=32), nullable=False, server_default=sa.text("'draft'")),
		sa.Column("acquisition_kind", sa.String(length=32), nullable=False, server_default=sa.text("'purchase'")),
		sa.Column("acquisition_date", sa.Date(), nullable=False),
		sa.Column("commission_date", sa.Date(), nullable=False),
		sa.Column("cost", sa.Numeric(18, 2), nullable=False),
		sa.Column("salvage", sa.Numeric(18, 2), nullable=False, server_default=sa.text("0")),
		sa.Column("vat_amount", sa.Numeric(18, 2), nullable=False, server_default=sa.text("0")),
		sa.Column("accum_depreciation", sa.Numeric(18, 2), nullable=False, server_default=sa.text("0")),
		sa.Column("opening_accum_depreciation", sa.Numeric(18, 2), nullable=False, server_default=sa.text("0")),
		sa.Column("method", sa.String(length=32), nullable=False, server_default=sa.text("'straight_line'")),
		sa.Column("useful_life_months", sa.Integer(), nullable=True),
		sa.Column("declining_annual_rate", sa.Numeric(8, 6), nullable=True),
		sa.Column("location_id", sa.Integer(), nullable=True),
		sa.Column("custodian_person_id", sa.Integer(), nullable=True),
		sa.Column("project_id", sa.Integer(), nullable=True),
		sa.Column("acquisition_document_id", sa.Integer(), nullable=True),
		sa.Column("extra_info", sa.JSON(), nullable=True),
		sa.Column("created_by_user_id", sa.Integer(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["class_id"], ["fa_classes.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["location_id"], ["fa_locations.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["custodian_person_id"], ["persons.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["project_id"], ["projects.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["acquisition_document_id"], ["documents.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "code", name="uq_fa_assets_biz_code"),
	)
	op.create_index("ix_fa_assets_business_id", "fa_assets", ["business_id"], unique=False)
	op.create_index("ix_fa_assets_class_id", "fa_assets", ["class_id"], unique=False)
	op.create_index("ix_fa_assets_status", "fa_assets", ["status"], unique=False)

	op.create_table(
		"fa_depreciation_runs",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("period_year", sa.Integer(), nullable=False),
		sa.Column("period_month", sa.Integer(), nullable=False),
		sa.Column("period_start", sa.Date(), nullable=False),
		sa.Column("period_end", sa.Date(), nullable=False),
		sa.Column("status", sa.String(length=32), nullable=False, server_default=sa.text("'draft'")),
		sa.Column("convention", sa.String(length=32), nullable=False),
		sa.Column("total_amount", sa.Numeric(18, 2), nullable=False, server_default=sa.text("0")),
		sa.Column("document_id", sa.Integer(), nullable=True),
		sa.Column("created_by_user_id", sa.Integer(), nullable=True),
		sa.Column("posted_by_user_id", sa.Integer(), nullable=True),
		sa.Column("posted_at", sa.DateTime(), nullable=True),
		sa.Column("description", sa.Text(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["document_id"], ["documents.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["posted_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_fa_depreciation_runs_business_id", "fa_depreciation_runs", ["business_id"], unique=False)
	op.create_index(
		"uq_fa_depreciation_runs_open_period",
		"fa_depreciation_runs",
		["business_id", "period_year", "period_month"],
		unique=True,
		postgresql_where=sa.text("status IN ('draft', 'posted')"),
	)

	op.create_table(
		"fa_depreciation_run_lines",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("run_id", sa.Integer(), nullable=False),
		sa.Column("asset_id", sa.Integer(), nullable=False),
		sa.Column("amount", sa.Numeric(18, 2), nullable=False),
		sa.Column("book_value_before", sa.Numeric(18, 2), nullable=False),
		sa.Column("book_value_after", sa.Numeric(18, 2), nullable=False),
		sa.Column("method", sa.String(length=32), nullable=False),
		sa.Column("expense_account_id", sa.Integer(), nullable=False),
		sa.Column("accum_account_id", sa.Integer(), nullable=False),
		sa.ForeignKeyConstraint(["run_id"], ["fa_depreciation_runs.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["asset_id"], ["fa_assets.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["expense_account_id"], ["accounts.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["accum_account_id"], ["accounts.id"], ondelete="RESTRICT"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("run_id", "asset_id", name="uq_fa_depr_run_line_asset"),
	)
	op.create_index("ix_fa_depreciation_run_lines_asset_id", "fa_depreciation_run_lines", ["asset_id"], unique=False)

	op.create_table(
		"fa_document_links",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("asset_id", sa.Integer(), nullable=True),
		sa.Column("run_id", sa.Integer(), nullable=True),
		sa.Column("document_id", sa.Integer(), nullable=False),
		sa.Column("link_type", sa.String(length=32), nullable=False),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["asset_id"], ["fa_assets.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["run_id"], ["fa_depreciation_runs.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["document_id"], ["documents.id"], ondelete="RESTRICT"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("document_id", name="uq_fa_document_links_document"),
	)
	op.create_index("ix_fa_document_links_business_id", "fa_document_links", ["business_id"], unique=False)
	op.create_index("ix_fa_document_links_asset_id", "fa_document_links", ["asset_id"], unique=False)
	op.create_index("ix_fa_document_links_run_id", "fa_document_links", ["run_id"], unique=False)


def downgrade() -> None:
	op.drop_table("fa_document_links")
	op.drop_table("fa_depreciation_run_lines")
	op.drop_index("uq_fa_depreciation_runs_open_period", table_name="fa_depreciation_runs")
	op.drop_table("fa_depreciation_runs")
	op.drop_table("fa_assets")
	op.drop_table("fa_locations")
	op.drop_table("fa_classes")
	op.drop_table("fa_settings")
	conn = op.get_bind()
	for code, _, _ in reversed(_COA_LEAVES):
		conn.execute(
			sa.text(
				"""
				DELETE FROM accounts
				WHERE business_id IS NULL AND code = :code
				  AND NOT EXISTS (
					SELECT 1 FROM document_lines WHERE account_id = accounts.id
				  )
				"""
			),
			{"code": code},
		)
