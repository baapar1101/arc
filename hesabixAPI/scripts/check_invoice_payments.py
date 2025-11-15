#!/usr/bin/env python3
"""
اسکریپت بررسی ذخیره‌سازی تراکنش‌های پرداخت در فاکتورها
"""

import sys
import os
import json
from datetime import datetime
from typing import Optional, List, Dict, Any

# اضافه کردن مسیر پروژه به sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, Session

# اطلاعات اتصال به دیتابیس از env.example
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

def get_latest_invoice(db: Session) -> Optional[Dict[str, Any]]:
    """دریافت آخرین فاکتور ثبت شده"""
    query = text("""
        SELECT 
            id, code, document_type, document_date, 
            business_id, extra_info, created_at
        FROM documents
        WHERE document_type LIKE 'invoice_%'
        ORDER BY id DESC
        LIMIT 1
    """)
    result = db.execute(query).fetchone()
    if result:
        return {
            "id": result[0],
            "code": result[1],
            "document_type": result[2],
            "document_date": result[3],
            "business_id": result[4],
            "extra_info": json.loads(result[5]) if result[5] else {},
            "created_at": result[6]
        }
    return None

def list_recent_invoices(db: Session, limit: int = 10) -> List[Dict[str, Any]]:
    """لیست فاکتورهای اخیر"""
    query = text("""
        SELECT 
            id, code, document_type, document_date, 
            business_id, extra_info, created_at
        FROM documents
        WHERE document_type LIKE 'invoice_%'
        ORDER BY id DESC
        LIMIT :limit
    """)
    results = db.execute(query, {"limit": limit}).fetchall()
    
    invoices = []
    for row in results:
        extra_info = json.loads(row[5]) if row[5] else {}
        links = extra_info.get('links', {})
        has_payments = bool(links.get('receipt_payment_document_ids', []))
        
        invoices.append({
            "id": row[0],
            "code": row[1],
            "document_type": row[2],
            "document_date": row[3],
            "business_id": row[4],
            "extra_info": extra_info,
            "created_at": row[6],
            "has_payments": has_payments
        })
    return invoices

def get_invoice_by_id(db: Session, invoice_id: int) -> Optional[Dict[str, Any]]:
    """دریافت فاکتور با شناسه"""
    query = text("""
        SELECT 
            id, code, document_type, document_date, 
            business_id, extra_info, created_at
        FROM documents
        WHERE id = :invoice_id
    """)
    result = db.execute(query, {"invoice_id": invoice_id}).fetchone()
    if result:
        return {
            "id": result[0],
            "code": result[1],
            "document_type": result[2],
            "document_date": result[3],
            "business_id": result[4],
            "extra_info": json.loads(result[5]) if result[5] else {},
            "created_at": result[6]
        }
    return None

def get_receipt_payment_documents(db: Session, doc_ids: List[int]) -> List[Dict[str, Any]]:
    """دریافت اسناد دریافت/پرداخت"""
    if not doc_ids:
        return []
    
    placeholders = ",".join([":id" + str(i) for i in range(len(doc_ids))])
    params = {f"id{i}": doc_id for i, doc_id in enumerate(doc_ids)}
    
    query = text(f"""
        SELECT 
            id, code, document_type, document_date,
            business_id, description, extra_info, created_at
        FROM documents
        WHERE id IN ({placeholders})
        ORDER BY id
    """)
    results = db.execute(query, params).fetchall()
    
    documents = []
    for row in results:
        documents.append({
            "id": row[0],
            "code": row[1],
            "document_type": row[2],
            "document_date": row[3],
            "business_id": row[4],
            "description": row[5],
            "extra_info": json.loads(row[6]) if row[6] else {},
            "created_at": row[7]
        })
    return documents

