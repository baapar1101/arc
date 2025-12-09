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
    from sqlalchemy import inspect
    from sqlalchemy.engine.reflection import Inspector
    
    bind = op.get_bind()
    inspector = inspect(bind)
    
    # بررسی و حذف constraint/index قبلی برای code (idempotent)
    existing_indexes = [idx['name'] for idx in inspector.get_indexes('warranty_codes')]
    existing_constraints = [uc['name'] for uc in inspector.get_unique_constraints('warranty_codes')]
    
    if 'uq_warranty_codes_code' in existing_constraints:
        op.drop_constraint('uq_warranty_codes_code', 'warranty_codes', type_='unique')
    if 'ix_warranty_codes_code' in existing_indexes:
        op.drop_index('ix_warranty_codes_code', table_name='warranty_codes')
    
    # اضافه کردن constraint و index جدید برای business_id + code (idempotent)
    if 'uq_warranty_codes_business_code' not in existing_constraints:
        op.create_unique_constraint(
            'uq_warranty_codes_business_code',
            'warranty_codes',
            ['business_id', 'code']
        )
    if 'idx_warranty_codes_code' not in existing_indexes:
        op.create_index(
            'idx_warranty_codes_code',
            'warranty_codes',
            ['business_id', 'code'],
            unique=False
        )
    
    # اضافه کردن index برای activated_by_person_id (idempotent)
    if 'idx_warranty_codes_activated_by_person_id' not in existing_indexes:
        op.create_index(
            'idx_warranty_codes_activated_by_person_id',
            'warranty_codes',
            ['activated_by_person_id'],
            unique=False
        )
    
    # اضافه کردن index ترکیبی برای business_id + activated_by_person_id (idempotent)
    if 'idx_warranty_codes_business_person' not in existing_indexes:
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

