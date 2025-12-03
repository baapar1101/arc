"""ایجاد حساب هزینه اشتراک و خدمات سیستم (70507)

revision: 20251202_000002_create_document_monetization_expense_account
down_revision: 20251202_000001
branch_labels: None
depends_on: None

این میگریشن حساب 70507 را برای هزینه اشتراک و خدمات سیستم ایجاد می‌کند.
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20251202_000002'
down_revision = '20251202_000001'
branch_labels = None
depends_on = None


def upgrade():
    """ایجاد حساب 70507"""
    conn = op.get_bind()
    
    # بررسی می‌کنیم که آیا حساب 705 وجود دارد
    check_705 = sa.text("SELECT id FROM accounts WHERE code = '705' AND business_id IS NULL LIMIT 1")
    result_705 = conn.execute(check_705).fetchone()
    
    if result_705:
        parent_id_705 = result_705[0]
        
        # بررسی می‌کنیم که آیا حساب 70507 از قبل وجود دارد
        check_70507 = sa.text("SELECT id FROM accounts WHERE code = '70507' AND business_id IS NULL LIMIT 1")
        result_70507 = conn.execute(check_70507).fetchone()
        
        if not result_70507:
            # ایجاد حساب 70507
            insert_70507 = sa.text("""
                INSERT INTO accounts (name, code, account_type, business_id, parent_id, created_at, updated_at)
                VALUES ('هزینه اشتراک و خدمات سیستم', '70507', 'accounting_document', NULL, :parent_id, NOW(), NOW())
            """)
            conn.execute(insert_70507, {"parent_id": parent_id_705})
        else:
            # به‌روزرسانی نام حساب در صورت نیاز
            update_70507 = sa.text("""
                UPDATE accounts
                SET name = 'هزینه اشتراک و خدمات سیستم',
                    account_type = 'accounting_document',
                    parent_id = :parent_id,
                    updated_at = NOW()
                WHERE code = '70507'
                  AND business_id IS NULL
            """)
            conn.execute(update_70507, {"parent_id": parent_id_705})


def downgrade():
    """برگرداندن تغییرات - حذف حساب 70507"""
    conn = op.get_bind()
    
    # حذف حساب 70507
    delete_70507 = sa.text("""
        DELETE FROM accounts
        WHERE code = '70507' AND business_id IS NULL
    """)
    conn.execute(delete_70507)



