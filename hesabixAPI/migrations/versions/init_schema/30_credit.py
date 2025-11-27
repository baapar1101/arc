"""جداول business_credit_settings, installment_plan_templates"""
from alembic import op
import sqlalchemy as sa


def upgrade():
    # جدول business_credit_settings
    op.create_table(
        'business_credit_settings',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('is_enabled', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('default_limit', sa.Numeric(precision=14, scale=2), nullable=True),
        sa.Column('grace_days', sa.Integer(), nullable=True),
        sa.Column('late_fee_rate', sa.Numeric(precision=8, scale=4), nullable=True),
        sa.Column('auto_block_after_days', sa.Integer(), nullable=True),
        sa.Column('strategy', sa.String(length=30), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('business_id', name='uq_credit_settings_business')
    )
    op.create_index(op.f('ix_business_credit_settings_business_id'), 'business_credit_settings', ['business_id'], unique=False)

    # جدول installment_plan_templates
    op.create_table(
        'installment_plan_templates',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('name', sa.String(length=120), nullable=False),
        sa.Column('method', sa.String(length=20), nullable=False, server_default='flat'),
        sa.Column('num_installments', sa.Integer(), nullable=False),
        sa.Column('period_days', sa.Integer(), nullable=False, server_default='30'),
        sa.Column('down_payment_percent', sa.Numeric(precision=8, scale=4), nullable=True),
        sa.Column('interest_rate', sa.Numeric(precision=8, scale=4), nullable=True),
        sa.Column('late_fee_rate', sa.Numeric(precision=8, scale=4), nullable=True),
        sa.Column('issue_fee', sa.Numeric(precision=14, scale=2), nullable=True),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('business_id', 'name', name='uq_installment_plan_name_per_business')
    )
    op.create_index(op.f('ix_installment_plan_templates_business_id'), 'installment_plan_templates', ['business_id'], unique=False)


def downgrade():
    op.drop_index(op.f('ix_installment_plan_templates_business_id'), table_name='installment_plan_templates')
    op.drop_table('installment_plan_templates')
    
    op.drop_index(op.f('ix_business_credit_settings_business_id'), table_name='business_credit_settings')
    op.drop_table('business_credit_settings')

