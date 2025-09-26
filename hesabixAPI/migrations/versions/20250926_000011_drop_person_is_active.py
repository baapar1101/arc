from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '20250926_000011_drop_person_is_active'
down_revision = '20250926_000010_add_person_code_and_types'
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table('persons') as batch_op:
        try:
            batch_op.drop_column('is_active')
        except Exception:
            pass
    with op.batch_alter_table('person_bank_accounts') as batch_op:
        try:
            batch_op.drop_column('is_active')
        except Exception:
            pass


def downgrade() -> None:
    with op.batch_alter_table('persons') as batch_op:
        batch_op.add_column(sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('1')))
    with op.batch_alter_table('person_bank_accounts') as batch_op:
        batch_op.add_column(sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('1')))
