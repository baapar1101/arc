from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = '20251108_230001_add_report_templates'
down_revision: Union[str, None] = '20251107_170101_add_invoice_item_lines_and_migrate'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
	bind = op.get_bind()
	inspector = sa.inspect(bind)

	# Create report_templates table if not exists
	if 'report_templates' not in inspector.get_table_names():
		op.create_table(
			'report_templates',
			sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
			sa.Column('business_id', sa.Integer(), sa.ForeignKey('businesses.id', ondelete='CASCADE'), nullable=False),
			sa.Column('module_key', sa.String(length=64), nullable=False),
			sa.Column('subtype', sa.String(length=64), nullable=True),
			sa.Column('name', sa.String(length=160), nullable=False),
			sa.Column('description', sa.String(length=512), nullable=True),
			sa.Column('engine', sa.String(length=32), nullable=False, server_default=sa.text("'jinja2'")),
			sa.Column('status', sa.String(length=16), nullable=False, server_default=sa.text("'draft'")),
			sa.Column('is_default', sa.Boolean(), nullable=False, server_default=sa.text("0")),
			sa.Column('version', sa.Integer(), nullable=False, server_default=sa.text("1")),
			sa.Column('content_html', sa.Text(), nullable=False),
			sa.Column('content_css', sa.Text(), nullable=True),
			sa.Column('header_html', sa.Text(), nullable=True),
			sa.Column('footer_html', sa.Text(), nullable=True),
			sa.Column('paper_size', sa.String(length=32), nullable=True),
			sa.Column('orientation', sa.String(length=16), nullable=True),
			sa.Column('margins', sa.JSON(), nullable=True),
			sa.Column('assets', sa.JSON(), nullable=True),
			sa.Column('created_by', sa.Integer(), nullable=True),
			sa.Column('created_at', sa.DateTime(), nullable=False),
			sa.Column('updated_at', sa.DateTime(), nullable=False),
		)
		# Indexes
		try:
			op.create_index('ix_report_templates_business_id', 'report_templates', ['business_id'])
			op.create_index('ix_report_templates_module_key', 'report_templates', ['module_key'])
			op.create_index('ix_report_templates_subtype', 'report_templates', ['subtype'])
			op.create_index('ix_report_templates_status', 'report_templates', ['status'])
			op.create_index('ix_report_templates_is_default', 'report_templates', ['is_default'])
		except Exception:
			pass


def downgrade() -> None:
	# Drop indexes then table
	try:
		op.drop_index('ix_report_templates_is_default', table_name='report_templates')
		op.drop_index('ix_report_templates_status', table_name='report_templates')
		op.drop_index('ix_report_templates_subtype', table_name='report_templates')
		op.drop_index('ix_report_templates_module_key', table_name='report_templates')
		op.drop_index('ix_report_templates_business_id', table_name='report_templates')
	except Exception:
		pass
	try:
		op.drop_table('report_templates')
	except Exception:
		pass


