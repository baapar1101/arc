#!/usr/bin/env python3
"""
اسکریپت مستقیم برای اصلاح کد حساب هزینه سرویس‌های استعلامات
این اسکریپت تغییرات را مستقیماً در دیتابیس اعمال می‌کند
"""
import sys
from pathlib import Path

# اضافه کردن مسیر پروژه به sys.path
project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))

from sqlalchemy.orm import Session
from adapters.db.session import SessionLocal
from adapters.db.models.account import Account
from sqlalchemy import and_, text
from datetime import datetime


def fix_zohal_account_code(db: Session) -> bool:
    """اصلاح کد حساب هزینه سرویس‌های استعلامات"""
    try:
        # 1. برگرداندن حساب 70903 به نام اصلی "جرائم دیرکرد بانکی" (اگر تغییر کرده باشد)
        account_70903 = db.query(Account).filter(
            and_(
                Account.code == "70903",
                Account.business_id.is_(None)
            )
        ).first()
        
        if account_70903 and account_70903.name != "جرائم دیرکرد بانکی":
            print(f"🔄 برگرداندن حساب 70903 از '{account_70903.name}' به 'جرائم دیرکرد بانکی'")
            account_70903.name = "جرائم دیرکرد بانکی"
            account_70903.updated_at = datetime.utcnow()
            db.flush()
            print("✅ حساب 70903 اصلاح شد")
        elif account_70903:
            print("✅ حساب 70903 قبلاً با نام صحیح ('جرائم دیرکرد بانکی') تنظیم شده است")
        else:
            print("⚠️  حساب 70903 یافت نشد")
        
        # 2. ایجاد یا به‌روزرسانی حساب 70509
        account_705 = db.query(Account).filter(
            and_(
                Account.code == "705",
                Account.business_id.is_(None)
            )
        ).first()
        
        if not account_705:
            print("❌ حساب 705 (هزینه‌های عمومی) یافت نشد!")
            return False
        
        account_70509 = db.query(Account).filter(
            and_(
                Account.code == "70509",
                Account.business_id.is_(None)
            )
        ).first()
        
        if not account_70509:
            # ایجاد حساب 70509
            print("📝 ایجاد حساب 70509 (هزینه سرویس‌های استعلامات)...")
            account_70509 = Account(
                name="هزینه سرویس‌های استعلامات",
                code="70509",
                account_type="accounting_document",
                business_id=None,
                parent_id=account_705.id,
                created_at=datetime.utcnow(),
                updated_at=datetime.utcnow()
            )
            db.add(account_70509)
            db.flush()
            print(f"✅ حساب 70509 ایجاد شد (ID: {account_70509.id})")
        else:
            # به‌روزرسانی حساب در صورت نیاز
            updated = False
            if account_70509.name != "هزینه سرویس‌های استعلامات":
                print(f"🔄 به‌روزرسانی نام حساب 70509 از '{account_70509.name}' به 'هزینه سرویس‌های استعلامات'")
                account_70509.name = "هزینه سرویس‌های استعلامات"
                updated = True
            
            if account_70509.account_type != "accounting_document":
                print(f"🔄 به‌روزرسانی نوع حساب 70509 به 'accounting_document'")
                account_70509.account_type = "accounting_document"
                updated = True
            
            if account_70509.parent_id != account_705.id:
                print(f"🔄 به‌روزرسانی حساب والد 70509")
                account_70509.parent_id = account_705.id
                updated = True
            
            if updated:
                account_70509.updated_at = datetime.utcnow()
                db.flush()
                print(f"✅ حساب 70509 به‌روزرسانی شد (ID: {account_70509.id})")
            else:
                print(f"✅ حساب 70509 قبلاً به درستی تنظیم شده است (ID: {account_70509.id})")
        
        db.commit()
        return True
        
    except Exception as e:
        print(f"❌ خطا در اجرای تغییرات: {e}")
        import traceback
        traceback.print_exc()
        db.rollback()
        return False


def main():
    """تابع اصلی"""
    print("=" * 80)
    print("🔧 اصلاح کد حساب هزینه سرویس‌های استعلامات")
    print("=" * 80)
    print()
    
    db: Session = SessionLocal()
    try:
        success = fix_zohal_account_code(db)
        
        if success:
            print()
            print("=" * 80)
            print("✅ تمام تغییرات با موفقیت اعمال شدند.")
            print("=" * 80)
            return 0
        else:
            print()
            print("=" * 80)
            print("❌ خطا در اعمال تغییرات.")
            print("=" * 80)
            return 1
            
    except Exception as e:
        print(f"\n❌ خطای غیرمنتظره: {e}")
        import traceback
        traceback.print_exc()
        return 1
    finally:
        db.close()


if __name__ == "__main__":
    sys.exit(main())

