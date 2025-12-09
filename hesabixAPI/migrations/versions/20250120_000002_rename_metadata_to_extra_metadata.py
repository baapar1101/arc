"""تغییر نام ستون metadata به extra_metadata

revision: 20250120_000002_rename_metadata_to_extra_metadata
down_revision: 20250120_000001_create_warranty_tables
branch_labels: None
depends_on: None

این migration نام ستون metadata را در جدول warranty_codes به extra_metadata تغییر می‌دهد
تا با Declarative API SQLAlchemy تداخل نداشته باشد.
"""
from __future__ import annotations

from alembic import op


# revision identifiers, used by Alembic.
revision = '20250120_000002'
down_revision = '20250120_000001'
branch_labels = None
depends_on = None


def upgrade():
    # تغییر نام ستون از metadata به extra_metadata
    # بررسی وجود ستون قبل از تغییر نام
    from sqlalchemy import inspect
    from sqlalchemy.dialects.mysql import JSON
    
    conn = op.get_bind()
    inspector = inspect(conn)
    
    # بررسی وجود جدول
    if 'warranty_codes' in inspector.get_table_names():
        columns = [col['name'] for col in inspector.get_columns('warranty_codes')]
        
        # اگر ستون metadata وجود دارد، نام آن را تغییر بده
        if 'metadata' in columns:
            op.alter_column(
                'warranty_codes',
                'metadata',
                new_column_name='extra_metadata',
                existing_type=JSON,
                existing_nullable=True,
                existing_comment='اطلاعات اضافی'
            )
        # اگر extra_metadata از قبل وجود دارد، کاری نکن (migration قبلاً اجرا شده)


def downgrade():
    # برگشت به نام قبلی
    from sqlalchemy.dialects.mysql import JSON
    op.alter_column(
        'warranty_codes',
        'extra_metadata',
        new_column_name='metadata',
        existing_type=JSON,
        existing_nullable=True,
        existing_comment='اطلاعات اضافی'
    )

