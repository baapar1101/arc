from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '20250926_000010_add_person_code_and_types'
down_revision = '20250916_000002'
branch_labels = None
depends_on = None


def upgrade() -> None:
	with op.batch_alter_table('persons') as batch_op:
		batch_op.add_column(sa.Column('code', sa.Integer(), nullable=True))
		batch_op.add_column(sa.Column('person_types', sa.Text(), nullable=True))
		batch_op.create_unique_constraint('uq_persons_business_code', ['business_id', 'code'])


def downgrade() -> None:
	with op.batch_alter_table('persons') as batch_op:
		batch_op.drop_constraint('uq_persons_business_code', type_='unique')
		batch_op.drop_column('person_types')
		batch_op.drop_column('code')
