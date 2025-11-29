"""اصلاح کد حساب هزینه سرویس‌های استعلامات از 70903 به 70509

revision: 20250115_000001_fix_zohal_account_code
down_revision: b8c9286db6bd
branch_labels: None
depends_on: None

این میگریشن:
1. حساب 70903 را به نام اصلی "جرائم دیرکرد بانکی" برمی‌گرداند (اگر تغییر کرده باشد)
2. حساب 70509 را برای "هزینه سرویس‌های استعلامات" ایجاد می‌کند
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20250115_000001'
down_revision = 'b8c9286db6bd'
branch_labels = None
depends_on = None


def upgrade():
    """اصلاح حساب‌ها"""
    conn = op.get_bind()
    
    # 1. برگرداندن حساب 70903 به نام اصلی "جرائم دیرکرد بانکی" (اگر تغییر کرده باشد)
    update_70903 = sa.text("""
        UPDATE accounts
        SET name = 'جرائم دیرکرد بانکی',
            updated_at = NOW()
        WHERE code = '70903'
          AND business_id IS NULL
          AND name != 'جرائم دیرکرد بانکی'
    """)
    conn.execute(update_70903)
    
    # 2. ایجاد حساب 70509 برای "هزینه سرویس‌های استعلامات"
    # ابتدا بررسی می‌کنیم که آیا حساب 705 وجود دارد
    check_705 = sa.text("SELECT id FROM accounts WHERE code = '705' AND business_id IS NULL LIMIT 1")
    result_705 = conn.execute(check_705).fetchone()
    
    if result_705:
        parent_id_705 = result_705[0]
        
        # بررسی می‌کنیم که آیا حساب 70509 از قبل وجود دارد
        check_70509 = sa.text("SELECT id FROM accounts WHERE code = '70509' AND business_id IS NULL LIMIT 1")
        result_70509 = conn.execute(check_70509).fetchone()
        
        if not result_70509:
            # ایجاد حساب 70509
            insert_70509 = sa.text("""
                INSERT INTO accounts (name, code, account_type, business_id, parent_id, created_at, updated_at)
                VALUES ('هزینه سرویس‌های استعلامات', '70509', 'accounting_document', NULL, :parent_id, NOW(), NOW())
            """)
            conn.execute(insert_70509, {"parent_id": parent_id_705})
        else:
            # به‌روزرسانی نام حساب در صورت نیاز
            update_70509 = sa.text("""
                UPDATE accounts
                SET name = 'هزینه سرویس‌های استعلامات',
                    account_type = 'accounting_document',
                    parent_id = :parent_id,
                    updated_at = NOW()
                WHERE code = '70509'
                  AND business_id IS NULL
            """)
            conn.execute(update_70509, {"parent_id": parent_id_705})


def downgrade():
    """برگرداندن تغییرات"""
    conn = op.get_bind()
    
    # حذف حساب 70509
    delete_70509 = sa.text("""
        DELETE FROM accounts
        WHERE code = '70509' AND business_id IS NULL
    """)
    conn.execute(delete_70509)
    
    # برگرداندن حساب 70903 به "هزینه سرویس‌های استعلامات" (اگر قبلاً تغییر کرده بود)
    # این بخش را می‌توانید بر اساس نیاز سیستم تغییر دهید
    pass

