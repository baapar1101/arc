from __future__ import annotations

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20250927_000013_add_currencies_and_business_currencies'
down_revision = '20250927_000012_add_fiscal_years_table'
branch_labels = None
depends_on = None


def upgrade() -> None:
	# Create currencies table
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
		mysql_charset='utf8mb4'
	)
	# Unique constraints and indexes
	op.create_unique_constraint('uq_currencies_name', 'currencies', ['name'])
	op.create_unique_constraint('uq_currencies_code', 'currencies', ['code'])
	op.create_index('ix_currencies_name', 'currencies', ['name'])

	# Create business_currencies association table
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
		mysql_charset='utf8mb4'
	)

	# Add default_currency_id to businesses if not exists
	bind = op.get_bind()
	inspector = sa.inspect(bind)
	if 'businesses' in inspector.get_table_names():
		cols = {c['name'] for c in inspector.get_columns('businesses')}
		if 'default_currency_id' not in cols:
			with op.batch_alter_table('businesses') as batch_op:
				batch_op.add_column(sa.Column('default_currency_id', sa.Integer(), nullable=True))
				batch_op.create_foreign_key('fk_businesses_default_currency', 'currencies', ['default_currency_id'], ['id'], ondelete='RESTRICT')
				batch_op.create_index('ix_businesses_default_currency_id', ['default_currency_id'])
	# Unique and indexes for association
	op.create_unique_constraint('uq_business_currencies_business_currency', 'business_currencies', ['business_id', 'currency_id'])
	op.create_index('ix_business_currencies_business_id', 'business_currencies', ['business_id'])
	op.create_index('ix_business_currencies_currency_id', 'business_currencies', ['currency_id'])


def downgrade() -> None:
	# Drop index/foreign key/column default_currency_id if exists
	with op.batch_alter_table('businesses') as batch_op:
		try:
			batch_op.drop_index('ix_businesses_default_currency_id')
		except Exception:
			pass
		try:
			batch_op.drop_constraint('fk_businesses_default_currency', type_='foreignkey')
		except Exception:
			pass
		try:
			batch_op.drop_column('default_currency_id')
		except Exception:
			pass
	op.drop_index('ix_business_currencies_currency_id', table_name='business_currencies')
	op.drop_index('ix_business_currencies_business_id', table_name='business_currencies')
	op.drop_constraint('uq_business_currencies_business_currency', 'business_currencies', type_='unique')
	op.drop_table('business_currencies')

	op.drop_index('ix_currencies_name', table_name='currencies')
	op.drop_constraint('uq_currencies_code', 'currencies', type_='unique')
	op.drop_constraint('uq_currencies_name', 'currencies', type_='unique')
	op.drop_table('currencies')


