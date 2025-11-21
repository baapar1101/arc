"""add AI expense account (70508)

Revision ID: 20250121_000001_add_ai_expense_account
Revises: 20251120_053716_add_ai_tables
Create Date: 2025-01-21 00:00:01.000001
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "20250121_000001_add_ai_expense_account"
down_revision: Union[str, None] = "20251120_053716_add_ai_tables"  # بعد از AI tables
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
	conn = op.get_bind()
	
	# بررسی وجود حساب 70508
	check_query = sa.text("SELECT id FROM accounts WHERE business_id IS NULL AND code = '70508' LIMIT 1")
	existing = conn.execute(check_query).fetchone()
	
	if existing:
		# اگر حساب وجود دارد، فقط نام را به‌روزرسانی می‌کنیم
		update_query = sa.text("""
			UPDATE accounts 
			SET name = 'هزینه هوش مصنوعی', updated_at = NOW()
			WHERE business_id IS NULL AND code = '70508'
		""")
		conn.execute(update_query)
	else:
		# پیدا کردن parent_id (705 - هزینه های عمومی)
		parent_query = sa.text("SELECT id FROM accounts WHERE business_id IS NULL AND code = '705' LIMIT 1")
		parent_result = conn.execute(parent_query).fetchone()
		
		if not parent_result:
			raise Exception("Parent account with code '705' (هزینه های عمومی) not found")
		
		parent_id = parent_result[0]
		
		# ایجاد حساب هزینه هوش مصنوعی (account_type = 'accounting_document' مثل سایر حساب‌های عمومی)
		insert_query = sa.text("""
			INSERT INTO accounts (name, business_id, account_type, code, parent_id, created_at, updated_at)
			VALUES ('هزینه هوش مصنوعی', NULL, :account_type, '70508', :parent_id, NOW(), NOW())
		""")
		conn.execute(insert_query, {"parent_id": parent_id, "account_type": "accounting_document"})


def downgrade() -> None:
	conn = op.get_bind()
	
	# حذف حساب هزینه هوش مصنوعی (فقط حساب‌های عمومی)
	delete_query = sa.text("DELETE FROM accounts WHERE business_id IS NULL AND code = '70508'")
	conn.execute(delete_query)

