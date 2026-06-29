"""Payroll plugin tables

Revision ID: 20260707_000001_payroll_plugin_tables
Revises: 20260706_000001_support_read_csat
Create Date: 2026-07-07
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260707_000001_payroll_plugin_tables"
down_revision = "20260706_000001_support_read_csat"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"payroll_settings",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("document_code_format", sa.String(length=20), nullable=False, server_default=sa.text("'sequential'")),
		sa.Column("document_code_prefix", sa.String(length=16), nullable=False, server_default=sa.text("'PAY'")),
		sa.Column("wages_payable_account_id", sa.Integer(), nullable=True),
		sa.Column("payroll_expense_account_id", sa.Integer(), nullable=True),
		sa.Column("tax_payable_account_id", sa.Integer(), nullable=True),
		sa.Column("insurance_payable_account_id", sa.Integer(), nullable=True),
		sa.Column("default_currency_id", sa.Integer(), nullable=True),
		sa.Column("calculation_mode", sa.String(length=32), nullable=False, server_default=sa.text("'manual'")),
		sa.Column("require_approval", sa.Boolean(), nullable=False, server_default=sa.text("false")),
		sa.Column("auto_post_on_finalize", sa.Boolean(), nullable=False, server_default=sa.text("false")),
		sa.Column("allow_negative_net", sa.Boolean(), nullable=False, server_default=sa.text("false")),
		sa.Column("round_amounts_to", sa.SmallInteger(), nullable=False, server_default=sa.text("0")),
		sa.Column("payslip_template_json", sa.JSON(), nullable=True),
		sa.Column("extra_settings", sa.JSON(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["wages_payable_account_id"], ["accounts.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["payroll_expense_account_id"], ["accounts.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["tax_payable_account_id"], ["accounts.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["insurance_payable_account_id"], ["accounts.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["default_currency_id"], ["currencies.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", name="uq_payroll_settings_business"),
		mysql_charset="utf8mb4",
	)
	op.create_index(op.f("ix_payroll_settings_business_id"), "payroll_settings", ["business_id"], unique=False)

	op.create_table(
		"payroll_item_categories",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("code", sa.String(length=64), nullable=False),
		sa.Column("name", sa.String(length=200), nullable=False),
		sa.Column("item_kind", sa.String(length=32), nullable=False, server_default=sa.text("'earning'")),
		sa.Column("sort_order", sa.Integer(), nullable=False, server_default=sa.text("0")),
		sa.Column("is_system", sa.Boolean(), nullable=False, server_default=sa.text("false")),
		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("description", sa.Text(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "code", name="uq_payroll_item_categories_biz_code"),
		mysql_charset="utf8mb4",
	)
	op.create_index("ix_payroll_item_categories_business_id", "payroll_item_categories", ["business_id"], unique=False)

	op.create_table(
		"payroll_item_definitions",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("category_id", sa.Integer(), nullable=True),
		sa.Column("code", sa.String(length=64), nullable=False),
		sa.Column("name", sa.String(length=200), nullable=False),
		sa.Column("item_kind", sa.String(length=32), nullable=False),
		sa.Column("account_id", sa.Integer(), nullable=True),
		sa.Column("counter_account_id", sa.Integer(), nullable=True),
		sa.Column("calculation_type", sa.String(length=32), nullable=False, server_default=sa.text("'manual'")),
		sa.Column("default_amount", sa.Numeric(18, 4), nullable=True),
		sa.Column("percent_value", sa.Numeric(18, 8), nullable=True),
		sa.Column("formula_expression", sa.Text(), nullable=True),
		sa.Column("affects_gross", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("affects_taxable", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("affects_insurance", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("is_taxable", sa.Boolean(), nullable=False, server_default=sa.text("false")),
		sa.Column("is_insurable", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("show_on_payslip", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("sort_order", sa.Integer(), nullable=False, server_default=sa.text("0")),
		sa.Column("is_system", sa.Boolean(), nullable=False, server_default=sa.text("false")),
		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("extra_config", sa.JSON(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["account_id"], ["accounts.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["category_id"], ["payroll_item_categories.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["counter_account_id"], ["accounts.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "code", name="uq_payroll_item_definitions_biz_code"),
		mysql_charset="utf8mb4",
	)
	op.create_index("ix_payroll_item_definitions_business_id", "payroll_item_definitions", ["business_id"], unique=False)
	op.create_index("ix_payroll_item_definitions_category_id", "payroll_item_definitions", ["category_id"], unique=False)

	op.create_table(
		"payroll_departments",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("parent_id", sa.Integer(), nullable=True),
		sa.Column("code", sa.String(length=64), nullable=False),
		sa.Column("name", sa.String(length=200), nullable=False),
		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("sort_order", sa.Integer(), nullable=False, server_default=sa.text("0")),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["parent_id"], ["payroll_departments.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "code", name="uq_payroll_departments_biz_code"),
		mysql_charset="utf8mb4",
	)
	op.create_index("ix_payroll_departments_business_id", "payroll_departments", ["business_id"], unique=False)

	op.create_table(
		"payroll_employees",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("person_id", sa.Integer(), nullable=False),
		sa.Column("department_id", sa.Integer(), nullable=True),
		sa.Column("employee_code", sa.String(length=64), nullable=False),
		sa.Column("job_title", sa.String(length=200), nullable=True),
		sa.Column("employment_type", sa.String(length=32), nullable=False, server_default=sa.text("'full_time'")),
		sa.Column("hire_date", sa.Date(), nullable=True),
		sa.Column("termination_date", sa.Date(), nullable=True),
		sa.Column("base_salary", sa.Numeric(18, 4), nullable=True),
		sa.Column("insurance_number", sa.String(length=64), nullable=True),
		sa.Column("tax_id", sa.String(length=64), nullable=True),
		sa.Column("bank_account_info", sa.JSON(), nullable=True),
		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("extra_info", sa.JSON(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["department_id"], ["payroll_departments.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["person_id"], ["persons.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "employee_code", name="uq_payroll_employees_biz_code"),
		sa.UniqueConstraint("business_id", "person_id", name="uq_payroll_employees_biz_person"),
		mysql_charset="utf8mb4",
	)
	op.create_index("ix_payroll_employees_business_id", "payroll_employees", ["business_id"], unique=False)
	op.create_index("ix_payroll_employees_department_id", "payroll_employees", ["department_id"], unique=False)
	op.create_index("ix_payroll_employees_person_id", "payroll_employees", ["person_id"], unique=False)

	op.create_table(
		"payroll_periods",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("year", sa.SmallInteger(), nullable=False),
		sa.Column("month", sa.SmallInteger(), nullable=False),
		sa.Column("title", sa.String(length=120), nullable=False),
		sa.Column("start_date", sa.Date(), nullable=True),
		sa.Column("end_date", sa.Date(), nullable=True),
		sa.Column("status", sa.String(length=16), nullable=False, server_default=sa.text("'open'")),
		sa.Column("closed_at", sa.DateTime(), nullable=True),
		sa.Column("closed_by_user_id", sa.Integer(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["closed_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "year", "month", name="uq_payroll_periods_biz_year_month"),
		mysql_charset="utf8mb4",
	)
	op.create_index("ix_payroll_periods_business_id", "payroll_periods", ["business_id"], unique=False)

	op.create_table(
		"payroll_runs",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("period_id", sa.Integer(), nullable=True),
		sa.Column("code", sa.String(length=64), nullable=False),
		sa.Column("title", sa.String(length=200), nullable=False),
		sa.Column("run_date", sa.Date(), nullable=False),
		sa.Column("description", sa.Text(), nullable=True),
		sa.Column("status", sa.String(length=32), nullable=False, server_default=sa.text("'draft'")),
		sa.Column("gross_total", sa.Numeric(18, 4), nullable=False, server_default=sa.text("0")),
		sa.Column("deduction_total", sa.Numeric(18, 4), nullable=False, server_default=sa.text("0")),
		sa.Column("net_total", sa.Numeric(18, 4), nullable=False, server_default=sa.text("0")),
		sa.Column("employer_cost_total", sa.Numeric(18, 4), nullable=False, server_default=sa.text("0")),
		sa.Column("created_by_user_id", sa.Integer(), nullable=True),
		sa.Column("approved_by_user_id", sa.Integer(), nullable=True),
		sa.Column("finalized_by_user_id", sa.Integer(), nullable=True),
		sa.Column("posted_by_user_id", sa.Integer(), nullable=True),
		sa.Column("approved_at", sa.DateTime(), nullable=True),
		sa.Column("finalized_at", sa.DateTime(), nullable=True),
		sa.Column("posted_at", sa.DateTime(), nullable=True),
		sa.Column("cancelled_at", sa.DateTime(), nullable=True),
		sa.Column("extra_info", sa.JSON(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["approved_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["finalized_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["period_id"], ["payroll_periods.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["posted_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "code", name="uq_payroll_runs_biz_code"),
		mysql_charset="utf8mb4",
	)
	op.create_index("ix_payroll_runs_business_id", "payroll_runs", ["business_id"], unique=False)
	op.create_index("ix_payroll_runs_period_id", "payroll_runs", ["period_id"], unique=False)
	op.create_index("ix_payroll_runs_status", "payroll_runs", ["status"], unique=False)

	op.create_table(
		"payroll_run_lines",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("run_id", sa.Integer(), nullable=False),
		sa.Column("employee_id", sa.Integer(), nullable=False),
		sa.Column("person_id", sa.Integer(), nullable=False),
		sa.Column("line_number", sa.Integer(), nullable=False, server_default=sa.text("1")),
		sa.Column("notes", sa.Text(), nullable=True),
		sa.Column("gross_amount", sa.Numeric(18, 4), nullable=False, server_default=sa.text("0")),
		sa.Column("deduction_amount", sa.Numeric(18, 4), nullable=False, server_default=sa.text("0")),
		sa.Column("net_amount", sa.Numeric(18, 4), nullable=False, server_default=sa.text("0")),
		sa.Column("employer_cost_amount", sa.Numeric(18, 4), nullable=False, server_default=sa.text("0")),
		sa.ForeignKeyConstraint(["employee_id"], ["payroll_employees.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["person_id"], ["persons.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["run_id"], ["payroll_runs.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("run_id", "employee_id", name="uq_payroll_run_lines_run_employee"),
		mysql_charset="utf8mb4",
	)
	op.create_index("ix_payroll_run_lines_employee_id", "payroll_run_lines", ["employee_id"], unique=False)
	op.create_index("ix_payroll_run_lines_person_id", "payroll_run_lines", ["person_id"], unique=False)
	op.create_index("ix_payroll_run_lines_run_id", "payroll_run_lines", ["run_id"], unique=False)

	op.create_table(
		"payroll_run_line_items",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("run_line_id", sa.Integer(), nullable=False),
		sa.Column("item_definition_id", sa.Integer(), nullable=False),
		sa.Column("amount", sa.Numeric(18, 4), nullable=False, server_default=sa.text("0")),
		sa.Column("quantity", sa.Numeric(18, 6), nullable=True),
		sa.Column("is_computed", sa.Boolean(), nullable=False, server_default=sa.text("false")),
		sa.Column("notes", sa.Text(), nullable=True),
		sa.ForeignKeyConstraint(["item_definition_id"], ["payroll_item_definitions.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["run_line_id"], ["payroll_run_lines.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("run_line_id", "item_definition_id", name="uq_payroll_run_line_items_line_item"),
		mysql_charset="utf8mb4",
	)
	op.create_index("ix_payroll_run_line_items_item_definition_id", "payroll_run_line_items", ["item_definition_id"], unique=False)
	op.create_index("ix_payroll_run_line_items_run_line_id", "payroll_run_line_items", ["run_line_id"], unique=False)

	op.create_table(
		"payroll_document_links",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("run_id", sa.Integer(), nullable=False),
		sa.Column("document_id", sa.Integer(), nullable=False),
		sa.Column("link_type", sa.String(length=32), nullable=False),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["document_id"], ["documents.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["run_id"], ["payroll_runs.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		mysql_charset="utf8mb4",
	)
	op.create_index("ix_payroll_document_links_document_id", "payroll_document_links", ["document_id"], unique=False)
	op.create_index("ix_payroll_document_links_run_id", "payroll_document_links", ["run_id"], unique=False)

	op.create_table(
		"payroll_audit_logs",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("entity_type", sa.String(length=64), nullable=False),
		sa.Column("entity_id", sa.Integer(), nullable=False),
		sa.Column("action", sa.String(length=64), nullable=False),
		sa.Column("user_id", sa.Integer(), nullable=True),
		sa.Column("old_values", sa.JSON(), nullable=True),
		sa.Column("new_values", sa.JSON(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		mysql_charset="utf8mb4",
	)
	op.create_index(
		"ix_payroll_audit_logs_business_entity",
		"payroll_audit_logs",
		["business_id", "entity_type", "entity_id"],
		unique=False,
	)


def downgrade() -> None:
	op.drop_index("ix_payroll_audit_logs_business_entity", table_name="payroll_audit_logs")
	op.drop_table("payroll_audit_logs")

	op.drop_index("ix_payroll_document_links_run_id", table_name="payroll_document_links")
	op.drop_index("ix_payroll_document_links_document_id", table_name="payroll_document_links")
	op.drop_table("payroll_document_links")

	op.drop_index("ix_payroll_run_line_items_run_line_id", table_name="payroll_run_line_items")
	op.drop_index("ix_payroll_run_line_items_item_definition_id", table_name="payroll_run_line_items")
	op.drop_table("payroll_run_line_items")

	op.drop_index("ix_payroll_run_lines_run_id", table_name="payroll_run_lines")
	op.drop_index("ix_payroll_run_lines_person_id", table_name="payroll_run_lines")
	op.drop_index("ix_payroll_run_lines_employee_id", table_name="payroll_run_lines")
	op.drop_table("payroll_run_lines")

	op.drop_index("ix_payroll_runs_status", table_name="payroll_runs")
	op.drop_index("ix_payroll_runs_period_id", table_name="payroll_runs")
	op.drop_index("ix_payroll_runs_business_id", table_name="payroll_runs")
	op.drop_table("payroll_runs")

	op.drop_index("ix_payroll_periods_business_id", table_name="payroll_periods")
	op.drop_table("payroll_periods")

	op.drop_index("ix_payroll_employees_person_id", table_name="payroll_employees")
	op.drop_index("ix_payroll_employees_department_id", table_name="payroll_employees")
	op.drop_index("ix_payroll_employees_business_id", table_name="payroll_employees")
	op.drop_table("payroll_employees")

	op.drop_index("ix_payroll_departments_business_id", table_name="payroll_departments")
	op.drop_table("payroll_departments")

	op.drop_index("ix_payroll_item_definitions_category_id", table_name="payroll_item_definitions")
	op.drop_index("ix_payroll_item_definitions_business_id", table_name="payroll_item_definitions")
	op.drop_table("payroll_item_definitions")

	op.drop_index("ix_payroll_item_categories_business_id", table_name="payroll_item_categories")
	op.drop_table("payroll_item_categories")

	op.drop_index(op.f("ix_payroll_settings_business_id"), table_name="payroll_settings")
	op.drop_table("payroll_settings")
