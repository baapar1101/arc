from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '20250119_000001_add_check_reconciliations_tables'
down_revision = '20251119_000001_add_person_share_links'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # ایجاد جدول check_reconciliations
    op.create_table(
        'check_reconciliations',
        sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column('business_id', sa.Integer(), sa.ForeignKey('businesses.id', ondelete='CASCADE'), nullable=False),
        sa.Column('name', sa.String(length=255), nullable=False),
        sa.Column('base_date', sa.DateTime(), nullable=False),
        sa.Column('calculated_average_days', sa.Numeric(10, 2), nullable=False),
        sa.Column('calculated_date', sa.DateTime(), nullable=False),
        sa.Column('total_amount', sa.Numeric(18, 2), nullable=False),
        sa.Column('check_count', sa.Integer(), nullable=False),
        sa.Column('currency_id', sa.Integer(), sa.ForeignKey('currencies.id', ondelete='RESTRICT'), nullable=False),
        sa.Column('description', sa.String(length=1000), nullable=True),
        sa.Column('created_by_user_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='RESTRICT'), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
    )
    
    # ایجاد ایندکس‌ها برای check_reconciliations
    op.create_index('ix_check_reconciliations_business', 'check_reconciliations', ['business_id'])
    op.create_index('ix_check_reconciliations_created_at', 'check_reconciliations', ['created_at'])
    
    # ایجاد جدول check_reconciliation_items
    op.create_table(
        'check_reconciliation_items',
        sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column('reconciliation_id', sa.Integer(), sa.ForeignKey('check_reconciliations.id', ondelete='CASCADE'), nullable=False),
        sa.Column('check_id', sa.Integer(), sa.ForeignKey('checks.id', ondelete='CASCADE'), nullable=False),
        sa.Column('days_to_maturity', sa.Integer(), nullable=False),
        sa.Column('weighted_value', sa.Numeric(18, 2), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=False),
    )
    
    # ایجاد ایندکس‌ها برای check_reconciliation_items
    op.create_index('ix_check_reconciliation_items_reconciliation', 'check_reconciliation_items', ['reconciliation_id'])
    op.create_index('ix_check_reconciliation_items_check', 'check_reconciliation_items', ['check_id'])


def downgrade() -> None:
    # Drop indices
    op.drop_index('ix_check_reconciliation_items_check', table_name='check_reconciliation_items')
    op.drop_index('ix_check_reconciliation_items_reconciliation', table_name='check_reconciliation_items')
    op.drop_index('ix_check_reconciliations_created_at', table_name='check_reconciliations')
    op.drop_index('ix_check_reconciliations_business', table_name='check_reconciliations')
    
    # Drop tables
    op.drop_table('check_reconciliation_items')
    op.drop_table('check_reconciliations')

