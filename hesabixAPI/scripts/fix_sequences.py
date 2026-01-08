#!/usr/bin/env python3
"""
اسکریپت برای reset کردن sequence های PostgreSQL که از مقدار واقعی id عقب‌تر مانده‌اند
این مشکل معمولاً بعد از migrate کردن داده‌ها از MySQL به PostgreSQL رخ می‌دهد
"""

import psycopg2
from psycopg2 import sql
from psycopg2.extras import RealDictCursor

# تنظیمات اتصال به دیتابیس
DB_CONFIG = {
    "dbname": "hesabix",
    "user": "hesabix",
    "password": "hesabix",
    "host": "127.0.0.1",
    "port": "5432"
}

def get_sequence_table_mapping(cursor):
    """دریافت mapping بین sequence ها و جدول‌های مربوطه"""
    query = """
    SELECT 
        s.sequence_name,
        c.table_name,
        c.column_name
    FROM information_schema.sequences s
    JOIN information_schema.columns c 
        ON c.column_default LIKE '%' || s.sequence_name || '%'
    WHERE s.sequence_schema = 'public'
      AND c.table_schema = 'public'
      AND c.column_name = 'id'
      AND c.table_name = REPLACE(s.sequence_name, '_id_seq', '')
    ORDER BY s.sequence_name;
    """
    cursor.execute(query)
    return cursor.fetchall()

def fix_sequence(cursor, sequence_name, table_name):
    """Reset کردن یک sequence به MAX(id) جدول مربوطه"""
    try:
        # دریافت MAX(id) از جدول
        max_id_query = sql.SQL("SELECT COALESCE(MAX(id), 0) FROM {}").format(
            sql.Identifier(table_name)
        )
        cursor.execute(max_id_query)
        max_id = cursor.fetchone()[0]
        
        # Reset کردن sequence
        setval_query = sql.SQL("SELECT setval({}, {}, true)").format(
            sql.Literal(sequence_name),
            sql.Literal(max_id)
        )
        cursor.execute(setval_query)
        new_val = cursor.fetchone()[0]
        
        return max_id, new_val
    except Exception as e:
        print(f"  ❌ خطا در reset کردن {sequence_name}: {e}")
        return None, None

def main():
    print("🔧 شروع بررسی و رفع sequence های PostgreSQL...\n")
    
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        
        # دریافت لیست sequence ها
        mappings = get_sequence_table_mapping(cursor)
        
        if not mappings:
            print("⚠️  هیچ sequence یافت نشد!")
            return
        
        print(f"📋 تعداد {len(mappings)} sequence یافت شد\n")
        
        fixed_count = 0
        skipped_count = 0
        
        for mapping in mappings:
            sequence_name = mapping['sequence_name']
            table_name = mapping['table_name']
            
            print(f"🔍 بررسی {sequence_name} (جدول: {table_name})...")
            
            # دریافت مقدار فعلی sequence
            cursor.execute(sql.SQL("SELECT last_value FROM {}").format(
                sql.Identifier(sequence_name)
            ))
            current_seq_val = cursor.fetchone()[0]
            
            # دریافت MAX(id) از جدول
            cursor.execute(sql.SQL("SELECT COALESCE(MAX(id), 0) FROM {}").format(
                sql.Identifier(table_name)
            ))
            max_id = cursor.fetchone()[0]
            
            if current_seq_val < max_id:
                print(f"  ⚠️  sequence عقب‌تر است: {current_seq_val} < {max_id}")
                max_id_after, new_val = fix_sequence(cursor, sequence_name, table_name)
                if new_val is not None:
                    print(f"  ✅ sequence reset شد: {current_seq_val} → {new_val}")
                    fixed_count += 1
            else:
                print(f"  ✓ sequence به‌روز است: {current_seq_val} >= {max_id}")
                skipped_count += 1
        
        # Commit تغییرات
        conn.commit()
        
        print(f"\n✅ کار تمام شد!")
        print(f"   - {fixed_count} sequence reset شد")
        print(f"   - {skipped_count} sequence به‌روز بود")
        
        cursor.close()
        conn.close()
        
    except psycopg2.Error as e:
        print(f"❌ خطای دیتابیس: {e}")
        if conn:
            conn.rollback()
    except Exception as e:
        print(f"❌ خطای عمومی: {e}")

if __name__ == "__main__":
    main()

