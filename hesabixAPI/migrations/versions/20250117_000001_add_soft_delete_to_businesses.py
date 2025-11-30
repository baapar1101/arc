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
from sqlalchemy import inspect


# revision identifiers, used by Alembic.
revision = '20250117_000001'
down_revision = '20250116_000002'
branch_labels = None
depends_on = None


def upgrade():
    """اضافه کردن فیلدهای soft delete به جدول businesses در صورت عدم وجود"""
    conn = op.get_bind()
    inspector = inspect(conn)
    
    # بررسی وجود ستون‌ها
    columns = [col['name'] for col in inspector.get_columns('businesses')]
    
    # اضافه کردن فیلدهای soft delete در صورت عدم وجود
    if 'deleted_at' not in columns:
    op.add_column('businesses', sa.Column('deleted_at', sa.DateTime(), nullable=True))
    if 'deletion_requested_at' not in columns:
    op.add_column('businesses', sa.Column('deletion_requested_at', sa.DateTime(), nullable=True))
    if 'deletion_requested_by' not in columns:
    op.add_column('businesses', sa.Column('deletion_requested_by', sa.Integer(), nullable=True))
    if 'deletion_reason' not in columns:
    op.add_column('businesses', sa.Column('deletion_reason', sa.Text(), nullable=True))
    if 'auto_delete_at' not in columns:
    op.add_column('businesses', sa.Column('auto_delete_at', sa.DateTime(), nullable=True))
    
    # بررسی وجود ایندکس‌ها
    indexes = [idx['name'] for idx in inspector.get_indexes('businesses')]
    if 'ix_businesses_deleted_at' not in indexes:
    op.create_index(op.f('ix_businesses_deleted_at'), 'businesses', ['deleted_at'], unique=False)
    if 'ix_businesses_auto_delete_at' not in indexes:
    op.create_index(op.f('ix_businesses_auto_delete_at'), 'businesses', ['auto_delete_at'], unique=False)
    
    # بررسی وجود ForeignKey
    foreign_keys = [fk['name'] for fk in inspector.get_foreign_keys('businesses')]
    if 'fk_businesses_deletion_requested_by_users' not in foreign_keys:
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

