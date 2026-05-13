"""جداول تسهیلات دریافتی (قرارداد، اقساط، ثبت پرداخت)

Revision ID: 20260613_000002_received_loan_facility_tables
Revises: 20260613_000001_seed_received_loan_facility_chart_accounts
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260613_000002_received_loan_facility_tables"
down_revision = "20260613_000001_seed_received_loan_facility_chart_accounts"
branch_labels = None
depends_on = None


def upgrade() -> None:
	op.create_table(
		"received_loan_facilities",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("business_id", sa.Integer(), nullable=False),
		sa.Column("currency_id", sa.Integer(), nullable=False),
		sa.Column("created_by_user_id", sa.Integer(), nullable=False),
		sa.Column("title", sa.String(length=255), nullable=False),
		sa.Column("notes", sa.Text(), nullable=True),
		sa.Column(
			"lender_bank_account_id",
			sa.Integer(),
			sa.ForeignKey("bank_accounts.id", ondelete="SET NULL"),
			nullable=True,
			index=True,
		),
		sa.Column("principal_amount", sa.Numeric(precision=18, scale=2), nullable=False),
		sa.Column("annual_interest_rate_percent", sa.Numeric(precision=18, scale=6), nullable=True),
		sa.Column("contract_date", sa.Date(), nullable=False),
		sa.Column("first_installment_date", sa.Date(), nullable=True),
		sa.Column("installment_count", sa.Integer(), nullable=True),
		sa.Column("status", sa.String(length=20), nullable=False, server_default="draft"),
		sa.Column(
			"disbursement_document_id",
			sa.Integer(),
			sa.ForeignKey("documents.id", ondelete="SET NULL"),
			nullable=True,
			index=True,
		),
		sa.Column("schedule_method", sa.String(length=40), nullable=True),
		sa.Column("extra_info", sa.JSON(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("NOW()")),
		sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.text("NOW()")),
		sa.ForeignKeyConstraint(["business_id"], ["businesses.id"], ondelete="CASCADE"),
		sa.ForeignKeyConstraint(["currency_id"], ["currencies.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="RESTRICT"),
		sa.PrimaryKeyConstraint("id"),
	)
	op.create_index(
		op.f("ix_received_loan_facilities_business_id"),
		"received_loan_facilities",
		["business_id"],
	)
	op.create_index(
		op.f("ix_received_loan_facilities_contract_date"),
		"received_loan_facilities",
		["contract_date"],
	)
	op.create_index(
		op.f("ix_received_loan_facilities_status"),
		"received_loan_facilities",
		["status"],
	)

	op.create_table(
		"received_loan_installments",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("facility_id", sa.Integer(), nullable=False),
		sa.Column("sequence_no", sa.Integer(), nullable=False),
		sa.Column("due_date", sa.Date(), nullable=False),
		sa.Column("principal_due", sa.Numeric(precision=18, scale=2), nullable=False, server_default="0"),
		sa.Column("interest_due", sa.Numeric(precision=18, scale=2), nullable=False, server_default="0"),
		sa.Column("penalty_due", sa.Numeric(precision=18, scale=2), nullable=False, server_default="0"),
		sa.Column("principal_paid", sa.Numeric(precision=18, scale=2), nullable=False, server_default="0"),
		sa.Column("interest_paid", sa.Numeric(precision=18, scale=2), nullable=False, server_default="0"),
		sa.Column("penalty_paid", sa.Numeric(precision=18, scale=2), nullable=False, server_default="0"),
		sa.Column("extra_info", sa.JSON(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("NOW()")),
		sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.text("NOW()")),
		sa.ForeignKeyConstraint(["facility_id"], ["received_loan_facilities.id"], ondelete="CASCADE"),
		sa.PrimaryKeyConstraint("id"),
		sa.UniqueConstraint("facility_id", "sequence_no", name="uq_received_loan_installments_facility_sequence"),
	)
	op.create_index(
		op.f("ix_received_loan_installments_facility_id"),
		"received_loan_installments",
		["facility_id"],
	)
	op.create_index(
		op.f("ix_received_loan_installments_due_date"),
		"received_loan_installments",
		["due_date"],
	)

	op.create_table(
		"received_loan_installment_payments",
		sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
		sa.Column("installment_id", sa.Integer(), nullable=False),
		sa.Column("payment_date", sa.Date(), nullable=False),
		sa.Column("amount_total", sa.Numeric(precision=18, scale=2), nullable=False),
		sa.Column("principal_part", sa.Numeric(precision=18, scale=2), nullable=False, server_default="0"),
		sa.Column("interest_part", sa.Numeric(precision=18, scale=2), nullable=False, server_default="0"),
		sa.Column("penalty_part", sa.Numeric(precision=18, scale=2), nullable=False, server_default="0"),
		sa.Column(
			"bank_account_id",
			sa.Integer(),
			sa.ForeignKey("bank_accounts.id", ondelete="SET NULL"),
			nullable=True,
			index=True,
		),
		sa.Column(
			"document_id",
			sa.Integer(),
			sa.ForeignKey("documents.id", ondelete="SET NULL"),
			nullable=True,
			index=True,
		),
		sa.Column("description", sa.Text(), nullable=True),
		sa.Column("created_by_user_id", sa.Integer(), nullable=False),
		sa.Column("extra_info", sa.JSON(), nullable=True),
		sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.text("NOW()")),
		sa.PrimaryKeyConstraint("id"),
		sa.ForeignKeyConstraint(["created_by_user_id"], ["users.id"], ondelete="RESTRICT"),
		sa.ForeignKeyConstraint(["installment_id"], ["received_loan_installments.id"], ondelete="CASCADE"),
	)
	op.create_index(
		op.f("ix_received_loan_installment_payments_payment_date"),
		"received_loan_installment_payments",
		["payment_date"],
	)


def downgrade() -> None:
	op.drop_index(
		op.f("ix_received_loan_installment_payments_payment_date"),
		table_name="received_loan_installment_payments",
	)
	op.drop_table("received_loan_installment_payments")

	op.drop_index(op.f("ix_received_loan_installments_due_date"), table_name="received_loan_installments")
	op.drop_index(op.f("ix_received_loan_installments_facility_id"), table_name="received_loan_installments")
	op.drop_table("received_loan_installments")

	op.drop_index(op.f("ix_received_loan_facilities_status"), table_name="received_loan_facilities")
	op.drop_index(op.f("ix_received_loan_facilities_contract_date"), table_name="received_loan_facilities")
	op.drop_index(op.f("ix_received_loan_facilities_business_id"), table_name="received_loan_facilities")
	op.drop_table("received_loan_facilities")
