#!/usr/bin/env python3
"""
اسکریپت ایجاد حساب‌های مورد نیاز برای Document Monetization
استفاده: python scripts/ensure_document_monetization_accounts.py
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


def ensure_document_monetization_expense_account(db: Session) -> Account:
	"""
	بررسی و ایجاد حساب هزینه اشتراک و خدمات سیستم (70507)
	حساب در گروه هزینه‌های عمومی (705) قرار دارد
	"""
	from app.services.wallet_service import _get_fixed_account_by_code
	
	account = db.query(Account).filter(
		and_(
			Account.code == "70507",
			Account.business_id.is_(None)
		)
	).first()
	
	if not account:
		# دریافت حساب والد (705 - هزینه‌های عمومی)
		try:
			parent_account = _get_fixed_account_by_code(db, "705")
			parent_id = parent_account.id if parent_account else None
		except Exception:
			parent_id = None
		
		# ایجاد حساب هزینه اشتراک و خدمات سیستم
		print("📝 ایجاد حساب هزینه اشتراک و خدمات سیستم (70507)...")
		account = Account(
			name="هزینه اشتراک و خدمات سیستم",
			code="70507",
			account_type="accounting_document",
			business_id=None,  # حساب عمومی
			parent_id=parent_id
		)
		db.add(account)
		db.commit()
		db.refresh(account)
		print(f"✅ حساب ایجاد شد: {account.name} (کد: {account.code}, ID: {account.id})")
	else:
		# به‌روزرسانی نام حساب در صورت نیاز
		expected_name = "هزینه اشتراک و خدمات سیستم"
		if account.name != expected_name:
			account.name = expected_name
			if account.account_type != "accounting_document":
				account.account_type = "accounting_document"
			db.commit()
			print(f"✅ حساب به‌روزرسانی شد: {account.name} (کد: {account.code}, ID: {account.id})")
		else:
			print(f"✅ حساب موجود است: {account.name} (کد: {account.code}, ID: {account.id})")
	
	return account


def main():
	"""ایجاد حساب‌های مورد نیاز"""
	db: Session = SessionLocal()
	try:
		print("=" * 60)
		print("🔧 بررسی و ایجاد حساب‌های Document Monetization")
		print("=" * 60)
		
		ensure_document_monetization_expense_account(db)
		
		print("=" * 60)
		print("✅ تمام حساب‌ها با موفقیت بررسی/ایجاد شدند")
		print("=" * 60)
	except Exception as e:
		print(f"❌ خطا: {e}")
		import traceback
		traceback.print_exc()
		db.rollback()
		sys.exit(1)
	finally:
		db.close()


if __name__ == "__main__":
	main()



