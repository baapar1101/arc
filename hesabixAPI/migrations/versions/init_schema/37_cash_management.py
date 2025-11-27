"""جداول cash_registers, petty_cash"""
from alembic import op
import sqlalchemy as sa


def upgrade():
    # جدول cash_registers
    op.create_table(
        'cash_registers',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('name', sa.String(length=255), nullable=False),
        sa.Column('code', sa.String(length=50), nullable=True),
        sa.Column('description', sa.String(length=500), nullable=True),
        sa.Column('currency_id', sa.Integer(), nullable=False),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('is_default', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('payment_switch_number', sa.String(length=100), nullable=True),
        sa.Column('payment_terminal_number', sa.String(length=100), nullable=True),
        sa.Column('merchant_id', sa.String(length=100), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['currency_id'], ['currencies.id'], ondelete='RESTRICT'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('business_id', 'code', name='uq_cash_registers_business_code')
    )
    op.create_index(op.f('ix_cash_registers_business_id'), 'cash_registers', ['business_id'], unique=False)
    op.create_index(op.f('ix_cash_registers_name'), 'cash_registers', ['name'], unique=False)
    op.create_index(op.f('ix_cash_registers_code'), 'cash_registers', ['code'], unique=False)
    op.create_index(op.f('ix_cash_registers_currency_id'), 'cash_registers', ['currency_id'], unique=False)

    # جدول petty_cash
    op.create_table(
        'petty_cash',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('name', sa.String(length=255), nullable=False),
        sa.Column('code', sa.String(length=50), nullable=True),
        sa.Column('description', sa.String(length=500), nullable=True),
        sa.Column('currency_id', sa.Integer(), nullable=False),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('is_default', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['currency_id'], ['currencies.id'], ondelete='RESTRICT'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('business_id', 'code', name='uq_petty_cash_business_code')
    )
    op.create_index(op.f('ix_petty_cash_business_id'), 'petty_cash', ['business_id'], unique=False)
    op.create_index(op.f('ix_petty_cash_name'), 'petty_cash', ['name'], unique=False)
    op.create_index(op.f('ix_petty_cash_code'), 'petty_cash', ['code'], unique=False)
    op.create_index(op.f('ix_petty_cash_currency_id'), 'petty_cash', ['currency_id'], unique=False)


def downgrade():
    op.drop_index(op.f('ix_petty_cash_currency_id'), table_name='petty_cash')
    op.drop_index(op.f('ix_petty_cash_code'), table_name='petty_cash')
    op.drop_index(op.f('ix_petty_cash_name'), table_name='petty_cash')
    op.drop_index(op.f('ix_petty_cash_business_id'), table_name='petty_cash')
    op.drop_table('petty_cash')
    
    op.drop_index(op.f('ix_cash_registers_currency_id'), table_name='cash_registers')
    op.drop_index(op.f('ix_cash_registers_code'), table_name='cash_registers')
    op.drop_index(op.f('ix_cash_registers_name'), table_name='cash_registers')
    op.drop_index(op.f('ix_cash_registers_business_id'), table_name='cash_registers')
    op.drop_table('cash_registers')

