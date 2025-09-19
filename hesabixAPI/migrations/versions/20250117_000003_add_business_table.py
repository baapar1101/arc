from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import mysql

# revision identifiers, used by Alembic.
revision = "20250117_000003"
down_revision = "20250916_000002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Create businesses table
    op.create_table(
        'businesses',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('name', sa.String(length=255), nullable=False),
        sa.Column('business_type', mysql.ENUM('شرکت', 'مغازه', 'فروشگاه', 'اتحادیه', 'باشگاه', 'موسسه', 'شخصی', name='businesstype'), nullable=False),
        sa.Column('business_field', mysql.ENUM('تولیدی', 'بازرگانی', 'خدماتی', 'سایر', name='businessfield'), nullable=False),
        sa.Column('owner_id', sa.Integer(), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['owner_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )
    
    # Create indexes
    op.create_index('ix_businesses_name', 'businesses', ['name'])
    op.create_index('ix_businesses_owner_id', 'businesses', ['owner_id'])


def downgrade() -> None:
    # Drop indexes
    op.drop_index('ix_businesses_owner_id', table_name='businesses')
    op.drop_index('ix_businesses_name', table_name='businesses')
    
    # Drop table
    op.drop_table('businesses')
