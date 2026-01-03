#!/usr/bin/env python3
"""
اسکریپت بررسی ردیف‌های جدول accounts و مقایسه با میگریشن
"""
import sys
import os
from typing import List, Dict, Any, Optional

# اضافه کردن مسیر پروژه به sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, Session
from app.core.settings import get_settings

def create_connection():
    """ایجاد اتصال به دیتابیس"""
    settings = get_settings()
    engine = create_engine(
        settings.postgresql_dsn,
        echo=False,
        pool_pre_ping=True,
    )
    return sessionmaker(bind=engine)()

def get_all_accounts_from_db(db: Session) -> List[Dict[str, Any]]:
    """دریافت تمام حساب‌های عمومی (business_id IS NULL) از دیتابیس"""
    query = text("""
        SELECT id, name, business_id, account_type, code, parent_id, created_at, updated_at
        FROM accounts
        WHERE business_id IS NULL
        ORDER BY id ASC
    """)
    results = db.execute(query).fetchall()
    
    accounts = []
    for row in results:
        accounts.append({
            "id": row[0],
            "name": row[1],
            "business_id": row[2],
            "account_type": row[3],
            "code": row[4],
            "parent_id": row[5],
            "created_at": row[6],
            "updated_at": row[7]
        })
    return accounts

def get_accounts_from_migration() -> List[Dict[str, Any]]:
    """دریافت حساب‌ها از میگریشن 20_accounts_chart.py"""
    # مسیر فایل میگریشن نسبت به اسکریپت
    script_dir = os.path.dirname(os.path.abspath(__file__))
    api_dir = os.path.dirname(script_dir)
    migration_file = os.path.join(
        api_dir,
        "migrations", "versions", "init_schema", "20_accounts_chart.py"
    )
    
    # خواندن فایل میگریشن
    with open(migration_file, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # استخراج داده‌های items از میگریشن با استفاده از ast
    import re
    import ast
    
    # پیدا کردن بخش items = [...]
    items_match = re.search(r'items\s*=\s*\[(.*?)\]', content, re.DOTALL)
    if not items_match:
        return []
    
    items_str = "[" + items_match.group(1) + "]"
    
    try:
        # استفاده از ast.literal_eval برای parse کردن لیست
        items = ast.literal_eval(items_str)
        
        # تبدیل به فرمت یکسان
        result = []
        for item in items:
            result.append({
                "code": item["code"],
                "name": item["name"],
                "accountType": item["accountType"],
                "parentId": item["parentId"],
                "level": item["level"],
                "id": item["id"]
            })
        return result
    except Exception as e:
        print(f"⚠️  خطا در parse کردن میگریشن: {e}")
        return []

def find_missing_accounts(db_accounts: List[Dict], migration_accounts: List[Dict]) -> List[Dict]:
    """پیدا کردن حساب‌هایی که در دیتابیس هستند اما در میگریشن نیستند"""
    # ایجاد یک مجموعه از کدهای حساب‌های میگریشن
    migration_codes = {acc["code"] for acc in migration_accounts}
    
    missing = []
    for db_acc in db_accounts:
        if db_acc["code"] not in migration_codes:
            missing.append(db_acc)
    
    return missing

def main():
    """تابع اصلی"""
    print("🔍 بررسی ردیف‌های جدول accounts و مقایسه با میگریشن")
    print("="*80)
    
    db = None
    try:
        db = create_connection()
        print("✅ اتصال به دیتابیس برقرار شد")
        
        # دریافت حساب‌ها از دیتابیس
        print("\n📊 دریافت حساب‌ها از دیتابیس...")
        db_accounts = get_all_accounts_from_db(db)
        print(f"✅ {len(db_accounts)} حساب در دیتابیس یافت شد")
        
        # دریافت حساب‌ها از میگریشن
        print("\n📋 خواندن میگریشن 20_accounts_chart.py...")
        migration_accounts = get_accounts_from_migration()
        print(f"✅ {len(migration_accounts)} حساب در میگریشن یافت شد")
        
        # پیدا کردن حساب‌های گم‌شده
        print("\n🔎 جستجوی حساب‌هایی که در دیتابیس هستند اما در میگریشن نیستند...")
        missing_accounts = find_missing_accounts(db_accounts, migration_accounts)
        
        if missing_accounts:
            print(f"\n⚠️  {len(missing_accounts)} حساب در دیتابیس یافت شد که در میگریشن نیست:")
            print("-"*80)
            for acc in missing_accounts:
                account_type = acc['account_type']
                if isinstance(account_type, str):
                    account_type_str = account_type
                else:
                    account_type_str = str(account_type) if account_type is not None else '0'
                parent_id = acc['parent_id'] if acc['parent_id'] is not None else 'NULL'
                print(f"  - کد: {acc['code']:10s} | نام: {acc['name']:50s} | نوع: {account_type_str:20s} | parent_id: {parent_id}")
            
            print("\n💡 این حساب‌ها باید به میگریشن اضافه شوند.")
            return missing_accounts
        else:
            print("\n✅ همه حساب‌های دیتابیس در میگریشن موجود هستند!")
            return []
        
    except Exception as e:
        print(f"\n❌ خطا: {str(e)}")
        import traceback
        traceback.print_exc()
        return []
    finally:
        if db:
            db.close()

if __name__ == "__main__":
    missing = main()
    if missing:
        sys.exit(1)
    else:
        sys.exit(0)