def get_document_lines(db: Session, document_id: int) -> List[Dict[str, Any]]:
    """دریافت سطرهای یک سند"""
    query = text("""
        SELECT 
            dl.id, dl.account_id, dl.person_id, dl.bank_account_id,
            dl.cash_register_id, dl.petty_cash_id, dl.check_id,
            dl.debit, dl.credit, dl.description, dl.extra_info,
            a.code as account_code, a.name as account_name,
            p.alias_name as person_name
        FROM document_lines dl
        LEFT JOIN accounts a ON dl.account_id = a.id
        LEFT JOIN persons p ON dl.person_id = p.id
        WHERE dl.document_id = :document_id
        ORDER BY dl.id
    """)
    results = db.execute(query, {"document_id": document_id}).fetchall()
    
    lines = []
    for row in results:
        lines.append({
            "id": row[0],
            "account_id": row[1],
            "person_id": row[2],
            "bank_account_id": row[3],
            "cash_register_id": row[4],
            "petty_cash_id": row[5],
            "check_id": row[6],
            "debit": float(row[7]) if row[7] else 0.0,
            "credit": float(row[8]) if row[8] else 0.0,
            "description": row[9],
            "extra_info": json.loads(row[10]) if row[10] else {},
            "account_code": row[11],
            "account_name": row[12],
            "person_name": row[13]
        })
    return lines

def print_invoice_info(invoice: Dict[str, Any]):
    """چاپ اطلاعات فاکتور"""
    print("\n" + "="*80)
    print("📄 اطلاعات فاکتور")
    print("="*80)
    print(f"شناسه: {invoice['id']}")
    print(f"کد: {invoice['code']}")
    print(f"نوع: {invoice['document_type']}")
    print(f"تاریخ: {invoice['document_date']}")
    print(f"کسب‌وکار: {invoice['business_id']}")
    print(f"تاریخ ایجاد: {invoice['created_at']}")
    
    extra_info = invoice.get('extra_info', {})
    if extra_info:
        print("\n📋 اطلاعات اضافی (extra_info):")
        print(json.dumps(extra_info, indent=2, ensure_ascii=False))
    
    # بررسی لینک‌ها
    links = extra_info.get('links', {})
    receipt_payment_ids = links.get('receipt_payment_document_ids', [])
    
    print("\n" + "-"*80)
    if receipt_payment_ids:
        print(f"✅ لینک به اسناد دریافت/پرداخت یافت شد: {receipt_payment_ids}")
        return receipt_payment_ids
    else:
        print("❌ هیچ لینک به سند دریافت/پرداخت یافت نشد!")
        print("   این یعنی تراکنش‌های پرداخت ذخیره نشده‌اند یا فاکتور بدون تراکنش ثبت شده است.")
        return []

def print_receipt_payment_info(rp_doc: Dict[str, Any], db: Session):
    """چاپ اطلاعات سند دریافت/پرداخت"""
    print("\n" + "="*80)
    print(f"💰 سند دریافت/پرداخت: {rp_doc['code']}")
    print("="*80)
    print(f"شناسه: {rp_doc['id']}")
    print(f"کد: {rp_doc['code']}")
    print(f"نوع: {rp_doc['document_type']}")
    print(f"تاریخ: {rp_doc['document_date']}")
    print(f"توضیحات: {rp_doc.get('description', '-')}")
    
    extra_info = rp_doc.get('extra_info', {})
    if extra_info:
        print("\n📋 اطلاعات اضافی:")
        print(json.dumps(extra_info, indent=2, ensure_ascii=False))
    
    # دریافت سطرهای سند
    lines = get_document_lines(db, rp_doc['id'])
    
    print(f"\n📊 سطرهای سند ({len(lines)} سطر):")
    print("-"*80)
    
    total_debit = 0
    total_credit = 0
    
    for i, line in enumerate(lines, 1):
        print(f"\nسطر {i}:")
        print(f"  حساب: {line['account_code']} - {line['account_name']}")
        if line['person_name']:
            print(f"  طرف‌حساب: {line['person_name']}")
        if line['bank_account_id']:
            print(f"  بانک ID: {line['bank_account_id']}")
        if line['cash_register_id']:
            print(f"  صندوق ID: {line['cash_register_id']}")
        if line['petty_cash_id']:
            print(f"  تنخواهگردان ID: {line['petty_cash_id']}")
        if line['check_id']:
            print(f"  چک ID: {line['check_id']}")
        print(f"  بدهکار: {line['debit']:,.0f}")
        print(f"  بستانکار: {line['credit']:,.0f}")
        if line['description']:
            print(f"  توضیحات: {line['description']}")
        if line['extra_info']:
            print(f"  اطلاعات اضافی: {json.dumps(line['extra_info'], ensure_ascii=False)}")
        
        total_debit += line['debit']
        total_credit += line['credit']
    
    print("\n" + "-"*80)
    print(f"جمع بدهکار: {total_debit:,.0f}")
    print(f"جمع بستانکار: {total_credit:,.0f}")
    print(f"تفاوت: {abs(total_debit - total_credit):,.0f}")

