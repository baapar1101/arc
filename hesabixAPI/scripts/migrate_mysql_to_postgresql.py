#!/usr/bin/env python3
"""
اسکریپت انتقال داده از MySQL به PostgreSQL
این اسکریپت داده‌های MySQL را به PostgreSQL منتقل می‌کند و seed data ها را پاک می‌کند

ویژگی‌ها:
- پاک‌سازی seed data از PostgreSQL
- انتقال داده با قابلیت resume/checkpoint
- پردازش batch به batch برای جداول بزرگ
- مدیریت Foreign Keys
- تبدیل نوع داده‌ها (MySQL → PostgreSQL)
- Skip کردن alembic_version
"""

import sys
import os
import argparse
import json
from typing import List, Dict, Any, Optional, Set
from datetime import datetime
from decimal import Decimal
from pathlib import Path

# اضافه کردن مسیر پروژه به sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import create_engine, text, inspect
from sqlalchemy.orm import sessionmaker, Session
from sqlalchemy.exc import SQLAlchemyError
from urllib.parse import quote_plus

# Seed data tables که باید پاک شوند
SEED_DATA_TABLES = [
    'support_categories',
    'support_priorities', 
    'support_statuses',
    'currencies',
    'tax_types',
    'system_settings',
    'accounts',  # چارت حساب‌ها
    'marketplace_plugins',
    'marketplace_plugin_plans',
]

# جداولی که نباید منتقل شوند
EXCLUDED_TABLES = [
    'alembic_version',  # migration table
    'notification_delivery_attempts',  # جدول log که اطلاعات مفیدی ندارد
    'notification_outbox',  # جدول queue/log که بعد از پردازش مفید نیست
    'monitoring_metrics',  # جدول monitoring/log که اطلاعات مفیدی ندارد
    'monitoring_service_status',  # جدول monitoring/log که اطلاعات مفیدی ندارد
]

# تنظیمات اتصال پیش‌فرض
DEFAULT_MYSQL_CONFIG = {
    'host': '185.8.172.57',
    'user': 'root',
    'password': '136431',
    'database': 'hesabixpy',
    'port': 3306,
}

DEFAULT_POSTGRES_CONFIG = {
    'host': 'localhost',
    'user': 'hesabix',
    'password': '@@babaK24055',
    'database': 'hesabix',
    'port': 5432,
}


class CheckpointManager:
    """مدیریت checkpoint برای resume کردن انتقال"""
    
    def __init__(self, checkpoint_file: str = 'migration_checkpoint.json'):
        self.checkpoint_file = Path(checkpoint_file)
        self.checkpoint_data = {}
        self.load()
    
    def load(self):
        """بارگذاری checkpoint از فایل"""
        if self.checkpoint_file.exists():
            try:
                with open(self.checkpoint_file, 'r', encoding='utf-8') as f:
                    self.checkpoint_data = json.load(f)
                print(f"✅ Checkpoint بارگذاری شد: {len(self.checkpoint_data.get('tables', {}))} جدول")
            except Exception as e:
                print(f"⚠️ خطا در بارگذاری checkpoint: {e}")
                self.checkpoint_data = {}
        else:
            self.checkpoint_data = {
                'started_at': datetime.now().isoformat(),
                'tables': {},
            }
    
    def save(self):
        """ذخیره checkpoint در فایل"""
        try:
            self.checkpoint_data['updated_at'] = datetime.now().isoformat()
            with open(self.checkpoint_file, 'w', encoding='utf-8') as f:
                json.dump(self.checkpoint_data, f, indent=2, ensure_ascii=False)
        except Exception as e:
            print(f"⚠️ خطا در ذخیره checkpoint: {e}")
    
    def get_table_checkpoint(self, table_name: str) -> Dict[str, Any]:
        """دریافت checkpoint یک جدول"""
        return self.checkpoint_data.get('tables', {}).get(table_name, {})
    
    def set_table_checkpoint(self, table_name: str, last_id: Any, rows_migrated: int, completed: bool = False):
        """ذخیره checkpoint یک جدول"""
        if 'tables' not in self.checkpoint_data:
            self.checkpoint_data['tables'] = {}
        
        self.checkpoint_data['tables'][table_name] = {
            'last_id': str(last_id) if last_id is not None else None,
            'rows_migrated': rows_migrated,
            'completed': completed,
            'updated_at': datetime.now().isoformat(),
        }
        self.save()
    
    def clear(self):
        """پاک کردن checkpoint"""
        if self.checkpoint_file.exists():
            backup_file = self.checkpoint_file.with_suffix('.json.bak')
            self.checkpoint_file.rename(backup_file)
            print(f"✅ Checkpoint پاک شد و در {backup_file} backup شد")
        self.checkpoint_data = {
            'started_at': datetime.now().isoformat(),
            'tables': {},
        }
    
    def is_table_completed(self, table_name: str) -> bool:
        """بررسی اینکه آیا جدول کامل شده است"""
        return self.get_table_checkpoint(table_name).get('completed', False)


