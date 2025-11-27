"""merge_all_heads_final

Revision ID: 3f8bc1df5f7c
Revises: 20250205_000001_create_document_number_counters, 20251124_150001_add_product_tax_codes, 20251124_200000
Create Date: 2025-11-24 20:07:25.634984

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '3f8bc1df5f7c'
down_revision = ('20250205_000001_create_document_number_counters', '20251124_150001_add_product_tax_codes', '20251124_200000')
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
