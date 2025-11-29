"""اضافه کردن فیلدهای soft delete به جدول businesses

revision: 20250117_000001_add_soft_delete_to_businesses
down_revision: 20250116_000002
branch_labels: None
depends_on: None

این میگریشن فیلدهای soft delete را به جدول businesses اضافه می‌کند.
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20250117_000001'
down_revision = '20250116_000002'
branch_labels = None
depends_on = None


def upgrade():
    # اضافه کردن فیلدهای soft delete
    op.add_column('businesses', sa.Column('deleted_at', sa.DateTime(), nullable=True))
    op.add_column('businesses', sa.Column('deletion_requested_at', sa.DateTime(), nullable=True))
    op.add_column('businesses', sa.Column('deletion_requested_by', sa.Integer(), nullable=True))
    op.add_column('businesses', sa.Column('deletion_reason', sa.Text(), nullable=True))
    op.add_column('businesses', sa.Column('auto_delete_at', sa.DateTime(), nullable=True))
    
    # ایجاد ایندکس برای فیلدهای deleted_at و auto_delete_at
    op.create_index(op.f('ix_businesses_deleted_at'), 'businesses', ['deleted_at'], unique=False)
    op.create_index(op.f('ix_businesses_auto_delete_at'), 'businesses', ['auto_delete_at'], unique=False)
    
    # اضافه کردن ForeignKey برای deletion_requested_by
    op.create_foreign_key(
        'fk_businesses_deletion_requested_by_users',
        'businesses', 'users',
        ['deletion_requested_by'], ['id'],
        ondelete='SET NULL'
    )


def downgrade():
    # حذف ForeignKey
    op.drop_constraint('fk_businesses_deletion_requested_by_users', 'businesses', type_='foreignkey')
    
    # حذف ایندکس‌ها
    op.drop_index(op.f('ix_businesses_auto_delete_at'), table_name='businesses')
    op.drop_index(op.f('ix_businesses_deleted_at'), table_name='businesses')
    
    # حذف فیلدها
    op.drop_column('businesses', 'auto_delete_at')
    op.drop_column('businesses', 'deletion_reason')
    op.drop_column('businesses', 'deletion_requested_by')
    op.drop_column('businesses', 'deletion_requested_at')
    op.drop_column('businesses', 'deleted_at')

