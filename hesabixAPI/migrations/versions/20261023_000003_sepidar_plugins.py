"""Opt-in Sepidar plugin data bridge."""
from alembic import op
import sqlalchemy as sa
revision='20261023_000003_sepidar_plugins'
down_revision='20261023_000002_sepidar_operations'
branch_labels=None
depends_on=None

def upgrade():
    op.add_column('sepidar_import_settings',sa.Column('plugins_enabled',sa.Boolean(),nullable=False,server_default=sa.false()))

def downgrade():
    op.drop_column('sepidar_import_settings','plugins_enabled')