class DataTypeConverter:
    """تبدیل نوع داده‌های MySQL به PostgreSQL"""
    
    @staticmethod
    def convert_value(value: Any, mysql_type: str) -> Any:
        """تبدیل یک مقدار از MySQL به PostgreSQL"""
        if value is None:
            return None
        
        # تبدیل boolean
        if mysql_type.startswith('tinyint(1)'):
            return bool(value) if value is not None else None
        
        # تبدیل datetime
        if 'datetime' in mysql_type or 'timestamp' in mysql_type:
            if isinstance(value, datetime):
                return value
            if isinstance(value, str):
                try:
                    return datetime.fromisoformat(value.replace('Z', '+00:00'))
                except:
                    try:
                        return datetime.strptime(value, '%Y-%m-%d %H:%M:%S')
                    except:
                        return None
            return None
        
        # تبدیل JSON
        if mysql_type.startswith('json'):
            if isinstance(value, str):
                try:
                    return json.loads(value)
                except:
                    return value
            return value
        
        # تبدیل Decimal
        if 'decimal' in mysql_type or 'numeric' in mysql_type:
            if isinstance(value, (int, float, str)):
                try:
                    return Decimal(str(value))
                except:
                    return None
        
        return value
    
    @staticmethod
    def convert_row(row: Dict[str, Any], column_types: Dict[str, str], postgres_columns: Optional[Dict[str, str]] = None) -> Dict[str, Any]:
        """تبدیل یک ردیف کامل"""
        converted = {}
        for key, value in row.items():
            mysql_type = column_types.get(key, '')
            converted_value = DataTypeConverter.convert_value(value, mysql_type)
            
            # تبدیل '[null]' به None (مشکل در برخی داده‌ها)
            if isinstance(converted_value, str) and converted_value.lower() == '[null]':
                converted_value = None
            
            # اگر PostgreSQL column type JSON/JSONB است، باید dict/list را به JSON string تبدیل کنیم
            if postgres_columns and (postgres_columns.get(key, '').startswith('json') or postgres_columns.get(key, '').startswith('jsonb')):
                if isinstance(converted_value, (dict, list)):
                    converted_value = json.dumps(converted_value, ensure_ascii=False)
            
            converted[key] = converted_value
        return converted


