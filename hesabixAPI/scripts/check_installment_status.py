"""
اسکریپت برای بررسی وضعیت اقساط در دیتابیس
"""
import sys
import os
import json
from pathlib import Path

# اضافه کردن مسیر پروژه به sys.path
project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))

from sqlalchemy.orm import Session
from adapters.db.session import get_db
from adapters.db.models.document import Document

def check_document_by_code(db: Session, code: str):
    """بررسی سند بر اساس کد"""
    doc = db.query(Document).filter(Document.code == code).first()
    if not doc:
        print(f"❌ سند با کد {code} پیدا نشد")
        return None
    
    print(f"\n{'='*80}")
    print(f"📄 سند: {code}")
    print(f"   ID: {doc.id}")
    print(f"   نوع: {doc.document_type}")
    print(f"   تاریخ: {doc.document_date}")
    print(f"   کسب‌وکار: {doc.business_id}")
    print(f"{'='*80}")
    
    if doc.extra_info:
        print("\n📋 محتوای extra_info:")
        print(json.dumps(doc.extra_info, indent=2, ensure_ascii=False))
        
        # بررسی طرح اقساط
        if isinstance(doc.extra_info, dict):
            plan = doc.extra_info.get("installment_plan")
            if plan:
                print("\n💰 طرح اقساط:")
                schedule = plan.get("schedule", [])
                print(f"   تعداد اقساط: {len(schedule)}")
                for item in schedule:
                    seq = item.get("seq", 0)
                    total = item.get("total", 0)
                    paid = item.get("paid_amount", 0)
                    status = item.get("status", "N/A")
                    remaining = total - paid
                    due_date = item.get("due_date", "N/A")
                    print(f"\n   قسط #{seq}:")
                    print(f"      مبلغ کل: {total:,.0f}")
                    print(f"      پرداخت شده: {paid:,.0f}")
                    print(f"      باقیمانده: {remaining:,.0f}")
                    print(f"      وضعیت: {status}")
                    print(f"      سررسید: {due_date}")
    else:
        print("\n⚠️  extra_info خالی است")
    
    return doc

def main():
    """تابع اصلی"""
    db: Session = next(get_db())
    
    try:
        print("🔍 بررسی اسناد...\n")
        
        # بررسی فاکتور فروش
        invoice = check_document_by_code(db, "INV-20251116-0002")
        
        # بررسی سند دریافت
        receipt = check_document_by_code(db, "RC-20251117-0002")
        
        # بررسی settlements در سند دریافت
        if receipt and receipt.extra_info:
            settlements = receipt.extra_info.get("settlements", [])
            if settlements:
                print(f"\n{'='*80}")
                print("💳 تخصیص‌های اقساط در سند دریافت:")
                print(f"{'='*80}")
                for i, st in enumerate(settlements, 1):
                    print(f"\n   تخصیص #{i}:")
                    print(f"      فاکتور ID: {st.get('invoice_id')}")
                    print(f"      شخص ID: {st.get('person_id')}")
                    allocations = st.get("allocations", [])
                    print(f"      تعداد تخصیص‌ها: {len(allocations)}")
                    for al in allocations:
                        seq = al.get("seq")
                        amount = al.get("amount", 0)
                        print(f"         قسط #{seq}: {amount:,.0f}")
        
    except Exception as e:
        print(f"\n❌ خطا: {e}")
        import traceback
        traceback.print_exc()
    finally:
        db.close()

if __name__ == "__main__":
    main()

