"""add_description_to_documents

Revision ID: 9a06b0cb880a
Revises: ac9e4b3dcffc
Create Date: 2025-10-16 17:26:22.681359

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '9a06b0cb880a'
down_revision = 'ac9e4b3dcffc'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # افزودن ستون فقط اگر قبلاً وجود ندارد
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    cols = [c['name'] for c in inspector.get_columns('documents')]
    if 'description' not in cols:
        op.add_column('documents', sa.Column('description', sa.Text(), nullable=True))


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    cols = [c['name'] for c in inspector.get_columns('documents')]
    if 'description' in cols:
        op.drop_column('documents', 'description')
