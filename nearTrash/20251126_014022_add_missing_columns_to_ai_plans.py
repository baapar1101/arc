"""add missing columns to ai_plans

Revision ID: 20251126_014022_add_missing_columns_to_ai_plans
Revises: cc07f77111f2
Create Date: 2025-11-26 01:40:22.000000

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '20251126_014022_add_missing_columns_to_ai_plans'
down_revision: Union[str, None] = 'cc07f77111f2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    
    # بررسی وجود جدول ai_plans
    if 'ai_plans' not in inspector.get_table_names():
        return
    
    # بررسی وجود ستون‌ها قبل از اضافه کردن
    columns = {c['name'] for c in inspector.get_columns('ai_plans')}
    
    # اضافه کردن ستون tokens_limit در صورت عدم وجود
    if 'tokens_limit' not in columns:
        op.add_column(
            'ai_plans',
            sa.Column('tokens_limit', sa.Integer(), nullable=True)
        )
    
    # اضافه کردن ستون monthly_tokens_limit در صورت عدم وجود
    if 'monthly_tokens_limit' not in columns:
        op.add_column(
            'ai_plans',
            sa.Column('monthly_tokens_limit', sa.Integer(), nullable=True)
        )
    
    # اضافه کردن ستون auto_renew در صورت عدم وجود
    if 'auto_renew' not in columns:
        op.add_column(
            'ai_plans',
            sa.Column('auto_renew', sa.Boolean(), nullable=False, server_default='0')
        )


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    
    # بررسی وجود جدول ai_plans
    if 'ai_plans' not in inspector.get_table_names():
        return
    
    # بررسی وجود ستون‌ها قبل از حذف
    columns = {c['name'] for c in inspector.get_columns('ai_plans')}
    
    # حذف ستون‌ها در صورت وجود
    if 'auto_renew' in columns:
        op.drop_column('ai_plans', 'auto_renew')
    
    if 'monthly_tokens_limit' in columns:
        op.drop_column('ai_plans', 'monthly_tokens_limit')
    
    if 'tokens_limit' in columns:
        op.drop_column('ai_plans', 'tokens_limit')

