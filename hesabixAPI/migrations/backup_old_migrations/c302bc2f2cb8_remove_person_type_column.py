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
    # Check if column exists before dropping
    connection = op.get_bind()
    result = connection.execute(sa.text("""
        SELECT COUNT(*) 
        FROM information_schema.columns 
        WHERE table_schema = DATABASE() 
        AND table_name = 'persons' 
        AND column_name = 'person_type'
    """)).fetchone()
    
    if result[0] > 0:
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
