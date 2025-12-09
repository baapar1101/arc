"""
Dependency برای بررسی فعال بودن افزونه مدیریت تعمیرگاه
"""
from datetime import datetime
from functools import wraps
from typing import Optional

from sqlalchemy.orm import Session

from adapters.db.models.marketplace import MarketplacePlugin, BusinessPlugin
from app.core.responses import ApiError


def check_repair_shop_plugin_active(db: Session, business_id: int) -> bool:
    """
    بررسی فعال بودن افزونه مدیریت تعمیرگاه برای کسب‌وکار
    
    Args:
        db: Session دیتابیس
        business_id: شناسه کسب‌وکار
    
    Returns:
        True اگر افزونه فعال باشد، False در غیر این صورت
    """
    # پیدا کردن افزونه در marketplace
    plugin = db.query(MarketplacePlugin).filter(
        MarketplacePlugin.code == 'repair_shop_management',
        MarketplacePlugin.is_active == True  # noqa: E712
    ).first()
    
    if not plugin:
        return False
    
    # بررسی لایسنس کسب‌وکار
    license = db.query(BusinessPlugin).filter(
        BusinessPlugin.business_id == business_id,
        BusinessPlugin.plugin_id == plugin.id,
        BusinessPlugin.status == 'active'
    ).first()
    
    if not license:
        return False
    
    # بررسی تاریخ انقضا
    if license.ends_at and license.ends_at < datetime.utcnow():
        return False
    
    return True


def require_repair_shop_plugin(business_id_param: str = 'business_id'):
    """
    Decorator برای بررسی فعال بودن افزونه در endpoint ها
    
    Args:
        business_id_param: نام پارامتر business_id در تابع
    
    Usage:
        @require_repair_shop_plugin()
        def my_endpoint(business_id: int, db: Session = Depends(get_db)):
            ...
    """
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            # استخراج business_id از پارامترها
            business_id = kwargs.get(business_id_param)
            if not business_id:
                # اگر در kwargs نبود، از args بگیر (معمولاً اولین پارامتر است)
                if args:
                    business_id = args[0]
            
            # استخراج db از پارامترها
            db = kwargs.get('db')
            
            if not business_id or not db:
                raise ApiError(
                    "INVALID_PARAMETERS",
                    "پارامترهای لازم یافت نشد",
                    http_status=400
                )
            
            # بررسی فعال بودن افزونه
            if not check_repair_shop_plugin_active(db, business_id):
                raise ApiError(
                    "PLUGIN_NOT_ACTIVE",
                    "افزونه مدیریت تعمیرگاه فعال نیست. لطفاً ابتدا از بازار افزونه‌ها خریداری و فعال کنید.",
                    http_status=403,
                    extra_data={
                        "plugin_code": "repair_shop_management",
                        "required_action": "activate_plugin",
                        "marketplace_url": "/marketplace"
                    }
                )
            
            return func(*args, **kwargs)
        return wrapper
    return decorator


def get_repair_shop_plugin_info(db: Session) -> Optional[dict]:
    """
    دریافت اطلاعات افزونه مدیریت تعمیرگاه از marketplace
    
    Returns:
        دیکشنری حاوی اطلاعات افزونه یا None
    """
    plugin = db.query(MarketplacePlugin).filter(
        MarketplacePlugin.code == 'repair_shop_management'
    ).first()
    
    if not plugin:
        return None
    
    return {
        "id": plugin.id,
        "code": plugin.code,
        "name": plugin.name,
        "description": plugin.description,
        "category": plugin.category,
        "icon_url": plugin.icon_url,
        "is_active": plugin.is_active,
        "trial_days": plugin.trial_days,
        "trial_allowed": plugin.trial_allowed,
    }


def get_business_plugin_status(db: Session, business_id: int) -> dict:
    """
    دریافت وضعیت افزونه برای یک کسب‌وکار
    
    Returns:
        دیکشنری حاوی وضعیت افزونه
    """
    plugin = db.query(MarketplacePlugin).filter(
        MarketplacePlugin.code == 'repair_shop_management'
    ).first()
    
    if not plugin:
        return {
            "is_active": False,
            "status": "not_found",
            "message": "افزونه در سیستم یافت نشد"
        }
    
    license = db.query(BusinessPlugin).filter(
        BusinessPlugin.business_id == business_id,
        BusinessPlugin.plugin_id == plugin.id
    ).first()
    
    if not license:
        return {
            "is_active": False,
            "status": "not_purchased",
            "message": "افزونه خریداری نشده است",
            "plugin_info": get_repair_shop_plugin_info(db)
        }
    
    # بررسی انقضا
    is_expired = False
    if license.ends_at and license.ends_at < datetime.utcnow():
        is_expired = True
    
    return {
        "is_active": license.status == 'active' and not is_expired,
        "status": license.status,
        "is_trial": license.is_trial,
        "starts_at": license.starts_at.isoformat() if license.starts_at else None,
        "ends_at": license.ends_at.isoformat() if license.ends_at else None,
        "is_expired": is_expired,
        "auto_renew": license.auto_renew,
        "message": "افزونه فعال است" if (license.status == 'active' and not is_expired) else "افزونه منقضی شده است"
    }

