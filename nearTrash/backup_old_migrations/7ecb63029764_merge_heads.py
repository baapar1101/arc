"""merge heads

Revision ID: 7ecb63029764
Revises: 20250106_000004, 20251012_000101_update_accounts_account_type_to_english, 20251014_000501_add_quantity_to_document_lines
Create Date: 2025-10-14 12:36:58.259190

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '7ecb63029764'
down_revision = ('20250106_000004', '20251012_000101_update_accounts_account_type_to_english', '20251014_000501_add_quantity_to_document_lines')
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
