from __future__ import annotations

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20250927_000016_add_accounts_table'
down_revision = '20250927_000015_add_document_lines_table'
branch_labels = None
depends_on = None


def upgrade() -> None:
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
		mysql_charset='utf8mb4'
	)

	op.create_unique_constraint('uq_accounts_business_code', 'accounts', ['business_id', 'code'])
	op.create_index('ix_accounts_name', 'accounts', ['name'])
	op.create_index('ix_accounts_business_id', 'accounts', ['business_id'])
	op.create_index('ix_accounts_parent_id', 'accounts', ['parent_id'])


def downgrade() -> None:
	op.drop_index('ix_accounts_parent_id', table_name='accounts')
	op.drop_index('ix_accounts_business_id', table_name='accounts')
	op.drop_index('ix_accounts_name', table_name='accounts')
	op.drop_constraint('uq_accounts_business_code', 'accounts', type_='unique')
	op.drop_table('accounts')


