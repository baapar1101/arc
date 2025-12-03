"""تغییر نام ستون metadata به extra_metadata

revision: 20250120_000002_rename_metadata_to_extra_metadata
down_revision: 20250120_000001_create_warranty_tables
branch_labels: None
depends_on: None

این migration نام ستون metadata را در جدول warranty_codes به extra_metadata تغییر می‌دهد
تا با Declarative API SQLAlchemy تداخل نداشته باشد.
"""
from __future__ import annotations

from alembic import op


# revision identifiers, used by Alembic.
revision = '20250120_000002'
down_revision = '20250120_000001'
branch_labels = None
depends_on = None


def upgrade():
    # تغییر نام ستون از metadata به extra_metadata
    from sqlalchemy.dialects.mysql import JSON
    op.alter_column(
        'warranty_codes',
        'metadata',
        new_column_name='extra_metadata',
        existing_type=JSON,
        existing_nullable=True,
        existing_comment='اطلاعات اضافی'
    )


def downgrade():
    # برگشت به نام قبلی
    from sqlalchemy.dialects.mysql import JSON
    op.alter_column(
        'warranty_codes',
        'extra_metadata',
        new_column_name='metadata',
        existing_type=JSON,
        existing_nullable=True,
        existing_comment='اطلاعات اضافی'
    )

