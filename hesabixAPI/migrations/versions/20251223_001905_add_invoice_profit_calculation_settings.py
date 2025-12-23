"""add invoice profit calculation settings

Revision ID: 20251223_001905
Revises: 4d60f85a6561
Create Date: 2025-12-23 00:19:05.000000

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import mysql

# revision identifiers, used by Alembic.
revision = '20251223_001905'
down_revision = '4d60f85a6561'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # اضافه کردن فیلدهای تنظیمات محاسبه سود فاکتور
    op.add_column('businesses', sa.Column('invoice_profit_calculation_method', sa.String(length=20), nullable=True, server_default='automatic', comment='روش محاسبه سود فاکتور: automatic, manual, disabled'))
    op.add_column('businesses', sa.Column('invoice_profit_calculation_basis', sa.String(length=30), nullable=True, server_default='purchase_price', comment='مبنای محاسبه سود: purchase_price, cost_price, average_cost, fifo, lifo, weighted_average, standard_cost, actual_cost'))
    op.add_column('businesses', sa.Column('invoice_profit_include_overhead', sa.Boolean(), nullable=False, server_default='0', comment='آیا هزینه‌های سربار در محاسبه سود لحاظ شود؟'))
    op.add_column('businesses', sa.Column('invoice_profit_overhead_type', sa.String(length=30), nullable=True, server_default='none', comment='نوع هزینه‌های سربار: none, production_overhead, all_overhead, custom_percent'))
    op.add_column('businesses', sa.Column('invoice_profit_overhead_percent', sa.Numeric(precision=5, scale=2), nullable=True, server_default='0', comment='درصد هزینه‌های سربار (در صورت انتخاب custom_percent)'))
    op.add_column('businesses', sa.Column('invoice_profit_calculation_type', sa.String(length=20), nullable=True, server_default='gross', comment='نوع محاسبه سود: gross, net, both'))


def downgrade() -> None:
    # حذف فیلدهای اضافه شده
    op.drop_column('businesses', 'invoice_profit_calculation_type')
    op.drop_column('businesses', 'invoice_profit_overhead_percent')
    op.drop_column('businesses', 'invoice_profit_overhead_type')
    op.drop_column('businesses', 'invoice_profit_include_overhead')
    op.drop_column('businesses', 'invoice_profit_calculation_basis')
    op.drop_column('businesses', 'invoice_profit_calculation_method')


