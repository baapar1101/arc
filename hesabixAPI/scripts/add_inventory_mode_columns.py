#!/usr/bin/env python3
"""
اسکریپت افزودن ستون‌های inventory_mode، track_serial و track_barcode به جدول products
این اسکریپت فقط در صورت نبودن ستون‌ها، آن‌ها را اضافه می‌کند.
"""

import sys
import os

# اضافه کردن مسیر پروژه به sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import inspect, text
from adapters.db.session import engine


def main() -> None:
    """افزودن ستون‌های موردنیاز به جدول products"""
    with engine.connect() as conn:
        inspector = inspect(conn)
        
        # بررسی وجود جدول products
        if 'products' not in inspector.get_table_names():
            print("جدول products یافت نشد!")
            return
        
        # دریافت لیست ستون‌های موجود
        columns = {c['name'] for c in inspector.get_columns('products')}
        
        # افزودن ستون‌های موردنیاز
        ddl_statements = []
        
        if 'inventory_mode' not in columns:
            ddl_statements.append(
                "ALTER TABLE `products` ADD COLUMN `inventory_mode` VARCHAR(16) NULL DEFAULT 'bulk' COMMENT 'حالت موجودی: bulk (فله‌ای) یا unique (یونیک)'"
            )
            print("ستون inventory_mode اضافه خواهد شد")
        else:
            print("ستون inventory_mode از قبل وجود دارد")
        
        if 'track_serial' not in columns:
            ddl_statements.append(
                "ALTER TABLE `products` ADD COLUMN `track_serial` BOOLEAN NOT NULL DEFAULT FALSE COMMENT 'ردیابی سریال نامبر برای کالاهای یونیک'"
            )
            print("ستون track_serial اضافه خواهد شد")
        else:
            print("ستون track_serial از قبل وجود دارد")
        
        if 'track_barcode' not in columns:
            ddl_statements.append(
                "ALTER TABLE `products` ADD COLUMN `track_barcode` BOOLEAN NOT NULL DEFAULT FALSE COMMENT 'ردیابی بارکد برای کالاهای یونیک'"
            )
            print("ستون track_barcode اضافه خواهد شد")
        else:
            print("ستون track_barcode از قبل وجود دارد")
        
        # اجرای دستورات SQL
        if ddl_statements:
            print(f"\nاجرای {len(ddl_statements)} دستور SQL...")
            for stmt in ddl_statements:
                try:
                    conn.execute(text(stmt))
                    conn.commit()
                    print(f"✓ دستور اجرا شد: {stmt[:60]}...")
                except Exception as e:
                    print(f"✗ خطا در اجرای دستور: {e}")
                    conn.rollback()
            
            print("\n✓ تمام ستون‌ها با موفقیت اضافه شدند!")
        else:
            print("\n✓ همه ستون‌ها از قبل وجود دارند، نیازی به تغییر نیست.")


if __name__ == "__main__":
    main()

