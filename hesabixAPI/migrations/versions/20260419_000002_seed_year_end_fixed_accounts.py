"""حساب‌های عمومی مورد نیاز بستن سال مالی (کدهای ثابت سرویس year_end_closing)

کدهای 13101، 21101، 12101، 50101 در نمودار استاندارد قبلی نیستند ولی در
`year_end_closing_service._get_fixed_account_by_code` استفاده می‌شوند.

موقعیت درخت:
- 13101 زیر گروه 104 (حساب‌های دریافتنی) مانند سایر معین‌های اشخاص
- 21101 زیر گروه 202 (حساب‌ها و اسناد پرداختنی)
- 12101 زیر گروه 101 (دارایی‌های جاری) کنار موجودی کالای 10102
- 50101 زیر گروه 708 (هزینه‌های غیرعملیاتی) برای ثبت مالیات در سند بستن

Revision ID: 20260419_000002_seed_year_end_fixed_accounts
Revises: 20260419_000001_customer_club_v2_enhancements
Create Date: 2026-04-19
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260419_000002_seed_year_end_fixed_accounts"
down_revision = "20260419_000001_customer_club_v2_enhancements"
branch_labels = None
depends_on = None


def upgrade() -> None:
	conn = op.get_bind()

	def _insert_if_missing(code: str, name: str, parent_code: str) -> None:
		has_parent = conn.execute(
			sa.text(
				"SELECT id FROM accounts WHERE business_id IS NULL AND code = :pc LIMIT 1"
			),
			{"pc": parent_code},
		).scalar()
		if has_parent is None:
			raise RuntimeError(
				f"میگریشن year_end حساب والد با کد {parent_code} در accounts یافت نشد."
			)
		conn.execute(
			sa.text(
				"""
				INSERT INTO accounts (name, business_id, account_type, code, parent_id, created_at, updated_at)
				SELECT :name, NULL, 'accounting_document', :code, :pid, NOW(), NOW()
				WHERE NOT EXISTS (
					SELECT 1 FROM accounts WHERE business_id IS NULL AND code = :code
				)
				"""
			),
			{"name": name, "code": code, "pid": has_parent},
		)

	_insert_if_missing(
		"13101",
		"بدهکاران تجاری",
		"104",
	)
	_insert_if_missing(
		"21101",
		"بستانکاران تجاری",
		"202",
	)
	_insert_if_missing(
		"12101",
		"موجودی کالا",
		"101",
	)
	_insert_if_missing(
		"50101",
		"مالیات بر درآمد",
		"708",
	)


def downgrade() -> None:
	conn = op.get_bind()
	for code in ("13101", "21101", "12101", "50101"):
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
