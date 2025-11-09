"""add system_settings table and seed wallet_base_currency_code

Revision ID: 20251108_231201_add_system_settings
Revises: 20251107_170101_add_invoice_item_lines_and_migrate
Create Date: 2025-11-08 23:12:01.000001

"""

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20251108_231201_add_system_settings'
down_revision = '20251107_170101_add_invoice_item_lines_and_migrate'
branch_labels = None
depends_on = None


def upgrade() -> None:
	bind = op.get_bind()
	inspector = sa.inspect(bind)

	# 1) Create table if not exists
	if 'system_settings' not in inspector.get_table_names():
		op.create_table(
			'system_settings',
			sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
			sa.Column('key', sa.String(length=100), nullable=False, index=True),
			sa.Column('value_string', sa.String(length=255), nullable=True),
			sa.Column('value_int', sa.Integer(), nullable=True),
			sa.Column('value_json', sa.Text(), nullable=True),
			sa.Column('created_at', sa.DateTime(), nullable=False),
			sa.Column('updated_at', sa.DateTime(), nullable=False),
			sa.UniqueConstraint('key', name='uq_system_settings_key'),
		)
		try:
			op.create_index('ix_system_settings_key', 'system_settings', ['key'])
		except Exception:
			pass

	# 2) Seed default wallet base currency code to IRR if not set
	# prefer code instead of id to avoid id dependency
	try:
		conn = op.get_bind()
		# check if exists
		exists = conn.execute(sa.text("SELECT 1 FROM system_settings WHERE `key` = :k LIMIT 1"), {"k": "wallet_base_currency_code"}).fetchone()
		if not exists:
			conn.execute(
				sa.text(
					"""
					INSERT INTO system_settings (`key`, value_string, created_at, updated_at)
					VALUES (:k, :v, NOW(), NOW())
					"""
				),
				{"k": "wallet_base_currency_code", "v": "IRR"},
			)
	except Exception:
		# non-fatal
		pass


def downgrade() -> None:
	try:
		op.drop_index('ix_system_settings_key', table_name='system_settings')
	except Exception:
		pass
	op.drop_table('system_settings')


