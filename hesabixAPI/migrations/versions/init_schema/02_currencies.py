"""جداول currencies و business_currencies"""
from alembic import op
import sqlalchemy as sa


def upgrade():
    # جدول currencies
    op.create_table(
        'currencies',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('name', sa.String(length=100), nullable=False),
        sa.Column('title', sa.String(length=100), nullable=False),
        sa.Column('symbol', sa.String(length=16), nullable=False),
        sa.Column('code', sa.String(length=16), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('name', name='uq_currencies_name'),
        sa.UniqueConstraint('code', name='uq_currencies_code')
    )
    op.create_index(op.f('ix_currencies_name'), 'currencies', ['name'], unique=False)

    # جدول business_currencies
    op.create_table(
        'business_currencies',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('currency_id', sa.Integer(), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['currency_id'], ['currencies.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('business_id', 'currency_id', name='uq_business_currencies_business_currency')
    )
    op.create_index(op.f('ix_business_currencies_business_id'), 'business_currencies', ['business_id'], unique=False)
    op.create_index(op.f('ix_business_currencies_currency_id'), 'business_currencies', ['currency_id'], unique=False)


def downgrade():
    op.drop_index(op.f('ix_business_currencies_currency_id'), table_name='business_currencies')
    op.drop_index(op.f('ix_business_currencies_business_id'), table_name='business_currencies')
    op.drop_table('business_currencies')
    
    op.drop_index(op.f('ix_currencies_name'), table_name='currencies')
    op.drop_table('currencies')

