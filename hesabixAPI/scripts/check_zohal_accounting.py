#!/usr/bin/env python3
"""
اسکریپت بررسی حساب 70509 و اسناد حسابداری تولید شده برای استعلام
"""
import sys
from pathlib import Path

# اضافه کردن مسیر پروژه به sys.path
project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))

from sqlalchemy.orm import Session
from sqlalchemy import text, and_
from adapters.db.session import SessionLocal
from adapters.db.models.account import Account
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.zohal import ZohalServiceLog


def check_account_70509(db: Session):
    """بررسی حساب 70509"""
    print("="*80)
    print("📊 بررسی حساب 70509 (هزینه سرویس‌های استعلامات)")
    print("="*80)
    
    account = db.query(Account).filter(
        and_(
            Account.code == "70509",
            Account.business_id.is_(None)
        )
    ).first()
    
    if not account:
        print("❌ حساب 70509 یافت نشد!")
        print("💡 باید حساب با نام 'هزینه سرویس‌های استعلامات' ایجاد شود.")
        return None
    else:
        print(f"✅ حساب 70509 یافت شد:")
        print(f"   - ID: {account.id}")
        print(f"   - نام: {account.name}")
        print(f"   - کد: {account.code}")
        print(f"   - نوع: {account.account_type}")
        print(f"   - Business ID: {account.business_id}")
        
        if account.name != "هزینه سرویس‌های استعلامات":
            print(f"⚠️  هشدار: نام حساب '{account.name}' است، اما باید 'هزینه سرویس‌های استعلامات' باشد.")
        else:
            print("✅ نام حساب صحیح است.")
        
        if account.account_type != "expense":
            print(f"⚠️  هشدار: نوع حساب '{account.account_type}' است، اما باید 'expense' باشد.")
        else:
            print("✅ نوع حساب صحیح است.")
        
        # بررسی اینکه حساب در گروه هزینه‌های عمومی (705) قرار دارد
        if account.parent_id:
            parent = db.query(Account).filter(Account.id == account.parent_id).first()
            if parent:
                print(f"   - حساب والد: {parent.code} ({parent.name})")
                if parent.code != "705":
                    print(f"⚠️  هشدار: حساب والد باید 705 (هزینه‌های عمومی) باشد.")
                else:
                    print("✅ حساب در گروه صحیح قرار دارد (705 - هزینه‌های عمومی).")
        
        return account


def check_zohal_documents(db: Session, account_id: int):
    """بررسی اسناد حسابداری تولید شده برای استعلام"""
    print("\n" + "="*80)
    print("📄 بررسی اسناد حسابداری استعلام")
    print("="*80)
    
    # دریافت لاگ‌های موفق استعلام که سند حسابداری دارند
    logs_with_docs = db.query(ZohalServiceLog).filter(
        and_(
            ZohalServiceLog.status == "success",
            ZohalServiceLog.document_id.isnot(None),
            ZohalServiceLog.amount_charged > 0
        )
    ).order_by(ZohalServiceLog.created_at.desc()).limit(10).all()
    
    if not logs_with_docs:
        print("⚠️  هیچ سند حسابداری برای استعلام یافت نشد.")
        print("💡 ممکن است هنوز استعلامی انجام نشده باشد.")
        return
    
    print(f"📋 بررسی {len(logs_with_docs)} سند حسابداری اخیر:")
    print("-"*80)
    
    correct_count = 0
    incorrect_count = 0
    
    for log in logs_with_docs:
        document = db.query(Document).filter(Document.id == log.document_id).first()
        if not document:
            print(f"❌ سند با ID {log.document_id} یافت نشد!")
            continue
        
        # دریافت سطرهای سند
        lines = db.query(DocumentLine).filter(
            DocumentLine.document_id == document.id
        ).all()
        
        # بررسی اینکه آیا در سطرها از حساب 70509 استفاده شده است
        has_expense_account = False
        expense_line = None
        
        for line in lines:
            if line.account_id == account_id:
                has_expense_account = True
                expense_line = line
                break
        
        if has_expense_account:
            correct_count += 1
            print(f"✅ سند {document.code} (ID: {document.id})")
            print(f"   - تاریخ: {document.document_date}")
            print(f"   - مبلغ هزینه: {expense_line.debit}")
            print(f"   - توضیحات: {expense_line.description}")
        else:
            incorrect_count += 1
            print(f"❌ سند {document.code} (ID: {document.id})")
            print(f"   - تاریخ: {document.document_date}")
            print(f"   - هشدار: از حساب 70509 استفاده نشده است!")
            
            # نمایش حساب‌های استفاده شده
            account_codes = []
            for line in lines:
                if line.account_id:
                    acc = db.query(Account).filter(Account.id == line.account_id).first()
                    if acc:
                        account_codes.append(f"{acc.code} ({acc.name})")
            print(f"   - حساب‌های استفاده شده: {', '.join(account_codes)}")
    
    print("\n" + "-"*80)
    print(f"📊 خلاصه:")
    print(f"   - صحیح: {correct_count}")
    print(f"   - نادرست: {incorrect_count}")
    print(f"   - کل: {len(logs_with_docs)}")


def check_recent_inquiries(db: Session):
    """بررسی آخرین استعلام‌ها"""
    print("\n" + "="*80)
    print("🔍 بررسی آخرین استعلام‌ها")
    print("="*80)
    
    recent_logs = db.query(ZohalServiceLog).order_by(
        ZohalServiceLog.created_at.desc()
    ).limit(5).all()
    
    if not recent_logs:
        print("⚠️  هیچ استعلامی در سیستم یافت نشد.")
        return
    
    print(f"📋 آخرین {len(recent_logs)} استعلام:")
    print("-"*80)
    
    for log in recent_logs:
        status_icon = "✅" if log.status == "success" else "❌"
        print(f"{status_icon} استعلام #{log.id}")
        print(f"   - وضعیت: {log.status}")
        print(f"   - مبلغ: {log.amount_charged}")
        print(f"   - تاریخ: {log.created_at}")
        
        if log.document_id:
            print(f"   - سند حسابداری: ✅ (ID: {log.document_id})")
        else:
            print(f"   - سند حسابداری: ❌ (هیچ سندی ایجاد نشده)")
        
        print()


def main():
    """تابع اصلی"""
    print("🔍 بررسی سیستم حسابداری استعلام")
    print("="*80)
    
    db: Session = SessionLocal()
    try:
        # بررسی حساب 70509
        account = check_account_70509(db)
        
        if account:
            # بررسی اسناد حسابداری
            check_zohal_documents(db, account.id)
        
        # بررسی آخرین استعلام‌ها
        check_recent_inquiries(db)
        
        print("\n" + "="*80)
        print("✅ بررسی کامل شد.")
        return 0
        
    except Exception as e:
        print(f"\n❌ خطا: {e}")
        import traceback
        traceback.print_exc()
        return 1
    finally:
        db.close()


if __name__ == "__main__":
    sys.exit(main())

