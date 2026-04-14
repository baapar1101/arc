#!/usr/bin/env python3
"""اسکریپت افزودن افزونه گارانتی کالا"""
import sys
import os
from datetime import datetime

# اضافه کردن مسیر پروژه به sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from adapters.db.session import SessionLocal
from adapters.db.models.marketplace import MarketplacePlugin, MarketplacePluginPlan
from adapters.db.models.currency import Currency

def main():
    """افزودن افزونه گارانتی کالا"""
    db = SessionLocal()
    try:
        # پیدا کردن اولین ارز
        currency = db.query(Currency).order_by(Currency.id.asc()).first()
        if not currency:
            print("✗ خطا: هیچ ارزی در سیستم یافت نشد")
            return 1
        
        currency_id = currency.id
        print(f"✓ ارز پیدا شد: {currency.code} (ID: {currency_id})")
        
        # بررسی یا ایجاد افزونه
        plugin = db.query(MarketplacePlugin).filter(MarketplacePlugin.code == 'product_warranty').first()
        
        if plugin:
            print("✓ افزونه از قبل وجود دارد - به‌روزرسانی...")
            plugin.is_active = True
            plugin.updated_at = datetime.utcnow()
        else:
            print("✓ ایجاد افزونه جدید...")
            plugin = MarketplacePlugin(
                code='product_warranty',
                name='گارانتی کالا',
                description='افزونه مدیریت گارانتی کالا - امکان ثبت و پیگیری گارانتی محصولات فروخته شده',
                category='product_management',
                icon_url=None,
                is_active=True,
            )
            db.add(plugin)
            db.flush()
        
        plugin_id = plugin.id
        print(f"✓ افزونه ID: {plugin_id}")
        
        # بررسی یا ایجاد پلن ماهانه
        monthly_plan = db.query(MarketplacePluginPlan).filter(
            MarketplacePluginPlan.plugin_id == plugin_id,
            MarketplacePluginPlan.period == 'monthly'
        ).first()
        
        if not monthly_plan:
            print("✓ ایجاد پلن ماهانه...")
            monthly_plan = MarketplacePluginPlan(
                plugin_id=plugin_id,
                period='monthly',
                price=100000,
                currency_id=currency_id,
                is_active=True,
            )
            db.add(monthly_plan)
        else:
            print("✓ پلن ماهانه از قبل وجود دارد")
        
        # بررسی یا ایجاد پلن سالانه
        yearly_plan = db.query(MarketplacePluginPlan).filter(
            MarketplacePluginPlan.plugin_id == plugin_id,
            MarketplacePluginPlan.period == 'yearly'
        ).first()
        
        if not yearly_plan:
            print("✓ ایجاد پلن سالانه...")
            yearly_plan = MarketplacePluginPlan(
                plugin_id=plugin_id,
                period='yearly',
                price=1000000,
                currency_id=currency_id,
                is_active=True,
            )
            db.add(yearly_plan)
        else:
            print("✓ پلن سالانه از قبل وجود دارد")
        
        db.commit()
        print("✓ افزونه گارانتی کالا با موفقیت اضافه شد!")
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

