"""حساب‌های استاندارد تسهیلات دریافتی در جدول حساب عمومی

زیرمجموعه «وام پرداختنی» (کد 20501، زیر بدهی‌های غیرجاری)، برای ماژول
تسهیلات دریافتنی؛ درخت مانند میگریشن‌های دیگر با واسطه parent_id واقعی است.

رویدادهای هزینه‌ای (بهره/جریمه) از حساب‌های موجود 70901 و 70903 استفاده می‌کنند.

فازهای بعدی پیشنهادی (اجرا خارج از این فایل):
- فاز ۲: جداول قرارداد/قسط و API با ارجاع به این کدها.
- فاز ۳: UI و اتصال اسناد.
- فاز ۴: گزارشات و سطوح دسترسی.

Revision ID: 20260613_000001_seed_received_loan_facility_chart_accounts
Revises: 20260612_000002_merge_heads_report_template_status_events_and_business_print_settings_invoice_pdf_sections
Create Date: 2026-06-13
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "20260613_000001_seed_received_loan_facility_chart_accounts"
down_revision = (
	"20260612_000002_merge_heads_report_template_status_events_and_business_print_settings_invoice_pdf_sections"
)
branch_labels = None
depends_on = None

# هم‌نوع با حساب‌های نمونه 20503/20504 در میگریشن نمودار حساب‌ها
_RECEIVED_LOAN_ACCOUNT_TYPE = "0"


def upgrade() -> None:
	conn = op.get_bind()

	def _resolve_parent_account_id(parent_code: str) -> int:
		row = conn.execute(
			sa.text(
				"SELECT id FROM accounts WHERE business_id IS NULL AND code = :pc LIMIT 1"
			),
			{"pc": parent_code},
		).scalar()
		if row is None:
			raise RuntimeError(
				f"میگریشن تسهیلات: حساب والد با کد {parent_code} در accounts یافت نشد."
			)
		return int(row)

	pid = _resolve_parent_account_id("20501")

	def _insert_if_missing(code: str, name: str) -> None:
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
			{
				"name": name,
				"atype": _RECEIVED_LOAN_ACCOUNT_TYPE,
				"code": code,
				"pid": pid,
			},
		)

	# معین کنترلی اصل؛ قراردادهای جزئی را می‌توان زیر این یا به‌صورت جزء‌حساب مدیریت کرد
	_insert_if_missing("20505", "تسهیلات دریافتی ـ اصل")
	_insert_if_missing("20506", "ذخیره بهره تسهیلات دریافتی پرداختنی")
	_insert_if_missing("20507", "وجه التزام (جرایم) تسهیلات دریافتی پرداختنی")


def downgrade() -> None:
	conn = op.get_bind()
	for code in ("20507", "20506", "20505"):
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
