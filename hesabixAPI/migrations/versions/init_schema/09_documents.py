"""جداول documents و document_lines"""
from alembic import op
import sqlalchemy as sa


def upgrade():
    # جدول documents
    op.create_table(
        'documents',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('code', sa.String(length=50), nullable=False),
        sa.Column('business_id', sa.Integer(), nullable=False),
        sa.Column('fiscal_year_id', sa.Integer(), nullable=False),
        sa.Column('currency_id', sa.Integer(), nullable=False),
        sa.Column('created_by_user_id', sa.Integer(), nullable=False),
        sa.Column('registered_at', sa.DateTime(), nullable=False),
        sa.Column('document_date', sa.Date(), nullable=False),
        sa.Column('document_type', sa.String(length=50), nullable=False),
        sa.Column('is_proforma', sa.Boolean(), nullable=False, server_default='0'),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('extra_info', sa.JSON(), nullable=True),
        sa.Column('developer_settings', sa.JSON(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['business_id'], ['businesses.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['fiscal_year_id'], ['fiscal_years.id'], ondelete='RESTRICT'),
        sa.ForeignKeyConstraint(['currency_id'], ['currencies.id'], ondelete='RESTRICT'),
        sa.ForeignKeyConstraint(['created_by_user_id'], ['users.id'], ondelete='RESTRICT'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('business_id', 'code', name='uq_documents_business_code')
    )
    op.create_index(op.f('ix_documents_code'), 'documents', ['code'], unique=False)
    op.create_index(op.f('ix_documents_business_id'), 'documents', ['business_id'], unique=False)
    op.create_index(op.f('ix_documents_fiscal_year_id'), 'documents', ['fiscal_year_id'], unique=False)
    op.create_index(op.f('ix_documents_currency_id'), 'documents', ['currency_id'], unique=False)
    op.create_index(op.f('ix_documents_created_by_user_id'), 'documents', ['created_by_user_id'], unique=False)

    # جدول document_lines
    op.create_table(
        'document_lines',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('document_id', sa.Integer(), nullable=False),
        sa.Column('account_id', sa.Integer(), nullable=True),
        sa.Column('person_id', sa.Integer(), nullable=True),
        sa.Column('product_id', sa.Integer(), nullable=True),
        sa.Column('bank_account_id', sa.Integer(), nullable=True),
        sa.Column('cash_register_id', sa.Integer(), nullable=True),
        sa.Column('petty_cash_id', sa.Integer(), nullable=True),
        sa.Column('check_id', sa.Integer(), nullable=True),
        sa.Column('quantity', sa.Numeric(precision=18, scale=6), nullable=True, server_default='0'),
        sa.Column('debit', sa.Numeric(precision=18, scale=2), nullable=False, server_default='0'),
        sa.Column('credit', sa.Numeric(precision=18, scale=2), nullable=False, server_default='0'),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('extra_info', sa.JSON(), nullable=True),
        sa.Column('developer_data', sa.JSON(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['document_id'], ['documents.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['account_id'], ['accounts.id'], ondelete='RESTRICT'),
        sa.ForeignKeyConstraint(['person_id'], ['persons.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['product_id'], ['products.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['bank_account_id'], ['bank_accounts.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['cash_register_id'], ['cash_registers.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['petty_cash_id'], ['petty_cash.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['check_id'], ['checks.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_document_lines_document_id'), 'document_lines', ['document_id'], unique=False)
    op.create_index(op.f('ix_document_lines_account_id'), 'document_lines', ['account_id'], unique=False)
    op.create_index(op.f('ix_document_lines_person_id'), 'document_lines', ['person_id'], unique=False)
    op.create_index(op.f('ix_document_lines_product_id'), 'document_lines', ['product_id'], unique=False)
    op.create_index(op.f('ix_document_lines_bank_account_id'), 'document_lines', ['bank_account_id'], unique=False)
    op.create_index(op.f('ix_document_lines_cash_register_id'), 'document_lines', ['cash_register_id'], unique=False)
    op.create_index(op.f('ix_document_lines_petty_cash_id'), 'document_lines', ['petty_cash_id'], unique=False)
    op.create_index(op.f('ix_document_lines_check_id'), 'document_lines', ['check_id'], unique=False)


def downgrade():
    op.drop_index(op.f('ix_document_lines_check_id'), table_name='document_lines')
    op.drop_index(op.f('ix_document_lines_petty_cash_id'), table_name='document_lines')
    op.drop_index(op.f('ix_document_lines_cash_register_id'), table_name='document_lines')
    op.drop_index(op.f('ix_document_lines_bank_account_id'), table_name='document_lines')
    op.drop_index(op.f('ix_document_lines_product_id'), table_name='document_lines')
    op.drop_index(op.f('ix_document_lines_person_id'), table_name='document_lines')
    op.drop_index(op.f('ix_document_lines_account_id'), table_name='document_lines')
    op.drop_index(op.f('ix_document_lines_document_id'), table_name='document_lines')
    op.drop_table('document_lines')
    
    op.drop_index(op.f('ix_documents_created_by_user_id'), table_name='documents')
    op.drop_index(op.f('ix_documents_currency_id'), table_name='documents')
    op.drop_index(op.f('ix_documents_fiscal_year_id'), table_name='documents')
    op.drop_index(op.f('ix_documents_business_id'), table_name='documents')
    op.drop_index(op.f('ix_documents_code'), table_name='documents')
    op.drop_table('documents')

