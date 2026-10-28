"""فاز ۲ اموال: خروج، مخارج بعدی، تغییر برآورد، راکد مالیاتی.

Revision ID: 20261028_000005_fixed_assets_phase2
Revises: 20261028_000004_fixed_assets_plugin
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20261028_000005_fixed_assets_phase2"
down_revision = "20261028_000004_fixed_assets_plugin"
branch_labels = None
depends_on = None

_COA_LEAVES = (
	("60206", "سود واگذاری دارایی ثابت", "602"),
	("70804", "زیان واگذاری دارایی ثابت", "708"),
	("70404", "تعمیر و نگهداری", "704"),
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
				f"میگریشن اموال فاز ۲: حساب والد با کد {code} در accounts یافت نشد."
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

	op.add_column("fa_settings", sa.Column("vat_output_account_id", sa.Integer(), nullable=True))
	op.add_column("fa_settings", sa.Column("disposal_gain_account_id", sa.Integer(), nullable=True))
	op.add_column("fa_settings", sa.Column("disposal_loss_account_id", sa.Integer(), nullable=True))
	op.add_column("fa_settings", sa.Column("repair_expense_account_id", sa.Integer(), nullable=True))
	op.create_foreign_key(
		"fk_fa_settings_vat_output_account_id",
		"fa_settings",
		"accounts",
		["vat_output_account_id"],
		["id"],
		ondelete="SET NULL",
	)
	op.create_foreign_key(
		"fk_fa_settings_disposal_gain_account_id",
		"fa_settings",
		"accounts",
		["disposal_gain_account_id"],
		["id"],
		ondelete="SET NULL",
	)
	op.create_foreign_key(
		"fk_fa_settings_disposal_loss_account_id",
		"fa_settings",
		"accounts",
		["disposal_loss_account_id"],
		["id"],
		ondelete="SET NULL",
	)
	op.create_foreign_key(
		"fk_fa_settings_repair_expense_account_id",
		"fa_settings",
		"accounts",
		["repair_expense_account_id"],
		["id"],
		ondelete="SET NULL",
	)

	op.add_column("fa_assets", sa.Column("idle_from", sa.Date(), nullable=True))
	op.add_column("fa_assets", sa.Column("disposed_at", sa.Date(), nullable=True))
	op.add_column("fa_assets", sa.Column("disposal_kind", sa.String(length=32), nullable=True))
	op.add_column(
		"fa_assets",
		sa.Column("disposal_proceeds", sa.Numeric(18, 2), nullable=False, server_default=sa.text("0")),
	)
	op.add_column("fa_assets", sa.Column("disposal_document_id", sa.Integer(), nullable=True))
	op.add_column("fa_assets", sa.Column("sl_monthly_override", sa.Numeric(18, 8), nullable=True))
	op.add_column("fa_assets", sa.Column("estimate_effective_date", sa.Date(), nullable=True))
	op.create_foreign_key(
		"fk_fa_assets_disposal_document_id",
		"fa_assets",
		"documents",
		["disposal_document_id"],
		["id"],
		ondelete="SET NULL",
	)

	op.add_column(
		"fa_depreciation_run_lines",
		sa.Column("tax_preview_amount", sa.Numeric(18, 2), nullable=False, server_default=sa.text("0")),
	)

	op.create_table(
		"fa_subsequent_expenditures",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("asset_id", sa.Integer(), nullable=False),
		sa.Column("kind", sa.String(length=32), nullable=False),
		sa.Column("amount", sa.Numeric(18, 2), nullable=False),
		sa.Column("vat_amount", sa.Numeric(18, 2), nullable=False, server_default=sa.text("0")),
		sa.Column("expenditure_date", sa.Date(), nullable=False),
		sa.Column("document_id", sa.Integer(), nullable=False),
		sa.Column("description", sa.Text(), nullable=True),
		sa.Column("created_by_user_id", sa.Integer(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["asset_id"], ["fa_assets.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["document_id"], ["documents.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_fa_subsequent_expenditures_business_id", "fa_subsequent_expenditures", ["business_id"])
	op.create_index("ix_fa_subsequent_asset_id", "fa_subsequent_expenditures", ["asset_id"])

	op.create_table(
		"fa_estimate_changes",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("asset_id", sa.Integer(), nullable=False),
		sa.Column("effective_date", sa.Date(), nullable=False),
		sa.Column("old_method", sa.String(length=32), nullable=False),
		sa.Column("new_method", sa.String(length=32), nullable=False),
		sa.Column("old_useful_life_months", sa.Integer(), nullable=True),
		sa.Column("remaining_useful_life_months", sa.Integer(), nullable=True),
		sa.Column("old_declining_rate", sa.Numeric(8, 6), nullable=True),
		sa.Column("new_declining_rate", sa.Numeric(8, 6), nullable=True),
		sa.Column("old_salvage", sa.Numeric(18, 2), nullable=False),
		sa.Column("new_salvage", sa.Numeric(18, 2), nullable=False),
		sa.Column("sl_monthly_override", sa.Numeric(18, 8), nullable=True),
		sa.Column("remaining_depreciable", sa.Numeric(18, 2), nullable=False),
		sa.Column("created_by_user_id", sa.Integer(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["asset_id"], ["fa_assets.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_fa_estimate_changes_business_id", "fa_estimate_changes", ["business_id"])
	op.create_index("ix_fa_estimate_changes_asset_id", "fa_estimate_changes", ["asset_id"])


def downgrade() -> None:
	op.drop_index("ix_fa_estimate_changes_asset_id", table_name="fa_estimate_changes")
	op.drop_index("ix_fa_estimate_changes_business_id", table_name="fa_estimate_changes")
	op.drop_table("fa_estimate_changes")
	op.drop_index("ix_fa_subsequent_asset_id", table_name="fa_subsequent_expenditures")
	op.drop_index("ix_fa_subsequent_expenditures_business_id", table_name="fa_subsequent_expenditures")
	op.drop_table("fa_subsequent_expenditures")
	op.drop_column("fa_depreciation_run_lines", "tax_preview_amount")
	op.drop_constraint("fk_fa_assets_disposal_document_id", "fa_assets", type_="foreignkey")
	op.drop_column("fa_assets", "estimate_effective_date")
	op.drop_column("fa_assets", "sl_monthly_override")
	op.drop_column("fa_assets", "disposal_document_id")
	op.drop_column("fa_assets", "disposal_proceeds")
	op.drop_column("fa_assets", "disposal_kind")
	op.drop_column("fa_assets", "disposed_at")
	op.drop_column("fa_assets", "idle_from")
	op.drop_constraint("fk_fa_settings_repair_expense_account_id", "fa_settings", type_="foreignkey")
	op.drop_constraint("fk_fa_settings_disposal_loss_account_id", "fa_settings", type_="foreignkey")
	op.drop_constraint("fk_fa_settings_disposal_gain_account_id", "fa_settings", type_="foreignkey")
	op.drop_constraint("fk_fa_settings_vat_output_account_id", "fa_settings", type_="foreignkey")
	op.drop_column("fa_settings", "repair_expense_account_id")
	op.drop_column("fa_settings", "disposal_loss_account_id")
	op.drop_column("fa_settings", "disposal_gain_account_id")
	op.drop_column("fa_settings", "vat_output_account_id")
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
