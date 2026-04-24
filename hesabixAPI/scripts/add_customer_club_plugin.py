#!/usr/bin/env python3
"""ثبت افزونه باشگاه مشتریان در بازار افزونه‌ها."""

import sys
import os
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from adapters.db.session import SessionLocal
from adapters.db.models.marketplace import MarketplacePlugin, MarketplacePluginPlan
from adapters.db.models.currency import Currency


def main() -> int:
	db = SessionLocal()
	try:
		currency = db.query(Currency).order_by(Currency.id.asc()).first()
		if not currency:
			print("✗ خطا: هیچ ارزی در سیستم یافت نشد")
			return 1
		currency_id = currency.id

		plugin = db.query(MarketplacePlugin).filter(MarketplacePlugin.code == "customer_club").first()
		if plugin:
			print("✓ افزونه از قبل وجود دارد — به‌روزرسانی...")
			plugin.is_active = True
			plugin.updated_at = datetime.utcnow()
		else:
			plugin = MarketplacePlugin(
				code="customer_club",
				name="باشگاه مشتریان",
				description=(
					"مدیریت باشگاه وفاداری: امتیاز خودکار از فاکتور فروش، کسر متناسب با برگشت از فروش، "
					"دفتر تراکنش و تنظیمات قوانین امتیاز به ازای هر کسب‌وکار."
				),
				category="crm_marketing",
				icon_url=None,
				is_active=True,
				trial_days=14,
				trial_allowed=True,
			)
			db.add(plugin)
			db.flush()

		plugin_id = plugin.id

		for period, price in (("monthly", 120000), ("yearly", 1200000)):
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
		print(f"✓ افزونه باشگاه مشتریان آماده شد (plugin_id={plugin_id}).")
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
