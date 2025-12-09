"""normalize checks enum to uppercase

Revision ID: 20251204_000002
Revises: 20251204_000001
Create Date: 2025-12-04 23:40:00.000000

این migration مطمئن می‌شود که همه مقادیر enum در جدول checks با حروف بزرگ هستند.
"""
from alembic import op
from sqlalchemy import text


# revision identifiers, used by Alembic.
revision = '20251204_000002'
down_revision = '20250203_000001'
branch_labels = None
depends_on = None


def upgrade():
    """
    تبدیل مقادیر enum جدول checks به حروف بزرگ (idempotent)
    
    این migration برای MySQL طراحی شده است و مقادیر lowercase را به uppercase تبدیل می‌کند.
    اگر دیتابیس شما PostgreSQL است، این migration بدون مشکل رد می‌شود.
    """
    connection = op.get_bind()
    dialect_name = connection.dialect.name
    
    if dialect_name == 'mysql':
        # بررسی وضعیت فعلی ENUM (idempotent)
        result = connection.execute(text("SHOW COLUMNS FROM checks WHERE Field='type'"))
        row = result.fetchone()
        if row:
            current_enum = row[1]  # Type column
            # اگر lowercase وجود دارد، تبدیل کن
            if 'received' in current_enum or 'transferred' in current_enum:
                # برای MySQL: تبدیل enum با استفاده از placeholders موقت
                # Case-insensitive collations در MySQL مانع از وجود همزمان 'received' و 'RECEIVED' می‌شود
                
                # 1) اضافه کردن placeholders موقت
                connection.execute(text(
                    "ALTER TABLE checks MODIFY COLUMN type "
                    "ENUM('received','transferred','TMP_R','TMP_T') NOT NULL"
                ))
                
                # 2) انتقال مقادیر lowercase به placeholders
                connection.execute(text("UPDATE checks SET type='TMP_R' WHERE LOWER(type)='received'"))
                connection.execute(text("UPDATE checks SET type='TMP_T' WHERE LOWER(type)='transferred'"))
                
                # 3) تغییر enum به uppercase + placeholders
                connection.execute(text(
                    "ALTER TABLE checks MODIFY COLUMN type "
                    "ENUM('RECEIVED','TRANSFERRED','TMP_R','TMP_T') NOT NULL"
                ))
                
                # 4) انتقال placeholders به مقادیر نهایی uppercase
                connection.execute(text("UPDATE checks SET type='RECEIVED' WHERE type='TMP_R'"))
                connection.execute(text("UPDATE checks SET type='TRANSFERRED' WHERE type='TMP_T'"))
                
                # 5) حذف placeholders و تنظیم enum نهایی
                connection.execute(text(
                    "ALTER TABLE checks MODIFY COLUMN type "
                    "ENUM('RECEIVED','TRANSFERRED') NOT NULL"
                ))
            # اگر قبلاً uppercase است، کاری نکن
    
    elif dialect_name == 'postgresql':
        # برای PostgreSQL: تبدیل مستقیم (case-sensitive است)
        connection.execute(text("UPDATE checks SET type='RECEIVED' WHERE type='received'"))
        connection.execute(text("UPDATE checks SET type='TRANSFERRED' WHERE type='transferred'"))
    
    # برای سایر دیتابیس‌ها هیچ کاری انجام نمی‌دهیم


def downgrade():
    """
    این migration قابل برگشت نیست چون ممکن است داده‌ها را از بین ببرد.
    """
    pass

