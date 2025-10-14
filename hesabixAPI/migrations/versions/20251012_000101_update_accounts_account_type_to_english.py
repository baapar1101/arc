from __future__ import annotations

from alembic import op
import sqlalchemy as sa


"""
Normalize accounts.account_type to English values and add constraint

Revision ID: 20251012_000101_update_accounts_account_type_to_english
Revises: 20251011_010001_replace_accounts_chart_seed
Create Date: 2025-10-12 00:01:01.000001
"""


# revision identifiers, used by Alembic.
revision = '20251012_000101_update_accounts_account_type_to_english'
down_revision = '20251011_010001_replace_accounts_chart_seed'
branch_labels = None
depends_on = None


ALLOWED_TYPES = (
	"bank",
	"cash_register",
	"petty_cash",
	"check",
	"person",
	"product",
	"service",
	"accounting_document",
)


def upgrade() -> None:
	conn = op.get_bind()

	# نگاشت مقادیر عددی/قدیمی به مقادیر انگلیسی جدید
	mapping_updates: list[tuple[str, tuple[str, ...]]] = [
		("bank", ("3",)),
		("cash_register", ("1",)),
		("petty_cash", ("2",)),
		("check", ("5", "6", "10")),
		("person", ("4", "9")),
		("product", ("7",)),
		("service", ("25", "26", "29", "30", "31")),
	]

	for new_val, old_vals in mapping_updates:
		for old_val in old_vals:
			conn.execute(
				sa.text(
					"UPDATE accounts SET account_type = :new_val WHERE account_type = :old_val"
				),
				{"new_val": new_val, "old_val": old_val},
			)

	# سایر مقادیر ناشناخته را به accounting_document تنظیم کن
	placeholders = ", ".join([":v" + str(i) for i in range(len(ALLOWED_TYPES))])
	params = {("v" + str(i)): v for i, v in enumerate(ALLOWED_TYPES)}
	conn.execute(
		sa.text(
			f"UPDATE accounts SET account_type = 'accounting_document' WHERE account_type NOT IN ({placeholders})"
		),
		params,
	)

	# افزودن چک‌کانسترینت برای اطمینان از مقادیر مجاز (در صورت نبود)
	# برخی پایگاه‌ها CHECK را نادیده می‌گیرند؛ این بخش ایمن با try/except است
	try:
		op.create_check_constraint(
			"ck_accounts_account_type_allowed",
			"accounts",
			"account_type IN ('bank', 'cash_register', 'petty_cash', 'check', 'person', 'product', 'service', 'accounting_document')",
		)
	except Exception:
		# اگر از قبل وجود داشته باشد، نادیده بگیر
		pass


def downgrade() -> None:
	# حذف چک‌کانسترینت
	op.drop_constraint("ck_accounts_account_type_allowed", "accounts", type_="check")

	conn = op.get_bind()

	# نگاشت معکوس ساده برای بازگشت به مقادیر عددی پایه
	reverse_mapping: list[tuple[str, str]] = [
		("bank", "3"),
		("cash_register", "1"),
		("petty_cash", "2"),
		("check", "5"),
		("person", "4"),
		("product", "7"),
		("service", "25"),
		("accounting_document", "0"),
	]

	for eng_val, legacy_val in reverse_mapping:
		conn.execute(
			sa.text(
				"UPDATE accounts SET account_type = :legacy WHERE account_type = :eng"
			),
			{"legacy": legacy_val, "eng": eng_val},
		)