def main():
    """تابع اصلی"""
    print("🔍 بررسی ذخیره‌سازی تراکنش‌های پرداخت در فاکتورها")
    print("="*80)
    
    # دریافت شناسه فاکتور از آرگومان‌های خط فرمان (اختیاری)
    invoice_id = None
    list_all = False
    if len(sys.argv) > 1:
        if sys.argv[1] == "--list" or sys.argv[1] == "-l":
            list_all = True
        else:
            try:
                invoice_id = int(sys.argv[1])
                print(f"📌 بررسی فاکتور با شناسه: {invoice_id}")
            except ValueError:
                print("⚠️  شناسه فاکتور نامعتبر است. آخرین فاکتور بررسی می‌شود.")
    else:
        print("📌 بررسی آخرین فاکتور ثبت شده...")
    
    db = None
    try:
        db = create_connection()
        print("✅ اتصال به دیتابیس برقرار شد")
        
        # اگر لیست درخواست شده
        if list_all:
            print("\n📋 لیست فاکتورهای اخیر:")
            print("-"*80)
            invoices = list_recent_invoices(db, limit=20)
            for inv in invoices:
                status = "✅" if inv['has_payments'] else "❌"
                print(f"{status} ID: {inv['id']:3d} | کد: {inv['code']:20s} | تاریخ: {inv['document_date']} | پرداخت: {'دارد' if inv['has_payments'] else 'ندارد'}")
            print("\n💡 برای بررسی جزئیات یک فاکتور، شناسه آن را به عنوان آرگومان وارد کنید:")
            print("   python scripts/check_invoice_payments.py <invoice_id>")
            return
        
        # دریافت فاکتور
        if invoice_id:
            invoice = get_invoice_by_id(db, invoice_id)
            if not invoice:
                print(f"❌ فاکتور با شناسه {invoice_id} یافت نشد!")
                return
        else:
            invoice = get_latest_invoice(db)
            if not invoice:
                print("❌ هیچ فاکتوری یافت نشد!")
                return
        
        # نمایش اطلاعات فاکتور
        receipt_payment_ids = print_invoice_info(invoice)
        
        # اگر لینک به اسناد دریافت/پرداخت وجود دارد، آن‌ها را بررسی کن
        if receipt_payment_ids:
            print(f"\n🔗 بررسی {len(receipt_payment_ids)} سند دریافت/پرداخت...")
            rp_docs = get_receipt_payment_documents(db, receipt_payment_ids)
            
            if rp_docs:
                for rp_doc in rp_docs:
                    print_receipt_payment_info(rp_doc, db)
            else:
                print("⚠️  اسناد دریافت/پرداخت یافت نشدند!")
        else:
            print("\n💡 نکته: برای بررسی تراکنش‌های پرداخت، باید فاکتوری را انتخاب کنید")
            print("   که در زمان ثبت، تراکنش‌های پرداخت داشته باشد.")
        
        print("\n" + "="*80)
        print("✅ بررسی کامل شد")
        
    except Exception as e:
        print(f"\n❌ خطا: {str(e)}")
        import traceback
        traceback.print_exc()
    finally:
        if db:
            db.close()

if __name__ == "__main__":
    main()

