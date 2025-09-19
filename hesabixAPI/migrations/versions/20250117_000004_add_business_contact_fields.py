from __future__ import annotations

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "20250117_000004"
down_revision = "20250117_000003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Add new contact and identification fields to businesses table
    op.add_column('businesses', sa.Column('address', sa.Text(), nullable=True))
    op.add_column('businesses', sa.Column('phone', sa.String(length=20), nullable=True))
    op.add_column('businesses', sa.Column('mobile', sa.String(length=20), nullable=True))
    op.add_column('businesses', sa.Column('national_id', sa.String(length=20), nullable=True))
    op.add_column('businesses', sa.Column('registration_number', sa.String(length=50), nullable=True))
    op.add_column('businesses', sa.Column('economic_id', sa.String(length=50), nullable=True))
    
    # Create indexes for the new fields
    op.create_index('ix_businesses_national_id', 'businesses', ['national_id'])
    op.create_index('ix_businesses_registration_number', 'businesses', ['registration_number'])
    op.create_index('ix_businesses_economic_id', 'businesses', ['economic_id'])


def downgrade() -> None:
    # Drop indexes
    op.drop_index('ix_businesses_economic_id', table_name='businesses')
    op.drop_index('ix_businesses_registration_number', table_name='businesses')
    op.drop_index('ix_businesses_national_id', table_name='businesses')
    
    # Drop columns
    op.drop_column('businesses', 'economic_id')
    op.drop_column('businesses', 'registration_number')
    op.drop_column('businesses', 'national_id')
    op.drop_column('businesses', 'mobile')
    op.drop_column('businesses', 'phone')
    op.drop_column('businesses', 'address')
