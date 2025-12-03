"""افزودن پشتیبانی از حالت دمو/تست برای افزونه‌ها

revision: 20250119_000001_add_trial_support_to_marketplace
down_revision: 20250118_000001
branch_labels: None
depends_on: None

این میگریشن:
1. فیلدهای trial_days و trial_allowed را به marketplace_plugins اضافه می‌کند
2. فیلدهای is_trial و trial_started_at را به business_plugins اضافه می‌کند
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20250119_000001'
down_revision = '20250118_000001'
branch_labels = None
depends_on = None


def upgrade():
    """افزودن فیلدهای trial"""
    conn = op.get_bind()
    
    # بررسی و اضافه کردن فیلدهای trial به marketplace_plugins
    inspector = sa.inspect(conn)
    marketplace_columns = [col['name'] for col in inspector.get_columns('marketplace_plugins')]
    
    if 'trial_days' not in marketplace_columns:
        op.add_column('marketplace_plugins', sa.Column('trial_days', sa.Integer(), nullable=True))
    if 'trial_allowed' not in marketplace_columns:
        op.add_column('marketplace_plugins', sa.Column('trial_allowed', sa.Boolean(), nullable=False, server_default='0'))
    
    # بررسی و اضافه کردن فیلدهای trial به business_plugins
    business_columns = [col['name'] for col in inspector.get_columns('business_plugins')]
    
    if 'is_trial' not in business_columns:
        op.add_column('business_plugins', sa.Column('is_trial', sa.Boolean(), nullable=False, server_default='0'))
    if 'trial_started_at' not in business_columns:
        op.add_column('business_plugins', sa.Column('trial_started_at', sa.DateTime(), nullable=True))


def downgrade():
    """حذف فیلدهای trial"""
    # حذف فیلدهای trial از business_plugins
    op.drop_column('business_plugins', 'trial_started_at')
    op.drop_column('business_plugins', 'is_trial')
    
    # حذف فیلدهای trial از marketplace_plugins
    op.drop_column('marketplace_plugins', 'trial_allowed')
    op.drop_column('marketplace_plugins', 'trial_days')

