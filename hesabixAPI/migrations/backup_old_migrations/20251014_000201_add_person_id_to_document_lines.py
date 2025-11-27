from __future__ import annotations

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20251014_000201_add_person_id_to_document_lines'
down_revision = '20250927_000017_add_account_id_to_document_lines'
branch_labels = None
depends_on = None


def upgrade() -> None:
	with op.batch_alter_table('document_lines') as batch_op:
		batch_op.add_column(sa.Column('person_id', sa.Integer(), nullable=True))
		batch_op.create_foreign_key('fk_document_lines_person_id_persons', 'persons', ['person_id'], ['id'], ondelete='SET NULL')
		batch_op.create_index('ix_document_lines_person_id', ['person_id'])


def downgrade() -> None:
	with op.batch_alter_table('document_lines') as batch_op:
		batch_op.drop_index('ix_document_lines_person_id')
		batch_op.drop_constraint('fk_document_lines_person_id_persons', type_='foreignkey')
		batch_op.drop_column('person_id')


