"""add image_file_id to products

Revision ID: 20251117_050152
Revises: 
Create Date: 2025-11-17 05:01:52.000000

"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '20251117_050152'
down_revision = '20250116_000002_add_wallet_account'
branch_labels = None
depends_on = None


def upgrade() -> None:
    connection = op.get_bind()
    
    # بررسی وجود ستون
    result = connection.execute(sa.text("""
        SELECT COUNT(*) 
        FROM information_schema.columns 
        WHERE table_schema = DATABASE() 
        AND table_name = 'products' 
        AND column_name = 'image_file_id'
    """)).scalar()
    
    # اگر ستون وجود ندارد، اضافه می‌کنیم
    if result == 0:
        op.add_column(
            'products',
            sa.Column('image_file_id', sa.String(length=36), nullable=True)
        )
        
        # تغییر charset و collation برای سازگاری با file_storage.id
        connection.execute(sa.text("""
            ALTER TABLE products 
            MODIFY COLUMN image_file_id VARCHAR(36) 
            CHARACTER SET utf8mb4 
            COLLATE utf8mb4_general_ci 
            NULL
        """))
    else:
        # اگر ستون وجود دارد، فقط charset و collation را تغییر می‌دهیم
        connection.execute(sa.text("""
            ALTER TABLE products 
            MODIFY COLUMN image_file_id VARCHAR(36) 
            CHARACTER SET utf8mb4 
            COLLATE utf8mb4_general_ci 
            NULL
        """))
    
    # بررسی وجود Foreign Key
    fk_result = connection.execute(sa.text("""
        SELECT COUNT(*) 
        FROM information_schema.table_constraints 
        WHERE table_schema = DATABASE() 
        AND table_name = 'products' 
        AND constraint_name = 'fk_products_image_file_id'
    """)).scalar()
    
    # اگر Foreign Key وجود ندارد، اضافه می‌کنیم
    if fk_result == 0:
        op.create_foreign_key(
            'fk_products_image_file_id',
            'products',
            'file_storage',
            ['image_file_id'],
            ['id'],
            ondelete='SET NULL'
        )
    
    # بررسی وجود Index
    index_result = connection.execute(sa.text("""
        SELECT COUNT(*) 
        FROM information_schema.statistics 
        WHERE table_schema = DATABASE() 
        AND table_name = 'products' 
        AND index_name = 'ix_products_image_file_id'
    """)).scalar()
    
    # اگر Index وجود ندارد، اضافه می‌کنیم
    if index_result == 0:
        op.create_index(
            'ix_products_image_file_id',
            'products',
            ['image_file_id']
        )


def downgrade() -> None:
    # حذف index
    op.drop_index('ix_products_image_file_id', table_name='products')
    
    # حذف Foreign Key
    op.drop_constraint('fk_products_image_file_id', 'products', type_='foreignkey')
    
    # حذف فیلد
    op.drop_column('products', 'image_file_id')

