"""Customer club (loyalty) tables

Revision ID: 20260418_000002_customer_club_tables
Revises: 20260418_000001_invoice_profit_ledger_recognition
Create Date: 2026-04-18
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260418_000002_customer_club_tables"
down_revision = "20260418_000001_invoice_profit_ledger_recognition"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"customer_club_settings",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("earn_mode", sa.String(length=40), nullable=False, server_default=sa.text("'percent_basis'")),
		sa.Column("amount_basis", sa.String(length=40), nullable=False, server_default=sa.text("'net'")),
		sa.Column("percent_of_basis", sa.Numeric(18, 8), nullable=True),
		sa.Column("step_currency_amount", sa.Numeric(18, 4), nullable=True),
		sa.Column("points_per_step", sa.Numeric(18, 8), nullable=True),
		sa.Column("rounding_mode", sa.String(length=16), nullable=False, server_default=sa.text("'floor'")),
		sa.Column("max_points_per_invoice", sa.Numeric(18, 4), nullable=True),
		sa.Column("min_basis_amount", sa.Numeric(18, 4), nullable=False, server_default=sa.text("0")),
		sa.Column("require_customer_person_type", sa.Boolean(), nullable=False, server_default=sa.text("true")),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", name="uq_customer_club_settings_business"),
		mysql_charset="utf8mb4",
	)
	op.create_index(op.f("ix_customer_club_settings_business_id"), "customer_club_settings", ["business_id"], unique=False)

	op.create_table(
		"customer_club_balances",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("person_id", sa.Integer(), nullable=False),
		sa.Column("balance_points", sa.Numeric(18, 6), nullable=False, server_default=sa.text("0")),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["person_id"], ["persons.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("business_id", "person_id", name="uq_customer_club_balance_biz_person"),
		mysql_charset="utf8mb4",
	)
	op.create_index(op.f("ix_customer_club_balances_business_id"), "customer_club_balances", ["business_id"], unique=False)
	op.create_index(op.f("ix_customer_club_balances_person_id"), "customer_club_balances", ["person_id"], unique=False)

	op.create_table(
		"customer_club_ledger",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("person_id", sa.Integer(), nullable=True),
		sa.Column("delta_points", sa.Numeric(18, 6), nullable=False),
		sa.Column("balance_after", sa.Numeric(18, 6), nullable=False),
		sa.Column("transaction_type", sa.String(length=32), nullable=False),
		sa.Column("reference_document_id", sa.Integer(), nullable=True),
		sa.Column("description", sa.Text(), nullable=True),
		sa.Column("created_by_user_id", sa.Integer(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["person_id"], ["persons.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["reference_document_id"], ["documents.id"], ondelete="SET NULL"),
		sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("id"),
		mysql_charset="utf8mb4",
	)
	op.create_index(op.f("ix_customer_club_ledger_business_id"), "customer_club_ledger", ["business_id"], unique=False)
	op.create_index(op.f("ix_customer_club_ledger_person_id"), "customer_club_ledger", ["person_id"], unique=False)
	op.create_index(op.f("ix_customer_club_ledger_reference_document_id"), "customer_club_ledger", ["reference_document_id"], unique=False)
	op.create_index(op.f("ix_customer_club_ledger_created_by_user_id"), "customer_club_ledger", ["created_by_user_id"], unique=False)
	op.create_index("ix_customer_club_ledger_biz_created", "customer_club_ledger", ["business_id", "created_at"], unique=False)

	op.create_table(
		"customer_club_invoice_snapshots",
		sa.Column("document_id", sa.Integer(), nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("person_id", sa.Integer(), nullable=True),
		sa.Column("accrued_points", sa.Numeric(18, 6), nullable=False, server_default=sa.text("0")),
		sa.Column("updated_at", sa.DateTime(), nullable=False),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["document_id"], ["documents.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["person_id"], ["persons.id"], ondelete="SET NULL"),
		sa.PrimaryKeyConstraint("document_id"),
		mysql_charset="utf8mb4",
	)
	op.create_index(op.f("ix_customer_club_invoice_snapshots_business_id"), "customer_club_invoice_snapshots", ["business_id"], unique=False)
	op.create_index(op.f("ix_customer_club_invoice_snapshots_person_id"), "customer_club_invoice_snapshots", ["person_id"], unique=False)


def downgrade() -> None:
	op.drop_index("ix_customer_club_ledger_biz_created", table_name="customer_club_ledger")
	op.drop_index(op.f("ix_customer_club_ledger_created_by_user_id"), table_name="customer_club_ledger")
	op.drop_index(op.f("ix_customer_club_ledger_reference_document_id"), table_name="customer_club_ledger")
	op.drop_index(op.f("ix_customer_club_ledger_person_id"), table_name="customer_club_ledger")
	op.drop_index(op.f("ix_customer_club_ledger_business_id"), table_name="customer_club_ledger")
	op.drop_table("customer_club_ledger")

	op.drop_index(op.f("ix_customer_club_invoice_snapshots_person_id"), table_name="customer_club_invoice_snapshots")
	op.drop_index(op.f("ix_customer_club_invoice_snapshots_business_id"), table_name="customer_club_invoice_snapshots")
	op.drop_table("customer_club_invoice_snapshots")

	op.drop_index(op.f("ix_customer_club_balances_person_id"), table_name="customer_club_balances")
	op.drop_index(op.f("ix_customer_club_balances_business_id"), table_name="customer_club_balances")
	op.drop_table("customer_club_balances")

	op.drop_index(op.f("ix_customer_club_settings_business_id"), table_name="customer_club_settings")
	op.drop_table("customer_club_settings")
