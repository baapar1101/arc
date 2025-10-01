from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect

# revision identifiers, used by Alembic.
revision = '20250927_000022_add_person_commission_fields'
down_revision = '20250927_000021_update_person_type_enum_to_persian'
branch_labels = None
depends_on = None


def upgrade() -> None:
	bind = op.get_bind()
	inspector = inspect(bind)
	cols = {c['name'] for c in inspector.get_columns('persons')} if 'persons' in inspector.get_table_names() else set()
	with op.batch_alter_table('persons') as batch_op:
		if 'commission_sale_percent' not in cols:
			batch_op.add_column(sa.Column('commission_sale_percent', sa.Numeric(5, 2), nullable=True))
		if 'commission_sales_return_percent' not in cols:
			batch_op.add_column(sa.Column('commission_sales_return_percent', sa.Numeric(5, 2), nullable=True))
		if 'commission_sales_amount' not in cols:
			batch_op.add_column(sa.Column('commission_sales_amount', sa.Numeric(12, 2), nullable=True))
		if 'commission_sales_return_amount' not in cols:
			batch_op.add_column(sa.Column('commission_sales_return_amount', sa.Numeric(12, 2), nullable=True))
		if 'commission_exclude_discounts' not in cols:
			batch_op.add_column(sa.Column('commission_exclude_discounts', sa.Boolean(), server_default=sa.text('0'), nullable=False))
		if 'commission_exclude_additions_deductions' not in cols:
			batch_op.add_column(sa.Column('commission_exclude_additions_deductions', sa.Boolean(), server_default=sa.text('0'), nullable=False))
		if 'commission_post_in_invoice_document' not in cols:
			batch_op.add_column(sa.Column('commission_post_in_invoice_document', sa.Boolean(), server_default=sa.text('0'), nullable=False))


def downgrade() -> None:
	with op.batch_alter_table('persons') as batch_op:
		batch_op.drop_column('commission_post_in_invoice_document')
		batch_op.drop_column('commission_exclude_additions_deductions')
		batch_op.drop_column('commission_exclude_discounts')
		batch_op.drop_column('commission_sales_return_amount')
		batch_op.drop_column('commission_sales_amount')
		batch_op.drop_column('commission_sales_return_percent')
		batch_op.drop_column('commission_sale_percent')


