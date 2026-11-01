"""Retain reviewed source deletions and their complete financial before-images."""
from alembic import op
import sqlalchemy as sa
revision='20261101_000001_sepidar_reconciliation'
down_revision='20261023_000005_addon_postings'
branch_labels=None
depends_on=None

def upgrade():
    if 'retired_at' not in {c['name'] for c in sa.inspect(op.get_bind()).get_columns('sepidar_native_maps')}:
        op.add_column('sepidar_native_maps',sa.Column('retired_at',sa.DateTime(),nullable=True))
    from adapters.db.models.sepidar_live_import import SepidarReconciliationAudit
    SepidarReconciliationAudit.__table__.create(op.get_bind(),checkfirst=True)

def downgrade():
    raise RuntimeError('Reconciliation history must be retained; roll back code, not financial audit data.')
