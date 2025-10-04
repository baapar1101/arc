"""add cash_registers table

Revision ID: 20251003_000201_add_cash_registers_table
Revises: 
Create Date: 2025-10-03 00:02:01.000001

"""

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20251003_000201_add_cash_registers_table'
down_revision = 'a1443c153b47'
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if 'cash_registers' not in inspector.get_table_names():
        op.create_table(
            'cash_registers',
            sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column('business_id', sa.Integer(), sa.ForeignKey('businesses.id', ondelete='CASCADE'), nullable=False),
            sa.Column('code', sa.String(length=50), nullable=True),
            sa.Column('description', sa.String(length=500), nullable=True),
            sa.Column('currency_id', sa.Integer(), sa.ForeignKey('currencies.id', ondelete='RESTRICT'), nullable=False),
            sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('1')),
            sa.Column('is_default', sa.Boolean(), nullable=False, server_default=sa.text('0')),
            sa.Column('payment_switch_number', sa.String(length=100), nullable=True),
            sa.Column('payment_terminal_number', sa.String(length=100), nullable=True),
            sa.Column('merchant_id', sa.String(length=100), nullable=True),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.Column('updated_at', sa.DateTime(), nullable=False),
            sa.UniqueConstraint('business_id', 'code', name='uq_cash_registers_business_code'),
        )
        try:
            op.create_index('ix_cash_registers_business_id', 'cash_registers', ['business_id'])
            op.create_index('ix_cash_registers_currency_id', 'cash_registers', ['currency_id'])
            op.create_index('ix_cash_registers_is_active', 'cash_registers', ['is_active'])
        except Exception:
            pass


def downgrade() -> None:
	op.drop_index('ix_cash_registers_is_active', table_name='cash_registers')
	op.drop_index('ix_cash_registers_currency_id', table_name='cash_registers')
	op.drop_index('ix_cash_registers_business_id', table_name='cash_registers')
	op.drop_table('cash_registers')


