"""add wallet account (10205)

Revision ID: 20250116_000002_add_wallet_account
Revises: 20250116_000001_add_storage_plans_and_subscriptions
Create Date: 2025-01-16 00:00:02.000001
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "20250116_000002_add_wallet_account"
down_revision: Union[str, None] = "20250116_000001_add_storage_plans_and_subscriptions"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
	conn = op.get_bind()
	
	# بررسی وجود حساب 10205
	check_query = sa.text("SELECT id FROM accounts WHERE business_id IS NULL AND code = '10205' LIMIT 1")
	existing = conn.execute(check_query).fetchone()
	
	if existing:
		# اگر حساب وجود دارد، فقط نام را به‌روزرسانی می‌کنیم
		update_query = sa.text("""
			UPDATE accounts 
			SET name = 'کیف پول', updated_at = NOW()
			WHERE business_id IS NULL AND code = '10205'
		""")
		conn.execute(update_query)
	else:
		# پیدا کردن parent_id (102 - موجودی نقد و بانک)
		parent_query = sa.text("SELECT id FROM accounts WHERE business_id IS NULL AND code = '102' LIMIT 1")
		parent_result = conn.execute(parent_query).fetchone()
		
		if not parent_result:
			raise Exception("Parent account with code '102' not found")
		
		parent_id = parent_result[0]
		
		# ایجاد حساب کیف پول (account_type = 'accounting_document' مثل سایر حساب‌های عمومی)
		insert_query = sa.text("""
			INSERT INTO accounts (name, business_id, account_type, code, parent_id, created_at, updated_at)
			VALUES ('کیف پول', NULL, :account_type, '10205', :parent_id, NOW(), NOW())
		""")
		conn.execute(insert_query, {"parent_id": parent_id, "account_type": "accounting_document"})


def downgrade() -> None:
	conn = op.get_bind()
	
	# حذف حساب کیف پول (فقط حساب‌های عمومی)
	delete_query = sa.text("DELETE FROM accounts WHERE business_id IS NULL AND code = '10205'")
	conn.execute(delete_query)