class MySQLToPostgreSQLMigration:
    """کلاس اصلی انتقال داده از MySQL به PostgreSQL"""
    
    def __init__(self, mysql_config: Dict[str, Any], postgres_config: Dict[str, Any],
                 checkpoint_file: str = 'migration_checkpoint.json',
                 batch_size: int = 1000):
        self.mysql_config = mysql_config
        self.postgres_config = postgres_config
        self.batch_size = batch_size
        self.checkpoint = CheckpointManager(checkpoint_file)
        
        # اتصال به MySQL
        mysql_dsn = f"mysql+pymysql://{mysql_config['user']}:{mysql_config['password']}@{mysql_config['host']}:{mysql_config['port']}/{mysql_config['database']}"
        self.mysql_engine = create_engine(
            mysql_dsn,
            echo=False,
            pool_pre_ping=True,
            pool_size=10,
            max_overflow=20,
            pool_recycle=3600,
            connect_args={
                'connect_timeout': 60,
                'charset': 'utf8mb4',
            }
        )
        self.mysql_session = sessionmaker(bind=self.mysql_engine)()
        
        # اتصال به PostgreSQL
        postgres_dsn = f"postgresql+psycopg2://{postgres_config['user']}:{quote_plus(postgres_config['password'])}@{postgres_config['host']}:{postgres_config['port']}/{postgres_config['database']}"
        self.postgres_engine = create_engine(
            postgres_dsn,
            echo=False,
            pool_pre_ping=True,
            pool_size=10,
            max_overflow=20,
            pool_recycle=3600,
            connect_args={
                'connect_timeout': 10,
            }
        )
        self.postgres_session = sessionmaker(bind=self.postgres_engine)()
        
        # آمار
        self.stats = {
            'tables_processed': 0,
            'tables_completed': 0,
            'total_rows_migrated': 0,
            'errors': 0,
            'error_details': [],
        }
    
    def get_mysql_tables(self) -> List[str]:
        """دریافت لیست جداول MySQL"""
        query = text("""
            SELECT table_name 
            FROM information_schema.tables 
            WHERE table_schema = :schema
            ORDER BY table_name
        """)
        result = self.mysql_session.execute(query, {'schema': self.mysql_config['database']})
        tables = [row[0] for row in result]
        
        # فیلتر کردن جداول excluded
        tables = [t for t in tables if t not in EXCLUDED_TABLES]
        
        return tables
    
    def get_table_columns(self, table_name: str, db_type: str = 'mysql') -> Dict[str, str]:
        """دریافت ستون‌ها و نوع داده‌های یک جدول"""
        if db_type == 'mysql':
            query = text("""
                SELECT column_name, data_type, column_type
                FROM information_schema.columns
                WHERE table_schema = :schema AND table_name = :table
                ORDER BY ordinal_position
            """)
            result = self.mysql_session.execute(query, {
                'schema': self.mysql_config['database'],
                'table': table_name,
            })
            return {row[0]: row[2] for row in result}  # column_type شامل کامل مثل tinyint(1)
        else:
            query = text("""
                SELECT column_name, data_type
                FROM information_schema.columns
                WHERE table_schema = 'public' AND table_name = :table
                ORDER BY ordinal_position
            """)
            result = self.postgres_session.execute(query, {'table': table_name})
            return {row[0]: row[1] for row in result}
    
    def get_table_row_count(self, table_name: str, db_type: str = 'mysql') -> int:
        """دریافت تعداد ردیف‌های یک جدول"""
        if db_type == 'mysql':
            query = text(f"SELECT COUNT(*) FROM `{table_name}`")
            result = self.mysql_session.execute(query)
        else:
            query = text(f'SELECT COUNT(*) FROM "{table_name}"')
            result = self.postgres_session.execute(query)
        return result.scalar()
    
    def clear_seed_data(self):
        """پاک کردن seed data از PostgreSQL"""
        print("\n" + "="*60)
        print("🧹 پاک کردن seed data از PostgreSQL...")
        print("="*60)
        
        # غیرفعال کردن Foreign Keys موقتاً
        self.disable_foreign_keys()
        
        try:
            for table_name in SEED_DATA_TABLES:
                # بررسی وجود جدول
                check_query = text("""
                    SELECT EXISTS (
                        SELECT FROM information_schema.tables 
                        WHERE table_schema = 'public' AND table_name = :table
                    )
                """)
                exists = self.postgres_session.execute(check_query, {'table': table_name}).scalar()
                
                if exists:
                    delete_query = text(f'DELETE FROM "{table_name}"')
                    result = self.postgres_session.execute(delete_query)
                    deleted_count = result.rowcount
                    self.postgres_session.commit()
                    print(f"  ✅ {table_name}: {deleted_count} ردیف پاک شد")
                else:
                    print(f"  ⚠️ {table_name}: جدول وجود ندارد")
        
        except Exception as e:
            self.postgres_session.rollback()
            print(f"  ❌ خطا در پاک کردن seed data: {e}")
            raise
        finally:
            # فعال کردن مجدد Foreign Keys
            self.enable_foreign_keys()
    
    def disable_foreign_keys(self):
        """غیرفعال کردن Foreign Key constraints موقتاً"""
        try:
            # PostgreSQL
            self.postgres_session.execute(text("SET session_replication_role = 'replica'"))
            self.postgres_session.commit()
        except Exception as e:
            print(f"⚠️ خطا در غیرفعال کردن Foreign Keys: {e}")
    
    def enable_foreign_keys(self):
        """فعال کردن مجدد Foreign Key constraints"""
        try:
            # PostgreSQL
            self.postgres_session.execute(text("SET session_replication_role = 'origin'"))
            self.postgres_session.commit()
        except Exception as e:
            print(f"⚠️ خطا در فعال کردن Foreign Keys: {e}")
    
    def migrate_table(self, table_name: str, skip_if_completed: bool = True) -> bool:
        """انتقال یک جدول از MySQL به PostgreSQL"""
        print(f"\n📊 انتقال جدول: {table_name}")
        print("-" * 60)
        
        # بررسی اینکه آیا جدول در EXCLUDED_TABLES است
        if table_name in EXCLUDED_TABLES:
            print(f"  ⏭️ این جدول در لیست excluded است (skip)")
            # علامت‌گذاری به عنوان کامل شده در checkpoint
            self.checkpoint.set_table_checkpoint(table_name, None, 0, completed=True)
            return True
        
        # بررسی اینکه آیا قبلاً کامل شده است
        if skip_if_completed and self.checkpoint.is_table_completed(table_name):
            print(f"  ⏭️ این جدول قبلاً کامل شده است (skip)")
            return True
        
        try:
            # دریافت اطلاعات جدول
            mysql_columns = self.get_table_columns(table_name, 'mysql')
            postgres_columns = self.get_table_columns(table_name, 'postgres')
            
            # بررسی وجود جدول در PostgreSQL - اگر وجود ندارد، ایجادش کنیم
            if not postgres_columns:
                print(f"  📝 جدول {table_name} در PostgreSQL وجود ندارد - در حال ایجاد...")
                # Import functions dynamically
                import importlib.util
                create_table_module_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "create_table_from_mysql.py")
                spec = importlib.util.spec_from_file_location("create_table_from_mysql", create_table_module_path)
                create_table_module = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(create_table_module)
                get_table_structure_mysql = create_table_module.get_table_structure_mysql
                get_primary_key_mysql = create_table_module.get_primary_key_mysql
                get_indexes_mysql = create_table_module.get_indexes_mysql
                create_table_postgresql = create_table_module.create_table_postgresql
                
                try:
                    # دریافت ساختار جدول از MySQL
                    mysql_structure = get_table_structure_mysql(
                        self.mysql_session, 
                        table_name, 
                        self.mysql_config['database']
                    )
                    mysql_pk = get_primary_key_mysql(
                        self.mysql_session, 
                        table_name, 
                        self.mysql_config['database']
                    )
                    mysql_indexes = get_indexes_mysql(
                        self.mysql_session, 
                        table_name, 
                        self.mysql_config['database']
                    )
                    
                    # ایجاد جدول در PostgreSQL
                    success = create_table_postgresql(
                        self.postgres_session,
                        table_name,
                        mysql_structure,
                        mysql_pk,
                        mysql_indexes
                    )
                    
                    if not success:
                        return False
                    
                    # دریافت مجدد ستون‌ها
                    postgres_columns = self.get_table_columns(table_name, 'postgres')
                    if not postgres_columns:
                        print(f"  ❌ خطا: جدول ایجاد شد اما ستون‌ها یافت نشدند")
                        return False
                    
                except Exception as e:
                    print(f"  ❌ خطا در ایجاد جدول {table_name}: {e}")
                    return False
            
            # فیلتر کردن ستون‌هایی که در PostgreSQL وجود دارند
            common_columns = [col for col in mysql_columns.keys() if col in postgres_columns.keys()]
            if not common_columns:
                print(f"  ⚠️ هیچ ستون مشترکی یافت نشد (skip)")
                return False
            
            # دریافت تعداد کل ردیف‌ها
            total_rows = self.get_table_row_count(table_name, 'mysql')
            print(f"  📈 تعداد کل ردیف‌ها در MySQL: {total_rows:,}")
            
            # دریافت checkpoint
            checkpoint = self.checkpoint.get_table_checkpoint(table_name)
            last_id = checkpoint.get('last_id')
            rows_migrated = checkpoint.get('rows_migrated', 0)
            
            if last_id:
                print(f"  🔄 ادامه از checkpoint: last_id={last_id}, rows_migrated={rows_migrated:,}")
            
            # تعیین primary key
            primary_key = self._get_primary_key(table_name, 'mysql')
            if not primary_key:
                print(f"  ⚠️ Primary key یافت نشد (skip)")
                return False
            
            # انتقال داده‌ها batch به batch
            batch_num = 0
            current_id = int(last_id) if last_id and last_id.isdigit() else 0
            
            while True:
                # دریافت batch از MySQL
                if primary_key:
                    query = text(f"""
                        SELECT * FROM `{table_name}`
                        WHERE `{primary_key}` > :last_id
                        ORDER BY `{primary_key}`
                        LIMIT :limit
                    """)
                else:
                    query = text(f"""
                        SELECT * FROM `{table_name}`
                        LIMIT :limit OFFSET :offset
                    """)
                
                params = {'limit': self.batch_size}
                if primary_key:
                    params['last_id'] = current_id
                else:
                    params['offset'] = rows_migrated
                
                result = self.mysql_session.execute(query, params)
                rows = result.fetchall()
                
                if not rows:
                    break  # تمام ردیف‌ها منتقل شدند
                
                # تبدیل داده‌ها
                converted_rows = []
                for row in rows:
                    row_dict = dict(row._mapping)
                    converted_row = DataTypeConverter.convert_row(row_dict, mysql_columns, postgres_columns)
                    # فیلتر کردن ستون‌های مشترک
                    filtered_row = {k: v for k, v in converted_row.items() if k in common_columns}
                    
                    # مدیریت مقادیر NOT NULL - person_types
                    if table_name == 'persons' and 'person_types' in filtered_row and filtered_row['person_types'] is None:
                        filtered_row['person_types'] = '[]'  # Default empty JSON array
                    
                    converted_rows.append(filtered_row)
                
                # درج در PostgreSQL
                try:
                    self._insert_batch(table_name, converted_rows, common_columns)
                    self.postgres_session.commit()
                    
                    # به‌روزرسانی checkpoint
                    if primary_key:
                        current_id = converted_rows[-1][primary_key]
                        rows_migrated += len(converted_rows)
                        self.checkpoint.set_table_checkpoint(table_name, current_id, rows_migrated, completed=False)
                    
                    batch_num += 1
                    print(f"  ✅ Batch {batch_num}: {len(converted_rows)} ردیف منتقل شد (مجموع: {rows_migrated:,}/{total_rows:,})")
                    
                except Exception as e:
                    self.postgres_session.rollback()
                    print(f"  ❌ خطا در batch {batch_num}: {e}")
                    self.stats['errors'] += 1
                    self.stats['error_details'].append({
                        'table': table_name,
                        'batch': batch_num,
                        'error': str(e),
                    })
                    raise
            
            # علامت‌گذاری جدول به عنوان کامل شده
            self.checkpoint.set_table_checkpoint(table_name, current_id, rows_migrated, completed=True)
            
            # اعتبارسنجی
            postgres_count = self.get_table_row_count(table_name, 'postgres')
            print(f"  ✅ انتقال کامل شد!")
            print(f"  📊 MySQL: {total_rows:,} | PostgreSQL: {postgres_count:,}")
            
            self.stats['tables_completed'] += 1
            self.stats['total_rows_migrated'] += rows_migrated
            
            return True
            
        except Exception as e:
            print(f"  ❌ خطا در انتقال جدول {table_name}: {e}")
            self.stats['errors'] += 1
            self.stats['error_details'].append({
                'table': table_name,
                'error': str(e),
            })
            return False
    
    def _get_primary_key(self, table_name: str, db_type: str = 'mysql') -> Optional[str]:
        """دریافت primary key یک جدول"""
        if db_type == 'mysql':
            query = text("""
                SELECT column_name
                FROM information_schema.key_column_usage
                WHERE table_schema = :schema 
                    AND table_name = :table 
                    AND constraint_name = 'PRIMARY'
                ORDER BY ordinal_position
                LIMIT 1
            """)
            result = self.mysql_session.execute(query, {
                'schema': self.mysql_config['database'],
                'table': table_name,
            })
        else:
            query = text("""
                SELECT column_name
                FROM information_schema.key_column_usage
                WHERE table_schema = 'public' 
                    AND table_name = :table 
                    AND constraint_name LIKE '%_pkey'
                ORDER BY ordinal_position
                LIMIT 1
            """)
            result = self.postgres_session.execute(query, {'table': table_name})
        
        row = result.fetchone()
        return row[0] if row else None
    
    def _insert_batch(self, table_name: str, rows: List[Dict[str, Any]], columns: List[str]):
        """درج یک batch از ردیف‌ها در PostgreSQL"""
        if not rows:
            return
        
        # ساخت INSERT query با ON CONFLICT DO NOTHING برای جلوگیری از duplicate key errors
        columns_str = ', '.join(f'"{col}"' for col in columns)
        placeholders = ', '.join([f':{col}' for col in columns])
        
        # دریافت primary key برای ON CONFLICT
        primary_key = self._get_primary_key(table_name, 'postgres')
        
        if primary_key and primary_key in columns:
            # استفاده از ON CONFLICT DO NOTHING برای جلوگیری از duplicate key
            query = text(f"""
                INSERT INTO "{table_name}" ({columns_str})
                VALUES ({placeholders})
                ON CONFLICT ({primary_key}) DO NOTHING
            """)
        else:
            # اگر primary key نداریم، INSERT عادی
            query = text(f"""
                INSERT INTO "{table_name}" ({columns_str})
                VALUES ({placeholders})
            """)
        
        # آماده‌سازی و درج داده‌ها
        for row in rows:
            # فقط مقادیری که در columns هستند
            row_data = {col: row.get(col) for col in columns}
            self.postgres_session.execute(query, row_data)
    
    def migrate_all(self, clear_seed: bool = True):
        """انتقال تمام جداول"""
        print("="*60)
        print("🚀 شروع انتقال داده از MySQL به PostgreSQL")
        print("="*60)
        
        # پاک کردن seed data
        if clear_seed:
            self.clear_seed_data()
        
        # غیرفعال کردن Foreign Keys
        self.disable_foreign_keys()
        
        try:
            # دریافت لیست جداول
            tables = self.get_mysql_tables()
            print(f"\n📋 تعداد جداول برای انتقال: {len(tables)}")
            
            # انتقال هر جدول
            for table_name in tables:
                self.stats['tables_processed'] += 1
                success = self.migrate_table(table_name)
                if not success:
                    print(f"  ⚠️ انتقال جدول {table_name} ناموفق بود")
        
        finally:
            # فعال کردن مجدد Foreign Keys
            self.enable_foreign_keys()
        
        # نمایش گزارش نهایی
        self.print_summary()
    
    def print_summary(self):
        """نمایش گزارش نهایی"""
        print("\n" + "="*60)
        print("📊 گزارش نهایی")
        print("="*60)
        print(f"✅ جداول پردازش شده: {self.stats['tables_processed']}")
        print(f"✅ جداول کامل شده: {self.stats['tables_completed']}")
        print(f"✅ تعداد کل ردیف‌های منتقل شده: {self.stats['total_rows_migrated']:,}")
        print(f"❌ خطاها: {self.stats['errors']}")
        
        if self.stats['error_details']:
            print("\n❌ جزئیات خطاها:")
            for error in self.stats['error_details']:
                print(f"  - {error.get('table', 'unknown')}: {error.get('error', 'unknown error')}")
        
        print("="*60)
    
    def close(self):
        """بستن اتصالات"""
        self.mysql_session.close()
        self.postgres_session.close()
        self.mysql_engine.dispose()
        self.postgres_engine.dispose()


