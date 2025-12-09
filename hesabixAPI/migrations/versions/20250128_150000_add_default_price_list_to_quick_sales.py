"""add_default_price_list_to_quick_sales

Revision ID: 20250128_150000
Revises: 9cc424e46c07
Create Date: 2025-01-28 15:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20250128_150000'
down_revision = '9cc424e46c07'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # اضافه کردن فیلد default_price_list_id به جدول quick_sales_settings
    op.add_column(
        'quick_sales_settings',
        sa.Column(
            'default_price_list_id',
            sa.Integer(),
            nullable=True,
            comment='لیست قیمت پیش‌فرض برای فروش سریع'
        )
    )
    
    # اضافه کردن ForeignKey constraint
    op.create_foreign_key(
        'fk_quick_sales_settings_default_price_list_id',
        'quick_sales_settings',
        'price_lists',
        ['default_price_list_id'],
        ['id'],
        ondelete='SET NULL'
    )


def downgrade() -> None:
    # حذف ForeignKey constraint
    op.drop_constraint(
        'fk_quick_sales_settings_default_price_list_id',
        'quick_sales_settings',
        type_='foreignkey'
    )
    
    # حذف فیلد
    op.drop_column('quick_sales_settings', 'default_price_list_id')

