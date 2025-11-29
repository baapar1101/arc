"""حذف کدهای حساب 10705, 60105, 20504, 20503 از جدول accounts

revision: 20250116_000001_delete_account_codes
down_revision: 20250115_000001
branch_labels: None
depends_on: None

این میگریشن کدهای حساب زیر را از جدول accounts حذف می‌کند:
- 10705
- 60105
- 20504
- 20503
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20250116_000001'
down_revision = '449131e7b816'
branch_labels = None
depends_on = None


def upgrade():
    """حذف کدهای حساب"""
    conn = op.get_bind()
    
    # حذف کدهای حساب با یک query واحد
    delete_query = sa.text("""
        DELETE FROM accounts
        WHERE code IN ('10705', '60105', '20504', '20503')
    """)
    conn.execute(delete_query)


def downgrade():
    """برگرداندن تغییرات - این میگریشن قابل برگشت نیست"""
    # حذف حساب‌ها عملیات برگشت‌ناپذیری است
    # برای برگشت نیاز به اطلاعات کامل حساب‌های حذف شده داریم
    pass

