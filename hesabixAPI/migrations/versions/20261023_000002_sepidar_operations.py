"""Opt-in native inventory, costing and settlements projection."""
from alembic import op
import sqlalchemy as sa
revision = '20261023_000002_sepidar_operations'
down_revision = '20261023_000001_sepidar_native'
branch_labels = None
depends_on = None
def upgrade():
    op.add_column('sepidar_import_settings',sa.Column('operations_enabled',sa.Boolean(),nullable=False,server_default=sa.false()))
def downgrade():
    op.drop_column('sepidar_import_settings','operations_enabled')
