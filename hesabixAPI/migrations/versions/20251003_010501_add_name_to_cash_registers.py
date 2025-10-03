"""add name to cash_registers

Revision ID: 20251003_010501_add_name_to_cash_registers
Revises: 20251003_000201_add_cash_registers_table
Create Date: 2025-10-03 01:05:01.000001

"""

from alembic import op
import sqlalchemy as sa


revision = '20251003_010501_add_name_to_cash_registers'
down_revision = '20251003_000201_add_cash_registers_table'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Add column if not exists (MySQL safe): try/except
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    cols = [c['name'] for c in inspector.get_columns('cash_registers')]
    if 'name' not in cols:
        op.add_column('cash_registers', sa.Column('name', sa.String(length=255), nullable=True))
        # Fill default empty name from code or merchant_id to avoid nulls
        try:
            conn.execute(sa.text("UPDATE cash_registers SET name = COALESCE(name, code)"))
        except Exception:
            pass
        # Alter to not null
        with op.batch_alter_table('cash_registers') as batch_op:
            batch_op.alter_column('name', existing_type=sa.String(length=255), nullable=False)
        # Create index
        try:
            op.create_index('ix_cash_registers_name', 'cash_registers', ['name'])
        except Exception:
            pass


def downgrade() -> None:
    try:
        op.drop_index('ix_cash_registers_name', table_name='cash_registers')
    except Exception:
        pass
    with op.batch_alter_table('cash_registers') as batch_op:
        try:
            batch_op.drop_column('name')
        except Exception:
            pass


