#!/usr/bin/env python3
"""
اسکریپت ایجاد حساب‌های مورد نیاز برای سرویس زحل
استفاده: python scripts/ensure_zohal_accounts.py
"""
import sys
from pathlib import Path

# اضافه کردن مسیر پروژه به sys.path
project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))

from sqlalchemy.orm import Session
from adapters.db.session import SessionLocal
from adapters.db.models.account import Account
from sqlalchemy import and_


def ensure_zohal_expense_account(db: Session) -> Account:
	"""
	بررسی و ایجاد حساب هزینه سرویس‌های استعلامات (70903)
	"""
	account = db.query(Account).filter(
		and_(
			Account.code == "70903",
			Account.business_id.is_(None)
		)
	).first()
	
	if not account:
		# ایجاد حساب هزینه سرویس‌های استعلامات
		print("📝 ایجاد حساب هزینه سرویس‌های استعلامات (70903)...")
		account = Account(
			name="هزینه سرویس‌های استعلامات",
			code="70903",
			account_type="expense",
			business_id=None  # حساب عمومی
		)
		db.add(account)
		db.commit()
		db.refresh(account)
		print(f"✅ حساب ایجاد شد: {account.name} (کد: {account.code}, ID: {account.id})")
	else:
		print(f"✅ حساب موجود است: {account.name} (کد: {account.code}, ID: {account.id})")
	
	return account


def main():
	"""ایجاد حساب‌های مورد نیاز"""
	db: Session = SessionLocal()
	try:
		ensure_zohal_expense_account(db)
		print("\n✅ تمام حساب‌های مورد نیاز ایجاد شدند.")
		return 0
	except Exception as e:
		print(f"❌ خطا: {e}")
		import traceback
		traceback.print_exc()
		db.rollback()
		return 1
	finally:
		db.close()


if __name__ == "__main__":
	sys.exit(main())

