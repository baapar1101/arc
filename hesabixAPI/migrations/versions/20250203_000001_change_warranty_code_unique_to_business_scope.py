"""تغییر یکتایی کد گارانتی به سطح کسب و کار

revision: 20250203_000001
down_revision: 8cb61ffb0637
branch_labels: None
depends_on: None

این migration کد گارانتی را از یکتا در سطح سیستم به یکتا در سطح کسب و کار تغییر می‌دهد.
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20250203_000001'
down_revision = '8cb61ffb0637'
branch_labels = None
depends_on = None


def upgrade():
    # حذف constraint و index قبلی برای code
    op.drop_constraint('uq_warranty_codes_code', 'warranty_codes', type_='unique')
    op.drop_index('ix_warranty_codes_code', table_name='warranty_codes')
    
    # اضافه کردن constraint و index جدید برای business_id + code
    op.create_unique_constraint(
        'uq_warranty_codes_business_code',
        'warranty_codes',
        ['business_id', 'code']
    )
    op.create_index(
        'idx_warranty_codes_code',
        'warranty_codes',
        ['business_id', 'code'],
        unique=False
    )
    
    # اضافه کردن index برای activated_by_person_id
    op.create_index(
        'idx_warranty_codes_activated_by_person_id',
        'warranty_codes',
        ['activated_by_person_id'],
        unique=False
    )
    
    # اضافه کردن index ترکیبی برای business_id + activated_by_person_id
    op.create_index(
        'idx_warranty_codes_business_person',
        'warranty_codes',
        ['business_id', 'activated_by_person_id'],
        unique=False
    )


def downgrade():
    # حذف index های جدید
    op.drop_index('idx_warranty_codes_business_person', table_name='warranty_codes')
    op.drop_index('idx_warranty_codes_activated_by_person_id', table_name='warranty_codes')
    op.drop_index('idx_warranty_codes_code', table_name='warranty_codes')
    op.drop_constraint('uq_warranty_codes_business_code', 'warranty_codes', type_='unique')
    
    # بازگرداندن constraint و index قبلی
    op.create_unique_constraint('uq_warranty_codes_code', 'warranty_codes', ['code'])
    op.create_index('ix_warranty_codes_code', 'warranty_codes', ['code'], unique=True)

