"""add is_default to email_config

Revision ID: 20250117_000009
Revises: 20250117_000008
Create Date: 2025-01-17 12:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20250117_000009'
down_revision = '20250117_000008'
branch_labels = None
depends_on = None


def upgrade():
    # Add is_default column to email_configs table
    op.add_column('email_configs', sa.Column('is_default', sa.Boolean(), nullable=False, server_default='0'))


def downgrade():
    # Remove is_default column from email_configs table
    op.drop_column('email_configs', 'is_default')