def main():
    parser = argparse.ArgumentParser(description='انتقال داده از MySQL به PostgreSQL')
    parser.add_argument('--mysql-host', default=DEFAULT_MYSQL_CONFIG['host'], help='MySQL host')
    parser.add_argument('--mysql-user', default=DEFAULT_MYSQL_CONFIG['user'], help='MySQL user')
    parser.add_argument('--mysql-password', default=DEFAULT_MYSQL_CONFIG['password'], help='MySQL password')
    parser.add_argument('--mysql-database', default=DEFAULT_MYSQL_CONFIG['database'], help='MySQL database')
    parser.add_argument('--mysql-port', type=int, default=DEFAULT_MYSQL_CONFIG['port'], help='MySQL port')
    
    parser.add_argument('--postgres-host', default=DEFAULT_POSTGRES_CONFIG['host'], help='PostgreSQL host')
    parser.add_argument('--postgres-user', default=DEFAULT_POSTGRES_CONFIG['user'], help='PostgreSQL user')
    parser.add_argument('--postgres-password', default=DEFAULT_POSTGRES_CONFIG['password'], help='PostgreSQL password')
    parser.add_argument('--postgres-database', default=DEFAULT_POSTGRES_CONFIG['database'], help='PostgreSQL database')
    parser.add_argument('--postgres-port', type=int, default=DEFAULT_POSTGRES_CONFIG['port'], help='PostgreSQL port')
    
    parser.add_argument('--checkpoint-file', default='migration_checkpoint.json', help='Checkpoint file path')
    parser.add_argument('--batch-size', type=int, default=1000, help='Batch size for migration')
    parser.add_argument('--clear-checkpoint', action='store_true', help='پاک کردن checkpoint و شروع از ابتدا')
    parser.add_argument('--no-clear-seed', action='store_true', help='پاک نکردن seed data')
    
    args = parser.parse_args()
    
    mysql_config = {
        'host': args.mysql_host,
        'user': args.mysql_user,
        'password': args.mysql_password,
        'database': args.mysql_database,
        'port': args.mysql_port,
    }
    
    postgres_config = {
        'host': args.postgres_host,
        'user': args.postgres_user,
        'password': args.postgres_password,
        'database': args.postgres_database,
        'port': args.postgres_port,
    }
    
    # ایجاد migration instance
    migration = MySQLToPostgreSQLMigration(
        mysql_config=mysql_config,
        postgres_config=postgres_config,
        checkpoint_file=args.checkpoint_file,
        batch_size=args.batch_size,
    )
    
    try:
        # پاک کردن checkpoint اگر لازم باشد
        if args.clear_checkpoint:
            migration.checkpoint.clear()
        
        # شروع انتقال
        migration.migrate_all(clear_seed=not args.no_clear_seed)
    
    except KeyboardInterrupt:
        print("\n\n⚠️ انتقال توسط کاربر متوقف شد")
        print("💾 Checkpoint ذخیره شد. می‌توانید با همان دستور ادامه دهید.")
    except Exception as e:
        print(f"\n\n❌ خطای غیرمنتظره: {e}")
        import traceback
        traceback.print_exc()
    finally:
        migration.close()


if __name__ == '__main__':
    main()

