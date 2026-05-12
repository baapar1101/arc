#!/usr/bin/env python3
"""Register Basalam connector plugin in marketplace."""

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
            print("✗ No currency found")
            return 1

        plugin = db.query(MarketplacePlugin).filter(MarketplacePlugin.code == "basalam_connector").first()
        if plugin:
            print("✓ Plugin already exists, updating")
            plugin.is_active = True
            plugin.updated_at = datetime.utcnow()
        else:
            plugin = MarketplacePlugin(
                code="basalam_connector",
                name="اتصال باسلام",
                description=(
                    "اتصال کامل به باسلام برای دریافت وب‌هوک، همگام‌سازی سفارش/محصول، "
                    "بریج چت و پشتیبانی از اتوماسیون‌های مرتبط."
                ),
                category="integration",
                icon_url=None,
                is_active=True,
                trial_days=14,
                trial_allowed=True,
            )
            db.add(plugin)
            db.flush()

        plugin_id = plugin.id
        plan_prices = (("monthly", 250000), ("yearly", 2500000))
        for period, price in plan_prices:
            plan = (
                db.query(MarketplacePluginPlan)
                .filter(MarketplacePluginPlan.plugin_id == plugin_id, MarketplacePluginPlan.period == period)
                .first()
            )
            if not plan:
                db.add(
                    MarketplacePluginPlan(
                        plugin_id=plugin_id,
                        period=period,
                        price=price,
                        currency_id=currency.id,
                        is_active=True,
                    )
                )

        db.commit()
        print(f"✓ Basalam plugin ready (plugin_id={plugin_id})")
        return 0
    except Exception as exc:
        db.rollback()
        print(f"✗ Failed: {exc}")
        return 1
    finally:
        db.close()


if __name__ == "__main__":
    raise SystemExit(main())
