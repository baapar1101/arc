"""جدول fiscal_years"""
from alembic import op
import sqlalchemy as sa


def upgrade():
    op.create_table(
        'fiscal_years',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('title', sa.String(length=255), nullable=False),
        sa.Column('start_date', sa.Date(), nullable=False),
        sa.Column('end_date', sa.Date(), nullable=False),
        sa.Column('is_last', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_fiscal_years_business_id'), 'fiscal_years', ['business_id'], unique=False)


def downgrade():
    op.drop_index(op.f('ix_fiscal_years_business_id'), table_name='fiscal_years')
    op.drop_table('fiscal_years')

