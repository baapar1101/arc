"""جداول اشتراک و صورتحساب پشتیبانی کاربر

Revision ID: 20260721_000001_support_billing
Revises: 20260720_000003_hscript_custom_reports
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260721_000001_support_billing"
down_revision = "20260720_000003_hscript_custom_reports"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"support_plans",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("name", sa.String(length=200), nullable=False),
		sa.Column("code", sa.String(length=100), nullable=False),
		sa.Column("period_months", sa.Integer(), nullable=False),
		sa.Column("price", sa.Numeric(precision=18, scale=2), nullable=False, server_default="0"),
		sa.Column("currency_id", sa.Integer(), nullable=False),
		sa.Column("is_free", sa.Boolean(), nullable=False, server_default=sa.text("false")),
		sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("description", sa.Text(), nullable=True),
		sa.Column("features_json", sa.JSON(), nullable=True),
		sa.Column("max_open_tickets", sa.Integer(), nullable=True),
		sa.Column("sla_policy_id", sa.Integer(), nullable=True),
		sa.Column("priority_weight", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("includes_priority_support", sa.Boolean(), nullable=False, server_default=sa.text("false")),
		sa.Column("trial_days", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["currency_id"], ["currencies.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["sla_policy_id"], ["support_sla_policies.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("code", name="uq_support_plans_code"),
	)
	op.create_index("ix_support_plans_code", "support_plans", ["code"])
	op.create_index("ix_support_plans_sla_policy_id", "support_plans", ["sla_policy_id"])

	op.create_table(
		"support_invoices",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("user_id", sa.Integer(), nullable=False),
		sa.Column("plan_id", sa.Integer(), nullable=False),
		sa.Column("code", sa.String(length=50), nullable=False),
		sa.Column("invoice_type", sa.String(length=20), nullable=False, server_default="purchase"),
		sa.Column("amount", sa.Numeric(precision=18, scale=2), nullable=False, server_default="0"),
		sa.Column("discount_amount", sa.Numeric(precision=18, scale=2), nullable=False, server_default="0"),
		sa.Column("currency_id", sa.Integer(), nullable=False),
		sa.Column("status", sa.String(length=20), nullable=False, server_default="awaiting_payment"),
		sa.Column("issued_at", sa.DateTime(), nullable=False),
		sa.Column("due_at", sa.DateTime(), nullable=True),
		sa.Column("paid_at", sa.DateTime(), nullable=True),
		sa.Column("payment_session_id", sa.Integer(), nullable=True),
		sa.Column("gateway_id", sa.Integer(), nullable=True),
		sa.Column("gateway_provider", sa.String(length=50), nullable=True),
		sa.Column("gateway_ref", sa.String(length=200), nullable=True),
		sa.Column("gateway_trace", sa.String(length=200), nullable=True),
		sa.Column("period_months", sa.Integer(), nullable=False),
		sa.Column("coverage_starts_at", sa.DateTime(), nullable=True),
		sa.Column("coverage_ends_at", sa.DateTime(), nullable=True),
		sa.Column("extra_info", sa.JSON(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["plan_id"], ["support_plans.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["currency_id"], ["currencies.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["gateway_id"], ["payment_gateways.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("code", name="uq_support_invoices_code"),
	)
	op.create_index("ix_support_invoices_user_id", "support_invoices", ["user_id"])
	op.create_index("ix_support_invoices_plan_id", "support_invoices", ["plan_id"])
	op.create_index("ix_support_invoices_code", "support_invoices", ["code"])
	op.create_index("ix_support_invoices_status", "support_invoices", ["status"])
	op.create_index("ix_support_invoices_payment_session_id", "support_invoices", ["payment_session_id"])

	op.create_table(
		"support_payment_sessions",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("user_id", sa.Integer(), nullable=False),
		sa.Column("invoice_id", sa.Integer(), nullable=False),
		sa.Column("gateway_id", sa.Integer(), nullable=False),
		sa.Column("amount", sa.Numeric(precision=18, scale=2), nullable=False),
		sa.Column("currency_id", sa.Integer(), nullable=False),
		sa.Column("status", sa.String(length=20), nullable=False, server_default="created"),
		sa.Column("external_ref", sa.String(length=200), nullable=True),
		sa.Column("provider_payload", sa.JSON(), nullable=True),
		sa.Column("verify_payload", sa.JSON(), nullable=True),
		sa.Column("client_return_path", sa.String(length=500), nullable=True),
		sa.Column("expires_at", sa.DateTime(), nullable=False),
		sa.Column("paid_at", sa.DateTime(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["invoice_id"], ["support_invoices.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["gateway_id"], ["payment_gateways.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["currency_id"], ["currencies.id"], ondelete="RESTRICT"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_support_payment_sessions_user_id", "support_payment_sessions", ["user_id"])
	op.create_index("ix_support_payment_sessions_invoice_id", "support_payment_sessions", ["invoice_id"])
	op.create_index("ix_support_payment_sessions_gateway_id", "support_payment_sessions", ["gateway_id"])
	op.create_index("ix_support_payment_sessions_status", "support_payment_sessions", ["status"])
	op.create_index("ix_support_payment_sessions_external_ref", "support_payment_sessions", ["external_ref"])

	op.create_table(
		"support_subscriptions",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("user_id", sa.Integer(), nullable=False),
		sa.Column("plan_id", sa.Integer(), nullable=False),
		sa.Column("status", sa.String(length=20), nullable=False, server_default="pending"),
		sa.Column("starts_at", sa.DateTime(), nullable=False),
		sa.Column("ends_at", sa.DateTime(), nullable=True),
		sa.Column("grace_ends_at", sa.DateTime(), nullable=True),
		sa.Column("auto_renew", sa.Boolean(), nullable=False, server_default=sa.text("false")),
		sa.Column("source_invoice_id", sa.Integer(), nullable=True),
		sa.Column("cancelled_at", sa.DateTime(), nullable=True),
		sa.Column("cancel_reason", sa.String(length=500), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["plan_id"], ["support_plans.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["source_invoice_id"], ["support_invoices.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index("ix_support_subscriptions_user_id", "support_subscriptions", ["user_id"])
	op.create_index("ix_support_subscriptions_plan_id", "support_subscriptions", ["plan_id"])
	op.create_index("ix_support_subscriptions_status", "support_subscriptions", ["status"])
	op.create_index("ix_support_subscriptions_ends_at", "support_subscriptions", ["ends_at"])
	op.create_index("ix_support_subscriptions_source_invoice_id", "support_subscriptions", ["source_invoice_id"])

	op.create_table(
		"support_usage_counters",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("user_id", sa.Integer(), nullable=False),
		sa.Column("period_key", sa.String(length=20), nullable=False),
		sa.Column("tickets_created", sa.Integer(), nullable=False, server_default="0"),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("user_id", "period_key", name="uq_support_usage_user_period"),
	)
	op.create_index("ix_support_usage_counters_user_id", "support_usage_counters", ["user_id"])

	# Seed four duration plans if IRR currency exists (inactive until admin sets prices)
	conn = op.get_bind()
	cur = conn.execute(sa.text("SELECT id FROM currencies WHERE code = 'IRR' LIMIT 1")).fetchone()
	if cur:
		currency_id = int(cur[0])
		now = sa.text("CURRENT_TIMESTAMP")
		plans = [
			("پشتیبانی ۱ ماهه", "support_1m", 1, 10),
			("پشتیبانی ۳ ماهه", "support_3m", 3, 20),
			("پشتیبانی ۶ ماهه", "support_6m", 6, 30),
			("پشتیبانی ۱۲ ماهه", "support_12m", 12, 40),
		]
		for name, code, months, sort_order in plans:
			conn.execute(
				sa.text(
					"""
					INSERT INTO support_plans
					(name, code, period_months, price, currency_id, is_free, is_active, sort_order,
					 description, priority_weight, includes_priority_support, trial_days, created_at, updated_at)
					VALUES
					(:name, :code, :months, 0, :currency_id, false, false, :sort_order,
					 :description, 0, false, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
					"""
				),
				{
					"name": name,
					"code": code,
					"months": months,
					"currency_id": currency_id,
					"sort_order": sort_order,
					"description": f"اشتراک پشتیبانی به مدت {months} ماه",
				},
			)


def downgrade() -> None:
	op.drop_table("support_usage_counters")
	op.drop_table("support_subscriptions")
	op.drop_table("support_payment_sessions")
	op.drop_table("support_invoices")
	op.drop_table("support_plans")
