"""Harden quick-sales permissions and invoice idempotency.

Revision ID: 20261017_000001_quick_sales_audit_permissions
Revises: 20261015_000001_quick_sales_web_shortcut
"""

from alembic import op

revision = "20261017_000001_quick_sales_audit_permissions"
down_revision = "20261015_000001_quick_sales_web_shortcut"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
        CREATE UNIQUE INDEX uq_documents_quick_sale_request
        ON documents (
            business_id,
            (extra_info ->> 'quick_sale_request_id')
        )
        WHERE document_type = 'invoice_sales'
          AND extra_info ->> 'quick_sale' = 'true'
          AND extra_info ->> 'quick_sale_request_id' IS NOT NULL
        """)
    # کاربران فعلی دارای مجوز ثبت فاکتور، رفتار جاری فروش سریع را از دست
    # نمی‌دهند؛ از این پس مالک می‌تواند هر مجوز را جداگانه ویرایش کند.
    op.execute("""
        UPDATE business_permissions
        SET business_permissions = jsonb_set(
            COALESCE(business_permissions::jsonb, '{}'::jsonb),
            '{quick_sales}',
            jsonb_build_object(
                    'create_customer', true,
                    'view_customer_contact', true,
                    'view_customer_balance', true
                ) || COALESCE(
                    business_permissions::jsonb -> 'quick_sales',
                    '{}'::jsonb
                ),
            true
        )::json
        WHERE COALESCE(
            (business_permissions::jsonb -> 'invoices' ->> 'add')::boolean,
            false
        ) = true
           OR COALESCE(
            (business_permissions::jsonb -> 'invoices' ->> 'write')::boolean,
            false
        ) = true
           OR COALESCE(
            (business_permissions::jsonb -> 'invoices' ->> 'edit')::boolean,
            false
        ) = true
        """)


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS uq_documents_quick_sale_request")
    op.execute("""
        UPDATE business_permissions
        SET business_permissions = (
            business_permissions::jsonb
            #- '{quick_sales,create_customer}'
            #- '{quick_sales,view_customer_contact}'
            #- '{quick_sales,view_customer_balance}'
        )::json
        """)
