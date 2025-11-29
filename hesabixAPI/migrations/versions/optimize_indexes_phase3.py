"""بهینه‌سازی Indexes برای بهبود Performance

Revision ID: optimize_indexes_phase3
Revises: 
Create Date: 2024-01-01 12:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'optimize_indexes_phase3'
down_revision = None  # باید با آخرین migration جایگزین شود
branch_labels = None
depends_on = None


def upgrade():
    """
    اضافه کردن Indexes برای بهبود Performance
    """
    
    # Indexes برای جدول documents
    try:
        op.create_index(
            'ix_documents_business_date',
            'documents',
            ['business_id', 'document_date'],
            unique=False
        )
        op.create_index(
            'ix_documents_business_type',
            'documents',
            ['business_id', 'document_type'],
            unique=False
        )
        op.create_index(
            'ix_documents_business_created',
            'documents',
            ['business_id', 'created_at'],
            unique=False
        )
    except Exception:
        pass  # اگر index وجود داشت، skip می‌کنیم
    
    # Indexes برای جدول products
    try:
        op.create_index(
            'ix_products_business_category',
            'products',
            ['business_id', 'category_id'],
            unique=False
        )
        op.create_index(
            'ix_products_business_name',
            'products',
            ['business_id', 'name'],
            unique=False
        )
        op.create_index(
            'ix_products_business_code',
            'products',
            ['business_id', 'code'],
            unique=False
        )
    except Exception:
        pass
    
    # Indexes برای جدول activity_logs
    try:
        op.create_index(
            'ix_activity_logs_business_category',
            'activity_logs',
            ['business_id', 'category'],
            unique=False
        )
        op.create_index(
            'ix_activity_logs_business_created',
            'activity_logs',
            ['business_id', 'created_at'],
            unique=False
        )
        op.create_index(
            'ix_activity_logs_user_created',
            'activity_logs',
            ['user_id', 'created_at'],
            unique=False
        )
        op.create_index(
            'ix_activity_logs_entity',
            'activity_logs',
            ['entity_type', 'entity_id'],
            unique=False
        )
    except Exception:
        pass
    
    # Indexes برای جدول invoice_item_lines
    try:
        op.create_index(
            'ix_invoice_item_lines_document_product',
            'invoice_item_lines',
            ['document_id', 'product_id'],
            unique=False
        )
    except Exception:
        pass
    
    # Indexes برای جدول api_keys (برای بهبود performance در validation)
    try:
        op.create_index(
            'ix_api_keys_user_type',
            'api_keys',
            ['user_id', 'key_type'],
            unique=False
        )
        op.create_index(
            'ix_api_keys_revoked',
            'api_keys',
            ['revoked_at'],
            unique=False
        )
    except Exception:
        pass
    
    # Indexes برای جدول persons
    try:
        op.create_index(
            'ix_persons_business_type',
            'persons',
            ['business_id', 'person_type'],
            unique=False
        )
        op.create_index(
            'ix_persons_business_name',
            'persons',
            ['business_id', 'name'],
            unique=False
        )
    except Exception:
        pass
    
    # Indexes برای جدول document_lines
    try:
        op.create_index(
            'ix_document_lines_document',
            'document_lines',
            ['document_id'],
            unique=False
        )
        op.create_index(
            'ix_document_lines_account',
            'document_lines',
            ['account_id'],
            unique=False
        )
    except Exception:
        pass


def downgrade():
    """
    حذف Indexes اضافه شده
    """
    try:
        op.drop_index('ix_documents_business_date', table_name='documents')
        op.drop_index('ix_documents_business_type', table_name='documents')
        op.drop_index('ix_documents_business_created', table_name='documents')
    except Exception:
        pass
    
    try:
        op.drop_index('ix_products_business_category', table_name='products')
        op.drop_index('ix_products_business_name', table_name='products')
        op.drop_index('ix_products_business_code', table_name='products')
    except Exception:
        pass
    
    try:
        op.drop_index('ix_activity_logs_business_category', table_name='activity_logs')
        op.drop_index('ix_activity_logs_business_created', table_name='activity_logs')
        op.drop_index('ix_activity_logs_user_created', table_name='activity_logs')
        op.drop_index('ix_activity_logs_entity', table_name='activity_logs')
    except Exception:
        pass
    
    try:
        op.drop_index('ix_invoice_item_lines_document_product', table_name='invoice_item_lines')
    except Exception:
        pass
    
    try:
        op.drop_index('ix_api_keys_user_type', table_name='api_keys')
        op.drop_index('ix_api_keys_revoked', table_name='api_keys')
    except Exception:
        pass
    
    try:
        op.drop_index('ix_persons_business_type', table_name='persons')
        op.drop_index('ix_persons_business_name', table_name='persons')
    except Exception:
        pass
    
    try:
        op.drop_index('ix_document_lines_document', table_name='document_lines')
        op.drop_index('ix_document_lines_account', table_name='document_lines')
    except Exception:
        pass

