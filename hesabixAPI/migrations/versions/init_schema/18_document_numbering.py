"""جداول business_document_numbering_settings و document_number_counters"""
from alembic import op
import sqlalchemy as sa


def upgrade():
    # جدول business_document_numbering_settings
    op.create_table(
        'business_document_numbering_settings',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('document_type', sa.String(length=50), nullable=False),
        sa.Column('prefix', sa.String(length=20), nullable=True),
        sa.Column('include_date', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('calendar_type', sa.String(length=10), nullable=False, server_default='gregorian'),
        sa.Column('date_format', sa.String(length=20), nullable=True),
        sa.Column('separator', sa.String(length=5), nullable=False, server_default='-'),
        sa.Column('start_number', sa.Integer(), nullable=False, server_default='1'),
        sa.Column('number_padding', sa.Integer(), nullable=False, server_default='4'),
        sa.Column('reset_period', sa.String(length=20), nullable=True),
        sa.Column('custom_format', sa.String(length=100), nullable=True),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('business_id', 'document_type', name='uq_doc_numbering_business_type')
    )
    op.create_index(op.f('ix_business_document_numbering_settings_business_id'), 'business_document_numbering_settings', ['business_id'], unique=False)
    op.create_index(op.f('ix_business_document_numbering_settings_document_type'), 'business_document_numbering_settings', ['document_type'], unique=False)

    # جدول document_number_counters
    op.create_table(
        'document_number_counters',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('document_type', sa.String(length=50), nullable=False),
        sa.Column('date_bucket', sa.String(length=32), nullable=False, server_default='GLOBAL'),
        sa.Column('last_number', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('business_id', 'document_type', 'date_bucket', name='uq_doc_number_counter_bucket')
    )
    op.create_index(op.f('ix_document_number_counters_business_id'), 'document_number_counters', ['business_id'], unique=False)
    op.create_index(op.f('ix_document_number_counters_document_type'), 'document_number_counters', ['document_type'], unique=False)


def downgrade():
    op.drop_index(op.f('ix_document_number_counters_document_type'), table_name='document_number_counters')
    op.drop_index(op.f('ix_document_number_counters_business_id'), table_name='document_number_counters')
    op.drop_table('document_number_counters')
    
    op.drop_index(op.f('ix_business_document_numbering_settings_document_type'), table_name='business_document_numbering_settings')
    op.drop_index(op.f('ix_business_document_numbering_settings_business_id'), table_name='business_document_numbering_settings')
    op.drop_table('business_document_numbering_settings')

