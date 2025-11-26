#!/usr/bin/env python3
"""
اسکریپت بررسی و ثبت webhook تلگرام
این اسکریپت وضعیت webhook را بررسی می‌کند و در صورت نیاز آن را ثبت می‌کند.
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
from app.services.system_settings_service import get_effective_notifications_settings
from app.services.providers.telegram_provider import TelegramProvider
from urllib import request, parse
import structlog

logger = structlog.get_logger()


def get_webhook_info(bot_token: str) -> dict:
	"""دریافت اطلاعات webhook فعلی از Telegram API"""
	url = f"https://api.telegram.org/bot{bot_token}/getWebhookInfo"
	try:
		with request.urlopen(request.Request(url), timeout=10) as resp:
			raw = resp.read().decode("utf-8")
			return json.loads(raw)
	except Exception as e:
		logger.error("get_webhook_info_failed", error=str(e))
		return {"ok": False, "error": str(e)}


def main():
	print("=" * 60)
	print("بررسی وضعیت webhook تلگرام")
	print("=" * 60)
	
	# اتصال به دیتابیس
	db: Session = next(get_db())
	
	try:
		# دریافت تنظیمات
		cfg = get_effective_notifications_settings(db)
		bot_token = cfg.get("telegram_bot_token")
		webhook_secret = cfg.get("telegram_webhook_secret")
		proxy_cfg = cfg.get("telegram_proxy") or {}
		proxy_enabled = bool(proxy_cfg.get("enabled") and proxy_cfg.get("base_url"))
		
		print(f"\n📋 تنظیمات:")
		print(f"  - Bot Token: {'✓ تنظیم شده' if bot_token else '✗ تنظیم نشده'}")
		print(f"  - Webhook Secret: {'✓ تنظیم شده' if webhook_secret else '✗ تنظیم نشده'}")
		print(f"  - Proxy Enabled: {'✓ بله' if proxy_enabled else '✗ خیر'}")
		if proxy_enabled:
			print(f"  - Proxy URL: {proxy_cfg.get('base_url')}")
		
		if not bot_token:
			print("\n❌ خطا: توکن ربات تلگرام تنظیم نشده است!")
			print("   لطفاً از طریق پنل ادمین، توکن ربات را تنظیم کنید.")
			return 1
		
		if not webhook_secret:
			print("\n❌ خطا: رمز webhook تنظیم نشده است!")
			print("   لطفاً از طریق پنل ادمین، رمز webhook را تنظیم کنید.")
			return 1
		
		# بررسی وضعیت webhook فعلی
		print(f"\n🔍 بررسی وضعیت webhook فعلی...")
		provider = TelegramProvider(bot_token=bot_token, proxy_config=proxy_cfg if proxy_enabled else None)
		
		# اگر proxy فعال است، نمی‌توانیم مستقیماً از Telegram API استفاده کنیم
		if not proxy_enabled:
			webhook_info = get_webhook_info(bot_token)
			if webhook_info.get("ok"):
				result = webhook_info.get("result", {})
				url = result.get("url", "")
				pending_count = result.get("pending_update_count", 0)
				last_error_date = result.get("last_error_date")
				last_error_message = result.get("last_error_message")
				
				print(f"\n📊 وضعیت webhook:")
				if url:
					print(f"  - URL: {url}")
					print(f"  - Pending Updates: {pending_count}")
					if last_error_date:
						print(f"  - Last Error Date: {last_error_date}")
						print(f"  - Last Error: {last_error_message}")
				else:
					print(f"  - ⚠️  Webhook ثبت نشده است!")
			else:
				print(f"\n⚠️  نتوانستیم وضعیت webhook را بررسی کنیم: {webhook_info.get('description', 'Unknown error')}")
		else:
			print(f"\n⚠️  در حالت proxy، نمی‌توانیم مستقیماً وضعیت webhook را بررسی کنیم.")
		
		# نمایش URL مورد انتظار
		if proxy_enabled:
			base_url = str(proxy_cfg.get("base_url")).rstrip("/")
			expected_url = f"{base_url}/telegram/webhook"
		else:
			# باید از API استفاده کنیم تا URL صحیح را دریافت کنیم
			# برای این کار، باید از endpoint ثبت webhook استفاده کنیم
			expected_url = f"https://hsxn.hesabix.ir/api/v1/integrations/telegram/webhook/{webhook_secret}"
		
		print(f"\n📌 URL مورد انتظار webhook:")
		print(f"  {expected_url}")
		
		print(f"\n💡 برای ثبت webhook:")
		print(f"  1. از طریق پنل ادمین به بخش تنظیمات بروید")
		print(f"  2. روی دکمه 'ثبت Webhook' کلیک کنید")
		print(f"  3. یا از API endpoint زیر استفاده کنید:")
		print(f"     POST /api/v1/admin/system-settings/notifications/telegram/webhook")
		
		return 0
		
	except Exception as e:
		logger.error("check_webhook_failed", error=str(e), exc_info=True)
		print(f"\n❌ خطا: {e}")
		return 1
	finally:
		db.close()


if __name__ == "__main__":
	sys.exit(main())

