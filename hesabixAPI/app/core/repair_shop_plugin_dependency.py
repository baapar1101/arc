"""
Dependency برای بررسی فعال بودن افزونه مدیریت تعمیرگاه
"""
from datetime import datetime
from functools import wraps
from typing import Optional

from sqlalchemy.orm import Session

from adapters.db.models.marketplace import MarketplacePlugin, BusinessPlugin
from app.core.plugin_license import (
    SOURCE_SYSTEM_DEFAULT,
    is_plugin_active,
    plugin_is_globally_enabled,
)
from app.core.responses import ApiError

PLUGIN_CODE = "repair_shop_management"


def check_repair_shop_plugin_active(db: Session, business_id: int) -> bool:
    """
    بررسی فعال بودن افزونه مدیریت تعمیرگاه برای کسب‌وکار
    
    Args:
        db: Session دیتابیس
        business_id: شناسه کسب‌وکار
    
    Returns:
        True اگر افزونه فعال باشد، False در غیر این صورت
    """
    return is_plugin_active(db, business_id, PLUGIN_CODE)


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
                raise ApiError("INVALID_PARAMETERS", "INVALID_PARAMETERS",
                    http_status=400
                )
            
            # بررسی فعال بودن افزونه
            if not check_repair_shop_plugin_active(db, business_id):
                raise ApiError("PLUGIN_NOT_ACTIVE", "PLUGIN_NOT_ACTIVE",
                    http_status=403,
                    details={
                        "plugin_code": PLUGIN_CODE,
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
        MarketplacePlugin.code == PLUGIN_CODE
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
        MarketplacePlugin.code == PLUGIN_CODE
    ).first()
    
    if not plugin:
        return {
            "is_active": False,
            "status": "not_found",
            "message": "PLUGIN_NOT_FOUND"
        }
    
    globally_enabled = plugin_is_globally_enabled(plugin)
    license = db.query(BusinessPlugin).filter(
        BusinessPlugin.business_id == business_id,
        BusinessPlugin.plugin_id == plugin.id
    ).first()
    
    if not license:
        if globally_enabled:
            return {
                "is_active": True,
                "status": "active",
                "source": SOURCE_SYSTEM_DEFAULT,
                "globally_enabled": True,
                "message": "PLUGIN_ACTIVE",
                "plugin_info": get_repair_shop_plugin_info(db),
            }
        return {
            "is_active": False,
            "status": "not_purchased",
            "message": "PLUGIN_NOT_PURCHASED",
            "plugin_info": get_repair_shop_plugin_info(db)
        }
    
    # بررسی انقضا
    is_expired = False
    if license.ends_at:
        ends_at_val = (
            license.ends_at.date()
            if isinstance(license.ends_at, datetime)
            else license.ends_at
        )
        if ends_at_val < datetime.utcnow().date():
            is_expired = True
    
    row_active = license.status == 'active' and not is_expired
    is_active = bool(globally_enabled or row_active)
    return {
        "is_active": is_active,
        "status": "active" if is_active else license.status,
        "is_trial": False if globally_enabled else license.is_trial,
        "starts_at": license.starts_at,
        "ends_at": None if globally_enabled else license.ends_at,
        "is_expired": False if globally_enabled else is_expired,
        "auto_renew": license.auto_renew,
        "globally_enabled": globally_enabled,
        "message": "PLUGIN_ACTIVE" if is_active else "PLUGIN_EXPIRED"
    }

