"""add_inventory_valuation_method

Revision ID: a1b2c3d4e5f6
Revises: b8c9286db6bd
Create Date: 2025-01-29 12:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'a1b2c3d4e5f6'
down_revision = 'b8c9286db6bd'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # بررسی اینکه آیا فیلد قبلاً وجود دارد یا نه
    from sqlalchemy import inspect
    from sqlalchemy import create_engine
    from alembic import context
    
    bind = context.get_bind()
    inspector = inspect(bind)
    columns = [col['name'] for col in inspector.get_columns('fiscal_years')]
    
    if 'inventory_valuation_method' not in columns:
        op.add_column(
            'fiscal_years',
            sa.Column(
                'inventory_valuation_method',
                sa.String(length=20),
                nullable=True,
                server_default='FIFO',
                comment='روش ارزیابی انبار: FIFO, LIFO, WeightedAverage'
            )
        )


def downgrade() -> None:
    op.drop_column('fiscal_years', 'inventory_valuation_method')

