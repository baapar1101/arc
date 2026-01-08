#!/usr/bin/env python3
"""
اسکریپت مانیتور پیشرفت Migration
این اسکریپت وضعیت migration را نشان می‌دهد
"""

import json
import sys
import os
from pathlib import Path
from datetime import datetime
from typing import Dict, Any

def load_checkpoint(checkpoint_file: str = 'migration_checkpoint.json') -> Dict[str, Any]:
    """بارگذاری checkpoint"""
    checkpoint_path = Path(checkpoint_file)
    if not checkpoint_path.exists():
        return {}
    
    try:
        with open(checkpoint_path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception as e:
        print(f"❌ خطا در خواندن checkpoint: {e}")
        return {}

def get_mysql_table_count(mysql_config: Dict[str, Any]) -> Dict[str, int]:
    """دریافت تعداد ردیف‌های جداول MySQL"""
    try:
        from sqlalchemy import create_engine, text
        
        mysql_dsn = f"mysql+pymysql://{mysql_config['user']}:{mysql_config['password']}@{mysql_config['host']}:{mysql_config['port']}/{mysql_config['database']}"
        engine = create_engine(mysql_dsn, echo=False, pool_pre_ping=True, connect_args={'connect_timeout': 5})
        
        with engine.connect() as conn:
            result = conn.execute(text("""
                SELECT table_name, table_rows
                FROM information_schema.tables 
                WHERE table_schema = :schema 
                AND table_name != 'alembic_version'
                ORDER BY table_name
            """), {'schema': mysql_config['database']})
            
            counts = {}
            for row in result:
                counts[row[0]] = row[1] if row[1] else 0
            
        engine.dispose()
        return counts
    except Exception as e:
        print(f"⚠️ خطا در اتصال به MySQL: {e}")
        return {}

def get_postgres_table_count(postgres_config: Dict[str, Any]) -> Dict[str, int]:
    """دریافت تعداد ردیف‌های جداول PostgreSQL"""
    try:
        from sqlalchemy import create_engine, text
        from urllib.parse import quote_plus
        
        postgres_dsn = f"postgresql+psycopg2://{postgres_config['user']}:{quote_plus(postgres_config['password'])}@{postgres_config['host']}:{postgres_config['port']}/{postgres_config['database']}"
        engine = create_engine(postgres_dsn, echo=False, pool_pre_ping=True, connect_args={'connect_timeout': 5})
        
        with engine.connect() as conn:
            result = conn.execute(text("""
                SELECT table_name 
                FROM information_schema.tables 
                WHERE table_schema = 'public' 
                AND table_type = 'BASE TABLE'
                AND table_name != 'alembic_version'
                ORDER BY table_name
            """))
            
            counts = {}
            for row in result:
                table_name = row[0]
                count_result = conn.execute(text(f'SELECT COUNT(*) FROM "{table_name}"'))
                counts[table_name] = count_result.scalar()
            
        engine.dispose()
        return counts
    except Exception as e:
        print(f"⚠️ خطا در اتصال به PostgreSQL: {e}")
        return {}

def format_number(num: int) -> str:
    """فرمت عدد با کاما"""
    return f"{num:,}"

def calculate_progress(checkpoint_data: Dict[str, Any], mysql_counts: Dict[str, int], postgres_counts: Dict[str, int]) -> Dict[str, Any]:
    """محاسبه پیشرفت"""
    tables_data = checkpoint_data.get('tables', {})
    
    total_tables = len(mysql_counts)
    completed_tables = sum(1 for t in tables_data.values() if t.get('completed', False))
    
    total_rows_mysql = sum(mysql_counts.values())
    total_rows_postgres = sum(postgres_counts.values())
    
    completed_tables_list = []
    in_progress_tables = []
    failed_tables = []
    
    for table_name, table_data in tables_data.items():
        if table_data.get('completed', False):
            completed_tables_list.append(table_name)
        elif table_data.get('rows_migrated', 0) > 0:
            in_progress_tables.append({
                'name': table_name,
                'migrated': table_data.get('rows_migrated', 0),
                'total': mysql_counts.get(table_name, 0),
                'last_id': table_data.get('last_id'),
            })
    
    # جداول کامل شده اما در checkpoint نیستند
    for table_name in postgres_counts:
        if table_name not in tables_data and postgres_counts[table_name] > 0:
            if postgres_counts[table_name] == mysql_counts.get(table_name, 0):
                completed_tables_list.append(table_name)
                completed_tables += 1
    
    progress_percent = (completed_tables / total_tables * 100) if total_tables > 0 else 0
    rows_progress_percent = (total_rows_postgres / total_rows_mysql * 100) if total_rows_mysql > 0 else 0
    
    return {
        'total_tables': total_tables,
        'completed_tables': completed_tables,
        'progress_percent': progress_percent,
        'total_rows_mysql': total_rows_mysql,
        'total_rows_postgres': total_rows_postgres,
        'rows_progress_percent': rows_progress_percent,
        'completed_tables_list': completed_tables_list,
        'in_progress_tables': in_progress_tables,
        'failed_tables': failed_tables,
    }

def print_status(checkpoint_data: Dict[str, Any], progress: Dict[str, Any]):
    """نمایش وضعیت"""
    print("="*70)
    print("📊 وضعیت Migration")
    print("="*70)
    
    if checkpoint_data.get('started_at'):
        started = datetime.fromisoformat(checkpoint_data['started_at'])
        print(f"🕐 شروع: {started.strftime('%Y-%m-%d %H:%M:%S')}")
    
    if checkpoint_data.get('updated_at'):
        updated = datetime.fromisoformat(checkpoint_data['updated_at'])
        elapsed = datetime.now() - updated
        print(f"🕐 آخرین بروزرسانی: {updated.strftime('%Y-%m-%d %H:%M:%S')} ({elapsed.total_seconds():.0f} ثانیه پیش)")
    
    print()
    print(f"📋 جداول:")
    print(f"   ✅ کامل شده: {progress['completed_tables']}/{progress['total_tables']} ({progress['progress_percent']:.1f}%)")
    print(f"   ⏳ در حال انجام: {len(progress['in_progress_tables'])}")
    
    print()
    print(f"📊 ردیف‌ها:")
    print(f"   MySQL:     {format_number(progress['total_rows_mysql'])}")
    print(f"   PostgreSQL: {format_number(progress['total_rows_postgres'])} ({progress['rows_progress_percent']:.1f}%)")
    
    print()
    print("="*70)
    print(f"🎯 پیشرفت کلی: {progress['progress_percent']:.1f}%")
    print("="*70)
    
    if progress['in_progress_tables']:
        print()
        print("⏳ جداول در حال انجام:")
        for table in progress['in_progress_tables'][:5]:  # فقط 5 تا اول
            table_progress = (table['migrated'] / table['total'] * 100) if table['total'] > 0 else 0
            print(f"   📊 {table['name']}: {format_number(table['migrated'])}/{format_number(table['total'])} ({table_progress:.1f}%)")
        if len(progress['in_progress_tables']) > 5:
            print(f"   ... و {len(progress['in_progress_tables']) - 5} جدول دیگر")
    
    print()

def main():
    import argparse
    
    parser = argparse.ArgumentParser(description='مانیتور پیشرفت Migration')
    parser.add_argument('--checkpoint-file', default='migration_checkpoint.json', help='Checkpoint file path')
    parser.add_argument('--mysql-host', default='185.8.172.57', help='MySQL host')
    parser.add_argument('--mysql-user', default='root', help='MySQL user')
    parser.add_argument('--mysql-password', default='136431', help='MySQL password')
    parser.add_argument('--mysql-database', default='hesabixpy', help='MySQL database')
    parser.add_argument('--postgres-host', default='localhost', help='PostgreSQL host')
    parser.add_argument('--postgres-user', default='hesabix', help='PostgreSQL user')
    parser.add_argument('--postgres-password', default='@@babaK24055', help='PostgreSQL password')
    parser.add_argument('--postgres-database', default='hesabix', help='PostgreSQL database')
    parser.add_argument('--watch', action='store_true', help='Watch mode - نمایش مداوم')
    parser.add_argument('--interval', type=int, default=5, help='Interval برای watch mode (ثانیه)')
    
    args = parser.parse_args()
    
    mysql_config = {
        'host': args.mysql_host,
        'user': args.mysql_user,
        'password': args.mysql_password,
        'database': args.mysql_database,
        'port': 3306,
    }
    
    postgres_config = {
        'host': args.postgres_host,
        'user': args.postgres_user,
        'password': args.postgres_password,
        'database': args.postgres_database,
        'port': 5432,
    }
    
    if args.watch:
        import time
        while True:
            os.system('clear')
            checkpoint_data = load_checkpoint(args.checkpoint_file)
            mysql_counts = get_mysql_table_count(mysql_config)
            postgres_counts = get_postgres_table_count(postgres_config)
            progress = calculate_progress(checkpoint_data, mysql_counts, postgres_counts)
            print_status(checkpoint_data, progress)
            print(f"\n⏳ بروزرسانی بعدی در {args.interval} ثانیه... (Ctrl+C برای خروج)")
            time.sleep(args.interval)
    else:
        checkpoint_data = load_checkpoint(args.checkpoint_file)
        if not checkpoint_data:
            print("⚠️ Checkpoint file یافت نشد. Migration شروع نشده است.")
            sys.exit(1)
        
        mysql_counts = get_mysql_table_count(mysql_config)
        postgres_counts = get_postgres_table_count(postgres_config)
        progress = calculate_progress(checkpoint_data, mysql_counts, postgres_counts)
        print_status(checkpoint_data, progress)

if __name__ == '__main__':
    main()


