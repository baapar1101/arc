"""جدول accounts"""
from alembic import op
import sqlalchemy as sa


def upgrade():
    op.create_table(
        'accounts',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('name', sa.String(length=255), nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=True),
        sa.Column('account_type', sa.String(length=50), nullable=False),
        sa.Column('code', sa.String(length=50), nullable=False),
        sa.Column('parent_id', sa.Integer(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['parent_id'], ['accounts.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('business_id', 'code', name='uq_accounts_business_code')
    )
    op.create_index(op.f('ix_accounts_name'), 'accounts', ['name'], unique=False)
    op.create_index(op.f('ix_accounts_business_id'), 'accounts', ['business_id'], unique=False)
    op.create_index(op.f('ix_accounts_parent_id'), 'accounts', ['parent_id'], unique=False)


def downgrade():
    op.drop_index(op.f('ix_accounts_parent_id'), table_name='accounts')
    op.drop_index(op.f('ix_accounts_business_id'), table_name='accounts')
    op.drop_index(op.f('ix_accounts_name'), table_name='accounts')
    op.drop_table('accounts')

