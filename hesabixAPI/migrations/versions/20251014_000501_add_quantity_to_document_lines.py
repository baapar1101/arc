from __future__ import annotations

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20251014_000501_add_quantity_to_document_lines'
down_revision = '20251014_000401_add_payment_refs_to_document_lines'
branch_labels = None
depends_on = None


def upgrade() -> None:
	with op.batch_alter_table('document_lines') as batch_op:
		batch_op.add_column(sa.Column('quantity', sa.Numeric(18, 6), nullable=True, server_default=sa.text('0')))


def downgrade() -> None:
	with op.batch_alter_table('document_lines') as batch_op:
		batch_op.drop_column('quantity')


