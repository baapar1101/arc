"""add warehouse contact fields

Revision ID: 20250120_000001_add_warehouse_contact_fields
Revises: c772753c99b0
Create Date: 2025-01-20 00:00:01.000000

"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect


# revision identifiers, used by Alembic.
revision = '20250120_000001_add_warehouse_contact_fields'
down_revision = '20250119_000001_add_check_reconciliations_tables'
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = inspect(bind)
    
    # Check if warehouses table exists
    if inspector.has_table('warehouses'):
        cols = {c['name'] for c in inspector.get_columns('warehouses')}
        
        with op.batch_alter_table('warehouses') as batch_op:
            if 'warehouse_keeper' not in cols:
                batch_op.add_column(sa.Column('warehouse_keeper', sa.String(length=255), nullable=True, comment='نام انباردار'))
            if 'phone' not in cols:
                batch_op.add_column(sa.Column('phone', sa.String(length=32), nullable=True, comment='تلفن'))
            if 'address' not in cols:
                batch_op.add_column(sa.Column('address', sa.Text(), nullable=True, comment='آدرس'))
            if 'postal_code' not in cols:
                batch_op.add_column(sa.Column('postal_code', sa.String(length=16), nullable=True, comment='کد پستی'))


def downgrade() -> None:
    bind = op.get_bind()
    inspector = inspect(bind)
    
    # Check if warehouses table exists
    if inspector.has_table('warehouses'):
        cols = {c['name'] for c in inspector.get_columns('warehouses')}
        
        with op.batch_alter_table('warehouses') as batch_op:
            if 'postal_code' in cols:
                try:
                    batch_op.drop_column('postal_code')
                except Exception:
                    pass
            if 'address' in cols:
                try:
                    batch_op.drop_column('address')
                except Exception:
                    pass
            if 'phone' in cols:
                try:
                    batch_op.drop_column('phone')
                except Exception:
                    pass
            if 'warehouse_keeper' in cols:
                try:
                    batch_op.drop_column('warehouse_keeper')
                except Exception:
                    pass

