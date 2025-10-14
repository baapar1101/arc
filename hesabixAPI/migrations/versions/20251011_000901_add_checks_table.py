from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = '20251011_000901_add_checks_table'
down_revision: Union[str, None] = '1f0abcdd7300'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
	# ایجاد ایمن جدول و ایندکس‌ها در صورت نبود
	bind = op.get_bind()
	inspector = sa.inspect(bind)

	# ایجاد type در صورت نیاز
	try:
		op.execute("SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_NAME='checks' LIMIT 1")
	except Exception:
		pass

	if 'checks' not in inspector.get_table_names():
		# Enum برای نوع چک
		try:
			# برخی درایورها ایجاد Enum را قبل از استفاده می‌خواهند
			sa.Enum('received', 'transferred', name='check_type')
		except Exception:
			pass
		op.create_table(
			'checks',
			sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
			sa.Column('business_id', sa.Integer(), sa.ForeignKey('businesses.id', ondelete='CASCADE'), nullable=False),
			sa.Column('type', sa.Enum('received', 'transferred', name='check_type'), nullable=False),
			sa.Column('person_id', sa.Integer(), sa.ForeignKey('persons.id', ondelete='SET NULL'), nullable=True),
			sa.Column('issue_date', sa.DateTime(), nullable=False),
			sa.Column('due_date', sa.DateTime(), nullable=False),
			sa.Column('check_number', sa.String(length=50), nullable=False),
			sa.Column('sayad_code', sa.String(length=16), nullable=True),
			sa.Column('bank_name', sa.String(length=255), nullable=True),
			sa.Column('branch_name', sa.String(length=255), nullable=True),
			sa.Column('amount', sa.Numeric(18, 2), nullable=False),
			sa.Column('currency_id', sa.Integer(), sa.ForeignKey('currencies.id', ondelete='RESTRICT'), nullable=False),
			sa.Column('created_at', sa.DateTime(), nullable=False),
			sa.Column('updated_at', sa.DateTime(), nullable=False),
			sa.UniqueConstraint('business_id', 'check_number', name='uq_checks_business_check_number'),
			sa.UniqueConstraint('business_id', 'sayad_code', name='uq_checks_business_sayad_code'),
		)

	# ایجاد ایندکس‌ها اگر وجود ندارند
	try:
		existing_indexes = {idx['name'] for idx in inspector.get_indexes('checks')}
		if 'ix_checks_business_type' not in existing_indexes:
			op.create_index('ix_checks_business_type', 'checks', ['business_id', 'type'])
		if 'ix_checks_business_person' not in existing_indexes:
			op.create_index('ix_checks_business_person', 'checks', ['business_id', 'person_id'])
		if 'ix_checks_business_issue_date' not in existing_indexes:
			op.create_index('ix_checks_business_issue_date', 'checks', ['business_id', 'issue_date'])
		if 'ix_checks_business_due_date' not in existing_indexes:
			op.create_index('ix_checks_business_due_date', 'checks', ['business_id', 'due_date'])
	except Exception:
		pass


def downgrade() -> None:
	# Drop indices
	op.drop_index('ix_checks_business_due_date', table_name='checks')
	op.drop_index('ix_checks_business_issue_date', table_name='checks')
	op.drop_index('ix_checks_business_person', table_name='checks')
	op.drop_index('ix_checks_business_type', table_name='checks')
	# Drop table
	op.drop_table('checks')
	# Drop enum type (if supported)
	try:
		op.execute("DROP TYPE check_type")
	except Exception:
		pass
