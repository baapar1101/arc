#!/usr/bin/env python3
"""
اسکریپت برای اجرای مستقیم migration مربوط به product_instances
"""
import sys
import os

# اضافه کردن مسیر پروژه به sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import create_engine, inspect, text
from app.core.settings import get_settings

def run_migration():
    settings = get_settings()
    engine = create_engine(settings.postgresql_dsn, echo=True)
    
    with engine.connect() as conn:
        inspector = inspect(engine)
        tables = set(inspector.get_table_names())
        products_columns = {c['name'] for c in inspector.get_columns('products')} if 'products' in tables else set()
        
        # افزودن فیلدهای جدید به جدول products
        if 'inventory_mode' not in products_columns:
            print("Adding inventory_mode column to products...")
            conn.execute(text("""
                ALTER TABLE products 
                ADD COLUMN inventory_mode VARCHAR(16) NULL DEFAULT 'bulk 
                COMMENT 'حالت موجودی: bulk (فله‌ای) یا unique (یونیک)'
            """))
            conn.commit()
        
        if 'track_serial' not in products_columns:
            print("Adding track_serial column to products...")
            conn.execute(text("""
                ALTER TABLE products 
                ADD COLUMN track_serial BOOLEAN NOT NULL DEFAULT FALSE 
                COMMENT 'ردیابی سریال نامبر برای کالاهای یونیک'
            """))
            conn.commit()
        
        if 'track_barcode' not in products_columns:
            print("Adding track_barcode column to products...")
            conn.execute(text("""
                ALTER TABLE products 
                ADD COLUMN track_barcode BOOLEAN NOT NULL DEFAULT FALSE 
                COMMENT 'ردیابی بارکد برای کالاهای یونیک'
            """))
            conn.commit()
        
        # ایجاد جدول product_instances
        if 'product_instances' not in tables:
            print("Creating product_instances table...")
            conn.execute(text("""
                CREATE TABLE product_instances (
                    id INTEGER NOT NULL AUTO_INCREMENT,
                    business_id INTEGER NOT NULL,
                    product_id INTEGER NOT NULL,
                    serial_number VARCHAR(128) NOT NULL COMMENT 'شماره سریال یکتا',
                    barcode VARCHAR(128) NULL COMMENT 'بارکد یکتا (اختیاری)',
                    warehouse_id INTEGER NULL,
                    status VARCHAR(16) NOT NULL DEFAULT 'available' COMMENT 'وضعیت: available, sold, warranty, defective',
                    custom_attributes JSON NULL COMMENT 'ویژگی‌های کالا مانند رنگ، سایز، مدل و ...',
                    entry_date DATE NOT NULL DEFAULT (CURRENT_DATE) COMMENT 'تاریخ ورود به انبار',
                    last_movement_date DATE NULL COMMENT 'تاریخ آخرین جابجایی',
                    current_invoice_id INTEGER NULL COMMENT 'فاکتور فروش (اگر فروخته شده)',
                    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                    PRIMARY KEY (id),
                    FOREIGN KEY (business_id) REFERENCES businesses (id) ON DELETE CASCADE,
                    FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE CASCADE,
                    FOREIGN KEY (warehouse_id) REFERENCES warehouses (id) ON DELETE SET NULL,
                    FOREIGN KEY (current_invoice_id) REFERENCES documents (id) ON DELETE SET NULL,
                    UNIQUE KEY uq_product_instances_business_serial (business_id, serial_number),
                    UNIQUE KEY uq_product_instances_business_barcode (business_id, barcode),
                    INDEX idx_product_instances_product (product_id),
                    INDEX idx_product_instances_warehouse (warehouse_id),
                    INDEX idx_product_instances_status (status),
                    INDEX idx_product_instances_business (business_id)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            """))
            conn.commit()
            print("product_instances table created successfully!")
        else:
            print("product_instances table already exists.")
        
        # افزودن فیلد instance_ids به warehouse_document_lines
        if 'warehouse_document_lines' in tables:
            warehouse_document_lines_columns = {c['name'] for c in inspector.get_columns('warehouse_document_lines')}
            if 'instance_ids' not in warehouse_document_lines_columns:
                print("Adding instance_ids column to warehouse_document_lines...")
                conn.execute(text("""
                    ALTER TABLE warehouse_document_lines 
                    ADD COLUMN instance_ids JSON NULL 
                    COMMENT 'لیست ID کالاهای یونیک (برای inventory_mode=unique)'
                """))
                conn.commit()
                print("instance_ids column added successfully!")
            else:
                print("instance_ids column already exists.")
        
        print("\nMigration completed successfully!")

if __name__ == "__main__":
    try:
        run_migration()
    except Exception as e:
        print(f"Error running migration: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

