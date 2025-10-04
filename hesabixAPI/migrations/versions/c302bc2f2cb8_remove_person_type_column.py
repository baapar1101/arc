"""remove_person_type_column

Revision ID: c302bc2f2cb8
Revises: 1f0abcdd7300
Create Date: 2025-10-04 19:04:30.866110

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'c302bc2f2cb8'
down_revision = '1f0abcdd7300'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # حذف ستون person_type از جدول persons
    op.drop_column('persons', 'person_type')


def downgrade() -> None:
    # بازگردانی ستون person_type
    op.add_column('persons', 
        sa.Column('person_type', 
            sa.Enum('مشتری', 'بازاریاب', 'کارمند', 'تامین‌کننده', 'همکار', 'فروشنده', 'سهامدار', name='person_type_enum'),
            nullable=False,
            comment='نوع شخص'
        )
    )
