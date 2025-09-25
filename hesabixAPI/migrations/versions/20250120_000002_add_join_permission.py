"""add join permission

Revision ID: 20250120_000002
Revises: 20250120_000001
Create Date: 2025-01-20 00:00:02.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20250120_000002'
down_revision = '20250120_000001'
branch_labels = None
depends_on = None


def upgrade():
    """Add join permission support"""
    # این migration فقط برای مستندسازی است
    # جدول business_permissions قبلاً وجود دارد و JSON field است
    # بنابراین نیازی به تغییر schema نیست
    pass


def downgrade():
    """Remove join permission support"""
    # این migration فقط برای مستندسازی است
    pass
