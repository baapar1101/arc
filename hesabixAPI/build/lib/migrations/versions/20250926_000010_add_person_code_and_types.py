from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect

# revision identifiers, used by Alembic.
revision = '20250926_000010_add_person_code_and_types'
down_revision = '20250916_000002'
branch_labels = None
depends_on = None


def upgrade() -> None:
	bind = op.get_bind()
	inspector = inspect(bind)
	# اگر جدول persons وجود ندارد، این مایگریشن را نادیده بگیر
	if 'persons' not in inspector.get_table_names():
		return
	cols = {c['name'] for c in inspector.get_columns('persons')}
	with op.batch_alter_table('persons') as batch_op:
		if 'code' not in cols:
			batch_op.add_column(sa.Column('code', sa.Integer(), nullable=True))
		if 'person_types' not in cols:
			batch_op.add_column(sa.Column('person_types', sa.Text(), nullable=True))
		# unique constraint if not exists
		existing_uniques = {uc['name'] for uc in inspector.get_unique_constraints('persons')}
		if 'uq_persons_business_code' not in existing_uniques:
			batch_op.create_unique_constraint('uq_persons_business_code', ['business_id', 'code'])


def downgrade() -> None:
	bind = op.get_bind()
	inspector = inspect(bind)
	if 'persons' not in inspector.get_table_names():
		return
	with op.batch_alter_table('persons') as batch_op:
		try:
			batch_op.drop_constraint('uq_persons_business_code', type_='unique')
		except Exception:
			pass
		try:
			batch_op.drop_column('person_types')
		except Exception:
			pass
		try:
			batch_op.drop_column('code')
		except Exception:
			pass
