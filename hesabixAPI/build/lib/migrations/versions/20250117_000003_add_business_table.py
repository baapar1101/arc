from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect

# revision identifiers, used by Alembic.
revision = "20250117_000003"
down_revision = "20250916_000002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = inspect(bind)

    # Create businesses table if not exists
    if 'businesses' not in inspector.get_table_names():
        op.create_table(
            'businesses',
            sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
            sa.Column('name', sa.String(length=255), nullable=False),
            sa.Column('business_type', sa.Enum('شرکت', 'مغازه', 'فروشگاه', 'اتحادیه', 'باشگاه', 'موسسه', 'شخصی', name='business_type_enum', create_type=False), nullable=False),
            sa.Column('business_field', sa.Enum('تولیدی', 'بازرگانی', 'خدماتی', 'سایر', name='business_field_enum', create_type=False), nullable=False),
            sa.Column('owner_id', sa.Integer(), nullable=False),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.Column('updated_at', sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(['owner_id'], ['users.id'], ondelete='CASCADE'),
            sa.PrimaryKeyConstraint('id')
        )
    
    # Create indexes if not exists
    existing_indexes = {idx['name'] for idx in inspector.get_indexes('businesses')} if 'businesses' in inspector.get_table_names() else set()
    if 'ix_businesses_name' not in existing_indexes:
        op.create_index('ix_businesses_name', 'businesses', ['name'])
    if 'ix_businesses_owner_id' not in existing_indexes:
        op.create_index('ix_businesses_owner_id', 'businesses', ['owner_id'])


def downgrade() -> None:
    # Drop indexes
    op.drop_index('ix_businesses_owner_id', table_name='businesses')
    op.drop_index('ix_businesses_name', table_name='businesses')
    
    # Drop table
    op.drop_table('businesses')
