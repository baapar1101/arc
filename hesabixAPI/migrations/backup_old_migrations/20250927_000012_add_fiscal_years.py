from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect


# revision identifiers, used by Alembic.
revision = '20250927_000012_add_fiscal_years'
down_revision = '20250926_000011_drop_active'
branch_labels = None
depends_on = ('20250117_000003',)


def upgrade() -> None:
	bind = op.get_bind()
	inspector = inspect(bind)

	# Create fiscal_years table if not exists
	if 'fiscal_years' not in inspector.get_table_names():
		op.create_table(
			'fiscal_years',
			sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
			sa.Column('business_id', sa.Integer(), nullable=False),
			sa.Column('title', sa.String(length=255), nullable=False),
			sa.Column('start_date', sa.Date(), nullable=False),
			sa.Column('end_date', sa.Date(), nullable=False),
			sa.Column('is_last', sa.Boolean(), nullable=False, server_default=sa.text('0')),
			sa.Column('created_at', sa.DateTime(), nullable=False),
			sa.Column('updated_at', sa.DateTime(), nullable=False),
			sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
			sa.PrimaryKeyConstraint('id')
		)

	# Indexes if not exists
	existing_indexes = {idx['name'] for idx in inspector.get_indexes('fiscal_years')} if 'fiscal_years' in inspector.get_table_names() else set()
	if 'ix_fiscal_years_business_id' not in existing_indexes:
		op.create_index('ix_fiscal_years_business_id', 'fiscal_years', ['business_id'])
	if 'ix_fiscal_years_title' not in existing_indexes:
		op.create_index('ix_fiscal_years_title', 'fiscal_years', ['title'])


def downgrade() -> None:
	op.drop_index('ix_fiscal_years_title', table_name='fiscal_years')
	op.drop_index('ix_fiscal_years_business_id', table_name='fiscal_years')
	op.drop_table('fiscal_years')


