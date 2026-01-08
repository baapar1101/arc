#!/usr/bin/env python3
"""
اسکریپت برای بررسی و reset کردن تمام sequence های PostgreSQL
که از مقدار واقعی id عقب‌تر مانده‌اند
"""

import sys
import os

# اضافه کردن مسیر پروژه به path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import create_engine, text
from adapters.db.session import get_settings

def get_all_sequences(engine):
    """دریافت لیست تمام sequence ها و جدول‌های مربوطه"""
    query = text("""
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
    """)
    
    with engine.connect() as conn:
        result = conn.execute(query)
        return result.fetchall()

def check_and_fix_sequence(engine, sequence_name, table_name):
    """بررسی و reset کردن یک sequence"""
    try:
        with engine.connect() as conn:
            # دریافت مقدار فعلی sequence
            seq_query = text(f"SELECT last_value FROM {sequence_name}")
            current_val = conn.execute(seq_query).scalar()
            
            # دریافت MAX(id) از جدول
            max_id_query = text(f"SELECT COALESCE(MAX(id), 0) FROM {table_name}")
            max_id = conn.execute(max_id_query).scalar()
            
            if current_val < max_id:
                # Reset کردن sequence
                fix_query = text(f"SELECT setval('{sequence_name}', {max_id}, true)")
                new_val = conn.execute(fix_query).scalar()
                conn.commit()
                return {
                    'sequence': sequence_name,
                    'table': table_name,
                    'old_value': current_val,
                    'max_id': max_id,
                    'new_value': new_val,
                    'fixed': True
                }
            else:
                return {
                    'sequence': sequence_name,
                    'table': table_name,
                    'old_value': current_val,
                    'max_id': max_id,
                    'new_value': current_val,
                    'fixed': False
                }
    except Exception as e:
        return {
            'sequence': sequence_name,
            'table': table_name,
            'error': str(e),
            'fixed': False
        }

def main():
    print("🔧 شروع بررسی تمام sequence های دیتابیس...\n")
    
    try:
        settings = get_settings()
        
        # استفاده از postgresql_dsn که quote_plus را برای password انجام می‌دهد
        # اما باید postgresql+psycopg2 را به postgresql تبدیل کنیم
        dsn = settings.postgresql_dsn.replace('postgresql+psycopg2://', 'postgresql://')
        engine = create_engine(dsn)
        
        # دریافت لیست sequence ها
        sequences = get_all_sequences(engine)
        
        if not sequences:
            print("⚠️  هیچ sequence یافت نشد!")
            return
        
        print(f"📋 تعداد {len(sequences)} sequence یافت شد\n")
        print("=" * 80)
        
        fixed_count = 0
        ok_count = 0
        error_count = 0
        issues = []
        
        for seq_info in sequences:
            sequence_name = seq_info[0]
            table_name = seq_info[1]
            
            result = check_and_fix_sequence(engine, sequence_name, table_name)
            
            if 'error' in result:
                print(f"❌ {sequence_name:50s} (جدول: {table_name:30s}) - خطا: {result['error']}")
                error_count += 1
            elif result['fixed']:
                print(f"🔧 {sequence_name:50s} (جدول: {table_name:30s})")
                print(f"   {result['old_value']:>10} → {result['new_value']:<10} (MAX(id): {result['max_id']})")
                issues.append(result)
                fixed_count += 1
            else:
                # فقط sequence های مشکل‌دار را نمایش بدهیم
                if result['old_value'] < result['max_id']:
                    print(f"⚠️  {sequence_name:50s} (جدول: {table_name:30s})")
                    print(f"   sequence: {result['old_value']}, MAX(id): {result['max_id']}")
                    issues.append(result)
                ok_count += 1
        
        print("=" * 80)
        print(f"\n✅ کار تمام شد!")
        print(f"   ✓ {ok_count} sequence به‌روز است")
        if fixed_count > 0:
            print(f"   🔧 {fixed_count} sequence reset شد")
        if error_count > 0:
            print(f"   ❌ {error_count} خطا")
        
        if issues:
            print(f"\n📋 خلاصه sequence های reset شده:")
            for issue in issues:
                if issue.get('fixed'):
                    print(f"   - {issue['sequence']} (جدول: {issue['table']}): {issue['old_value']} → {issue['new_value']}")
        
        engine.dispose()
        
    except Exception as e:
        print(f"❌ خطای عمومی: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    main()

