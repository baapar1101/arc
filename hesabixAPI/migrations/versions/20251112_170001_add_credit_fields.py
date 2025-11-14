"""add credit fields to persons and businesses

Revision ID: 20251112_170001_add_credit_fields
Revises: 20251110_101500_add_marketplace_tables
Create Date: 2025-11-12 17:00:01.000001

"""

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '20251112_170001_add_credit_fields'
down_revision = '20251110_101500'
branch_labels = None
depends_on = None


def _has_column(inspector, table_name: str, column_name: str) -> bool:
	tables = inspector.get_table_names()
	if table_name not in tables:
		return False
	cols = [c['name'] for c in inspector.get_columns(table_name)]
	return column_name in cols


def upgrade() -> None:
	bind = op.get_bind()
	inspector = sa.inspect(bind)

	# persons: credit_limit, credit_check_enabled
	if not _has_column(inspector, 'persons', 'credit_limit'):
		try:
			op.add_column('persons', sa.Column('credit_limit', sa.Numeric(14, 2), nullable=True, comment="سقف اعتبار شخص"))
		except Exception:
			pass
	if not _has_column(inspector, 'persons', 'credit_check_enabled'):
		try:
			op.add_column('persons', sa.Column('credit_check_enabled', sa.Boolean(), nullable=True, comment="فعال بودن بررسی اعتبار برای شخص (خالی: تبعیت از تنظیمات کسب‌وکار)"))
		except Exception:
			pass

	# businesses: default_credit_limit, check_credit_enabled_by_default
	if not _has_column(inspector, 'businesses', 'default_credit_limit'):
		try:
			op.add_column('businesses', sa.Column('default_credit_limit', sa.Numeric(14, 2), nullable=True, comment="سقف اعتبار پیشفرض اشخاص"))
		except Exception:
			pass
	if not _has_column(inspector, 'businesses', 'check_credit_enabled_by_default'):
		try:
			op.add_column('businesses', sa.Column('check_credit_enabled_by_default', sa.Boolean(), nullable=False, server_default="0", comment="بررسی اعتبار مشتریان به صورت پیشفرض"))
		except Exception:
			pass


def downgrade() -> None:
	# Safe drops (ignore errors)
	try:
		op.drop_column('persons', 'credit_limit')
	except Exception:
		pass
	try:
		op.drop_column('persons', 'credit_check_enabled')
	except Exception:
		pass
	try:
		op.drop_column('businesses', 'default_credit_limit')
	except Exception:
		pass
	try:
		op.drop_column('businesses', 'check_credit_enabled_by_default')
	except Exception:
		pass


