"""جدول report_templates"""
from alembic import op
import sqlalchemy as sa


def upgrade():
    op.create_table(
        'report_templates',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('module_key', sa.String(length=64), nullable=False),
        sa.Column('subtype', sa.String(length=64), nullable=True),
        sa.Column('name', sa.String(length=160), nullable=False),
        sa.Column('description', sa.String(length=512), nullable=True),
        sa.Column('engine', sa.String(length=32), nullable=False, server_default='jinja2'),
        sa.Column('status', sa.String(length=16), nullable=False, server_default='draft'),
        sa.Column('is_default', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('version', sa.Integer(), nullable=False, server_default='1'),
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
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['created_by'], ['users.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_report_templates_business_id'), 'report_templates', ['business_id'], unique=False)
    op.create_index(op.f('ix_report_templates_module_key'), 'report_templates', ['module_key'], unique=False)
    op.create_index(op.f('ix_report_templates_subtype'), 'report_templates', ['subtype'], unique=False)
    op.create_index(op.f('ix_report_templates_status'), 'report_templates', ['status'], unique=False)
    op.create_index(op.f('ix_report_templates_is_default'), 'report_templates', ['is_default'], unique=False)


def downgrade():
    op.drop_index(op.f('ix_report_templates_is_default'), table_name='report_templates')
    op.drop_index(op.f('ix_report_templates_status'), table_name='report_templates')
    op.drop_index(op.f('ix_report_templates_subtype'), table_name='report_templates')
    op.drop_index(op.f('ix_report_templates_module_key'), table_name='report_templates')
    op.drop_index(op.f('ix_report_templates_business_id'), table_name='report_templates')
    op.drop_table('report_templates')

