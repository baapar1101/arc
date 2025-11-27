"""add gift credit account (60205)

Revision ID: 20250126_000001_add_gift_credit_account
Revises: 20251117_050152_add_image_file_id_to_products
Create Date: 2025-01-26 00:00:01.000001

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20250126_000001_add_gift_credit_account'
down_revision = '20251117_050152'
branch_labels = None
depends_on = None


def upgrade() -> None:
    conn = op.get_bind()
    
    # بررسی وجود حساب 602 (درآمد های غیر عملیاتی)
    select_parent = sa.text("SELECT id FROM accounts WHERE business_id IS NULL AND code = '602' LIMIT 1")
    parent_result = conn.execute(select_parent)
    parent_row = parent_result.fetchone()
    
    if not parent_row:
        # اگر حساب والد وجود ندارد، از migration قبلی استفاده نکنید
        return
    
    parent_id = parent_row[0]
    
    # بررسی وجود حساب 60205
    select_existing = sa.text("SELECT id FROM accounts WHERE business_id IS NULL AND code = '60205' LIMIT 1")
    existing_result = conn.execute(select_existing)
    existing_row = existing_result.fetchone()
    
    if existing_row:
        # حساب از قبل وجود دارد
        return
    
    # اضافه کردن حساب جدید
    insert_query = sa.text(
        """
        INSERT INTO accounts (name, business_id, account_type, code, parent_id, created_at, updated_at)
        VALUES (:name, NULL, :account_type, :code, :parent_id, NOW(), NOW())
        """
    )
    
    conn.execute(
        insert_query,
        {
            "name": "کمک‌های دریافتی / اعتبارات هدیه",
            "account_type": "0",
            "code": "60205",
            "parent_id": parent_id,
        }
    )


def downgrade() -> None:
    conn = op.get_bind()
    
    # حذف حساب 60205
    delete_query = sa.text("DELETE FROM accounts WHERE business_id IS NULL AND code = '60205'")
    conn.execute(delete_query)

