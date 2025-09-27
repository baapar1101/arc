"""merge multiple heads

Revision ID: f876bfa36805
Revises: 20250117_000009, 20250120_000002, 20250927_000017_add_account_id_to_document_lines
Create Date: 2025-09-27 12:29:57.080003

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'f876bfa36805'
down_revision = ('20250117_000009', '20250120_000002', '20250927_000017_add_account_id_to_document_lines')
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
