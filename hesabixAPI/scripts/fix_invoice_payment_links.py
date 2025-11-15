#!/usr/bin/env python3
"""
اسکریپت اصلاح لینک‌های تراکنش‌های پرداخت در فاکتورها
این اسکریپت فاکتورهایی که سند دریافت/پرداخت دارند اما لینک ندارند را پیدا کرده و لینک را اضافه می‌کند.
"""

import sys
import os
import json
from typing import List, Dict, Any

# اضافه کردن مسیر پروژه به sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, Session

# اطلاعات اتصال به دیتابیس
DB_CONFIG = {
    "user": "root",
    "password": "136431",
    "host": "localhost",
    "port": 3306,
    "database": "hesabixpy"
}

def create_connection():
    """ایجاد اتصال به دیتابیس"""
    connection_string = (
        f"mysql+pymysql://{DB_CONFIG['user']}:{DB_CONFIG['password']}"
        f"@{DB_CONFIG['host']}:{DB_CONFIG['port']}/{DB_CONFIG['database']}"
    )
    engine = create_engine(connection_string, echo=False)
    return sessionmaker(bind=engine)()

def find_invoices_with_missing_links(db: Session) -> List[Dict[str, Any]]:
    """پیدا کردن فاکتورهایی که سند دریافت/پرداخت دارند اما لینک ندارند"""
    # پیدا کردن تمام اسناد دریافت/پرداخت که به فاکتورها لینک شده‌اند
    query = text("""
        SELECT id, code, extra_info
        FROM documents
        WHERE document_type IN ('receipt', 'payment')
        AND extra_info LIKE '%invoice_id%'
    """)
    rp_results = db.execute(query).fetchall()
    
    # گروه‌بندی بر اساس invoice_id
    invoice_to_rp_ids: Dict[int, List[int]] = {}
    for row in rp_results:
        extra_info = json.loads(row[2]) if isinstance(row[2], str) else (row[2] or {})
        invoice_id = extra_info.get('invoice_id')
        if invoice_id:
            if invoice_id not in invoice_to_rp_ids:
                invoice_to_rp_ids[invoice_id] = []
            invoice_to_rp_ids[invoice_id].append(row[0])
    
    # بررسی فاکتورها
    invoices_to_fix = []
    for invoice_id, rp_ids in invoice_to_rp_ids.items():
        inv_query = text("""
            SELECT id, code, extra_info
            FROM documents
            WHERE id = :invoice_id
            AND document_type LIKE 'invoice_%'
        """)
        inv_result = db.execute(inv_query, {"invoice_id": invoice_id}).fetchone()
        if not inv_result:
            continue
        
        extra_info = json.loads(inv_result[2]) if isinstance(inv_result[2], str) else (inv_result[2] or {})
        links = extra_info.get('links', {})
        existing_rp_ids = links.get('receipt_payment_document_ids', [])
        
        # اگر لینک موجود نیست یا ناقص است
        missing_ids = [rp_id for rp_id in rp_ids if rp_id not in existing_rp_ids]
        if missing_ids:
            invoices_to_fix.append({
                "invoice_id": invoice_id,
                "invoice_code": inv_result[1],
                "existing_rp_ids": existing_rp_ids,
                "missing_rp_ids": missing_ids,
                "all_rp_ids": rp_ids
            })
    
    return invoices_to_fix

def fix_invoice_links(db: Session, invoice_id: int, rp_ids: List[int]) -> bool:
    """اصلاح لینک‌های یک فاکتور"""
    try:
        # دریافت فاکتور
        query = text("""
            SELECT id, extra_info
            FROM documents
            WHERE id = :invoice_id
        """)
        result = db.execute(query, {"invoice_id": invoice_id}).fetchone()
        if not result:
            return False
        
        extra_info = json.loads(result[1]) if isinstance(result[1], str) else (result[1] or {})
        links = dict(extra_info.get('links', {}))
        
        # اضافه کردن شناسه‌های جدید
        existing_ids = set(links.get('receipt_payment_document_ids', []))
        existing_ids.update(rp_ids)
        links['receipt_payment_document_ids'] = list(existing_ids)
        
        # به‌روزرسانی
        extra_info['links'] = links
        # تبدیل به JSON string برای MySQL
        extra_info_json = json.dumps(extra_info, ensure_ascii=False)
        update_query = text("""
            UPDATE documents
            SET extra_info = CAST(:extra_info AS JSON)
            WHERE id = :invoice_id
        """)
        db.execute(update_query, {
            "invoice_id": invoice_id,
            "extra_info": extra_info_json
        })
        db.commit()
        return True
    except Exception as e:
        print(f"❌ خطا در اصلاح فاکتور {invoice_id}: {e}")
        db.rollback()
        return False

def main():
    """تابع اصلی"""
    print("🔧 اصلاح لینک‌های تراکنش‌های پرداخت در فاکتورها")
    print("="*80)
    
    db = None
    try:
        db = create_connection()
        print("✅ اتصال به دیتابیس برقرار شد\n")
        
        # پیدا کردن فاکتورهای نیازمند اصلاح
        invoices_to_fix = find_invoices_with_missing_links(db)
        
        if not invoices_to_fix:
            print("✅ همه فاکتورها لینک‌های صحیح دارند!")
            return
        
        print(f"📋 {len(invoices_to_fix)} فاکتور نیازمند اصلاح یافت شد:\n")
        for inv in invoices_to_fix:
            print(f"  فاکتور ID: {inv['invoice_id']:3d} | کد: {inv['invoice_code']:20s}")
            print(f"    لینک‌های موجود: {inv['existing_rp_ids']}")
            print(f"    لینک‌های مفقود: {inv['missing_rp_ids']}")
            print(f"    لینک‌های کامل: {inv['all_rp_ids']}\n")
        
        # درخواست تایید (اگر آرگومان --auto وجود داشت، خودکار اجرا شود)
        auto_mode = len(sys.argv) > 1 and sys.argv[1] == "--auto"
        if not auto_mode:
            response = input("آیا می‌خواهید این فاکتورها را اصلاح کنید؟ (y/n): ")
            if response.lower() != 'y':
                print("❌ عملیات لغو شد.")
                return
        else:
            print("🔄 حالت خودکار فعال است. در حال اصلاح...")
        
        # اصلاح فاکتورها
        print("\n🔧 در حال اصلاح...")
        fixed_count = 0
        for inv in invoices_to_fix:
            if fix_invoice_links(db, inv['invoice_id'], inv['all_rp_ids']):
                print(f"  ✅ فاکتور {inv['invoice_id']} ({inv['invoice_code']}) اصلاح شد")
                fixed_count += 1
            else:
                print(f"  ❌ فاکتور {inv['invoice_id']} ({inv['invoice_code']}) اصلاح نشد")
        
        print(f"\n✅ {fixed_count} از {len(invoices_to_fix)} فاکتور اصلاح شدند.")
        
    except Exception as e:
        print(f"\n❌ خطا: {str(e)}")
        import traceback
        traceback.print_exc()
    finally:
        if db:
            db.close()

if __name__ == "__main__":
    main()

