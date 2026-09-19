#!/usr/bin/env python3
"""ثبت افزونه حقوق و دستمزد در بازار افزونه‌ها."""

import os
import sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from adapters.db.session import SessionLocal
from adapters.db.models.currency import Currency
from adapters.db.models.marketplace import MarketplacePlugin, MarketplacePluginPlan


def main() -> int:
	db = SessionLocal()
	try:
		currency = db.query(Currency).order_by(Currency.id.asc()).first()
		if not currency:
			print("✗ خطا: هیچ ارزی در سیستم یافت نشد")
			return 1
		currency_id = currency.id

		plugin = db.query(MarketplacePlugin).filter(MarketplacePlugin.code == "payroll").first()
		if plugin:
			print("✓ افزونه از قبل وجود دارد — به‌روزرسانی...")
			plugin.name = "حقوق و دستمزد"
			plugin.description = (
				"مدیریت جامع حقوق و دستمزد: تعریف انعطاف‌پذیر آیتم‌های حقوق (مزایا، کسورات، هزینه کارفرما) "
				"با نگاشت حساب از دفتر کل، ثبت پرسنل، دوره‌های حقوق، اجرای حقوق و صدور اسناد حسابداری."
			)
			plugin.category = "hr_payroll"
			plugin.is_active = True
			plugin.trial_days = 14
			plugin.trial_allowed = True
			plugin.updated_at = datetime.utcnow()
		else:
			plugin = MarketplacePlugin(
				code="payroll",
				name="حقوق و دستمزد",
				description=(
					"مدیریت جامع حقوق و دستمزد: تعریف انعطاف‌پذیر آیتم‌های حقوق (مزایا، کسورات، هزینه کارفرما) "
					"با نگاشت حساب از دفتر کل، ثبت پرسنل، دوره‌های حقوق، اجرای حقوق و صدور اسناد حسابداری."
				),
				category="hr_payroll",
				icon_url=None,
				is_active=True,
				trial_days=14,
				trial_allowed=True,
			)
			db.add(plugin)
			db.flush()

		plugin_id = plugin.id

		for period, price in (("monthly", 180_000), ("yearly", 1_800_000)):
			p = (
				db.query(MarketplacePluginPlan)
				.filter(MarketplacePluginPlan.plugin_id == plugin_id, MarketplacePluginPlan.period == period)
				.first()
			)
			if not p:
				db.add(
					MarketplacePluginPlan(
						plugin_id=plugin_id,
						period=period,
						price=price,
						currency_id=currency_id,
						is_active=True,
					)
				)

		db.commit()
		print(f"✓ افزونه حقوق و دستمزد آماده شد (plugin_id={plugin_id}).")
		return 0
	except Exception as e:
		db.rollback()
		print(f"✗ خطا: {e}")
		import traceback

		traceback.print_exc()
		return 1
	finally:
		db.close()


if __name__ == "__main__":
	sys.exit(main())
