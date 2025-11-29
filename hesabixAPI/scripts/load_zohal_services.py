#!/usr/bin/env python3
"""
اسکریپت بارگذاری سرویس‌های زحل از فایل JSON
استفاده: python scripts/load_zohal_services.py
"""
import sys
import os
from pathlib import Path

# اضافه کردن مسیر پروژه به sys.path
project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))

from sqlalchemy.orm import Session
from adapters.db.session import SessionLocal
from app.services.zohal_service import load_services_from_json
from adapters.db.models.currency import Currency


def main():
	"""بارگذاری سرویس‌ها از فایل JSON"""
	# مسیر فایل JSON
	json_file = project_root.parent / "docs" / "zohal.json"
	
	if not json_file.exists():
		print(f"❌ فایل {json_file} یافت نشد!")
		return 1
	
	print(f"📂 بارگذاری سرویس‌ها از فایل: {json_file}")
	
	# دریافت ارز پیش‌فرض (IRR)
	db: Session = SessionLocal()
	try:
		currency = db.query(Currency).filter(Currency.code == "IRR").first()
		if not currency:
			print("❌ ارز IRR یافت نشد! لطفاً ابتدا ارزها را بارگذاری کنید.")
			return 1
		
		print(f"✅ ارز پیش‌فرض: {currency.code} (ID: {currency.id})")
		
		# بارگذاری سرویس‌ها
		result = load_services_from_json(
			db=db,
			json_file_path=str(json_file),
			default_currency_id=currency.id,
		)
		
		print(f"\n✅ بارگذاری با موفقیت انجام شد:")
		print(f"   - ایجاد شده: {result['created']}")
		print(f"   - به‌روزرسانی شده: {result['updated']}")
		print(f"   - رد شده: {result['skipped']}")
		print(f"   - مجموع: {result['total']}")
		
		return 0
	except Exception as e:
		print(f"❌ خطا در بارگذاری: {e}")
		import traceback
		traceback.print_exc()
		return 1
	finally:
		db.close()


if __name__ == "__main__":
	sys.exit(main())

