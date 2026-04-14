from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect

# revision identifiers, used by Alembic.
revision = '20250928_000023_remove_person_is_active_force'
down_revision = '4b2ea782bcb3'
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = inspect(bind)
    tables = set(inspector.get_table_names())

    # Drop is_active from persons if exists
    if 'persons' in tables:
        columns = {col['name'] for col in inspector.get_columns('persons')}
        if 'is_active' in columns:
            with op.batch_alter_table('persons') as batch_op:
                try:
                    batch_op.drop_column('is_active')
                except Exception:
                    pass

    # Drop is_active from person_bank_accounts if exists
    if 'person_bank_accounts' in tables:
        columns = {col['name'] for col in inspector.get_columns('person_bank_accounts')}
        if 'is_active' in columns:
            with op.batch_alter_table('person_bank_accounts') as batch_op:
                try:
                    batch_op.drop_column('is_active')
                except Exception:
                    pass


def downgrade() -> None:
    # Recreate columns with safe defaults if needed
    bind = op.get_bind()
    inspector = inspect(bind)
    tables = set(inspector.get_table_names())

    if 'persons' in tables:
        columns = {col['name'] for col in inspector.get_columns('persons')}
        if 'is_active' not in columns:
            with op.batch_alter_table('persons') as batch_op:
                batch_op.add_column(sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('1')))

    if 'person_bank_accounts' in tables:
        columns = {col['name'] for col in inspector.get_columns('person_bank_accounts')}
        if 'is_active' not in columns:
            with op.batch_alter_table('person_bank_accounts') as batch_op:
                batch_op.add_column(sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('1')))


