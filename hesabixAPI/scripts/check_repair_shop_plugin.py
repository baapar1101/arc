"""
اسکریپت بررسی وضعیت افزونه مدیریت تعمیرگاه
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from adapters.db.session import SessionLocal
from adapters.db.models.marketplace import MarketplacePlugin, MarketplacePluginPlan

def main():
    db = SessionLocal()
    
    try:
        plugin = db.query(MarketplacePlugin).filter(
            MarketplacePlugin.code == 'repair_shop_management'
        ).first()
        
        if plugin:
            print('\n' + '='*60)
            print('✅ افزونه مدیریت تعمیرگاه در دیتابیس یافت شد:')
            print('='*60)
            print(f'📦 ID: {plugin.id}')
            print(f'🏷️  نام: {plugin.name}')
            print(f'🔤 کد: {plugin.code}')
            print(f'📂 دسته: {plugin.category}')
            print(f'⚡ وضعیت: {"✅ فعال" if plugin.is_active else "❌ غیرفعال"}')
            print(f'🎁 Trial: {plugin.trial_days} روز ({"✅ مجاز" if plugin.trial_allowed else "❌ غیرمجاز"})')
            print()
            
            plans = db.query(MarketplacePluginPlan).filter(
                MarketplacePluginPlan.plugin_id == plugin.id
            ).all()
            
            print(f'💰 پلن‌های قیمت‌گذاری: ({len(plans)} پلن)')
            print('-'*60)
            for plan in plans:
                period_name = {
                    'monthly': 'ماهانه',
                    'yearly': 'سالانه',
                    'lifetime': 'مادام‌العمر'
                }.get(plan.period, plan.period)
                
                status = "✅" if plan.is_active else "❌"
                print(f'   {status} {period_name}: {int(plan.price):,} تومان')
            
            print('='*60)
            print('\n✅ افزونه با موفقیت ثبت شده و آماده استفاده است!')
            print('\n🔗 کاربران می‌توانند از مسیر زیر افزونه را خریداری کنند:')
            print('   GET /api/v1/marketplace/plugins')
            print('   POST /api/v1/marketplace/business/{business_id}/plugins/{plugin_id}/start-trial')
            print()
            
        else:
            print('❌ افزونه مدیریت تعمیرگاه در دیتابیس یافت نشد!')
            print('⚠️  لطفاً migration را اجرا کنید:')
            print('   alembic upgrade head')
    
    finally:
        db.close()

if __name__ == "__main__":
    main()

