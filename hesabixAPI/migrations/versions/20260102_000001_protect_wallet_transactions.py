"""protect_wallet_transactions

Revision ID: 20260102_000001
Revises: 20260101_000001
Create Date: 2026-01-02 00:00:00.000000

تغییر Foreign Key Constraints از SET NULL به RESTRICT برای محافظت از تراکنش‌های کیف پول
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect

# revision identifiers, used by Alembic.
revision = '20260102_000001'
down_revision = '20260101_000001'
branch_labels = None
depends_on = None


def upgrade() -> None:
    """
    تغییر constraint های Foreign Key از SET NULL به RESTRICT
    این کار از حذف تراکنش‌های کیف پول که به موجودیت‌های دیگر لینک شده‌اند جلوگیری می‌کند
    """
    bind = op.get_bind()
    inspector = inspect(bind)
    
    # لیست جداول و constraint های مربوطه
    tables_to_update = [
        {
            'table': 'ai_invoices',
            'column': 'wallet_transaction_id',
            'constraint_name': 'ai_invoices_wallet_transaction_id_fkey'
        },
        {
            'table': 'storage_invoices',
            'column': 'wallet_transaction_id',
            'constraint_name': 'storage_invoices_wallet_transaction_id_fkey'
        },
        {
            'table': 'marketplace_orders',
            'column': 'wallet_transaction_id',
            'constraint_name': 'marketplace_orders_wallet_transaction_id_fkey'
        },
        {
            'table': 'zohal_service_usage',
            'column': 'wallet_transaction_id',
            'constraint_name': 'zohal_service_usage_wallet_transaction_id_fkey'
        },
        {
            'table': 'ai_usage_logs',
            'column': 'wallet_transaction_id',
            'constraint_name': 'ai_usage_logs_wallet_transaction_id_fkey'
        },
        {
            'table': 'document_monetization',
            'column': 'wallet_transaction_id',
            'constraint_name': 'document_monetization_wallet_transaction_id_fkey'
        }
    ]
    
    for table_info in tables_to_update:
        table_name = table_info['table']
        constraint_name = table_info['constraint_name']
        
        # بررسی وجود جدول
        if table_name not in inspector.get_table_names():
            continue
        
        # بررسی وجود constraint
        try:
            # دریافت تمام foreign keys
            fks = inspector.get_foreign_keys(table_name)
            has_constraint = any(fk['name'] == constraint_name for fk in fks)
            
            if has_constraint:
                # حذف constraint قدیمی
                op.drop_constraint(constraint_name, table_name, type_='foreignkey')
                
                # ایجاد constraint جدید با RESTRICT
                op.create_foreign_key(
                    constraint_name,
                    table_name,
                    'wallet_transactions',
                    [table_info['column']],
                    ['id'],
                    ondelete='RESTRICT'
                )
        except Exception as e:
            # اگر constraint با نام دیگری وجود دارد، سعی می‌کنیم آن را پیدا کنیم
            try:
                fks = inspector.get_foreign_keys(table_name)
                for fk in fks:
                    if fk['constrained_columns'] == [table_info['column']]:
                        old_constraint_name = fk['name']
                        op.drop_constraint(old_constraint_name, table_name, type_='foreignkey')
                        op.create_foreign_key(
                            constraint_name,
                            table_name,
                            'wallet_transactions',
                            [table_info['column']],
                            ['id'],
                            ondelete='RESTRICT'
                        )
                        break
            except Exception:
                # اگر نتوانستیم constraint را تغییر دهیم، ادامه می‌دهیم
                pass


def downgrade() -> None:
    """
    برگشت به SET NULL (برای backward compatibility)
    """
    bind = op.get_bind()
    inspector = inspect(bind)
    
    tables_to_update = [
        {
            'table': 'ai_invoices',
            'column': 'wallet_transaction_id',
            'constraint_name': 'ai_invoices_wallet_transaction_id_fkey'
        },
        {
            'table': 'storage_invoices',
            'column': 'wallet_transaction_id',
            'constraint_name': 'storage_invoices_wallet_transaction_id_fkey'
        },
        {
            'table': 'marketplace_orders',
            'column': 'wallet_transaction_id',
            'constraint_name': 'marketplace_orders_wallet_transaction_id_fkey'
        },
        {
            'table': 'zohal_service_usage',
            'column': 'wallet_transaction_id',
            'constraint_name': 'zohal_service_usage_wallet_transaction_id_fkey'
        },
        {
            'table': 'ai_usage_logs',
            'column': 'wallet_transaction_id',
            'constraint_name': 'ai_usage_logs_wallet_transaction_id_fkey'
        },
        {
            'table': 'document_monetization',
            'column': 'wallet_transaction_id',
            'constraint_name': 'document_monetization_wallet_transaction_id_fkey'
        }
    ]
    
    for table_info in tables_to_update:
        table_name = table_info['table']
        constraint_name = table_info['constraint_name']
        
        if table_name not in inspector.get_table_names():
            continue
        
        try:
            fks = inspector.get_foreign_keys(table_name)
            has_constraint = any(fk['name'] == constraint_name for fk in fks)
            
            if has_constraint:
                op.drop_constraint(constraint_name, table_name, type_='foreignkey')
                op.create_foreign_key(
                    constraint_name,
                    table_name,
                    'wallet_transactions',
                    [table_info['column']],
                    ['id'],
                    ondelete='SET NULL'
                )
        except Exception:
            pass

