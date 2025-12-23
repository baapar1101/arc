"""
Health Check برای سامانه مالیاتی
"""

from __future__ import annotations

import logging
from typing import Dict, Any, Optional
from datetime import datetime

from app.core.settings import get_settings
from app.integrations.moadian.client import MoadianClient
from adapters.db.models.tax_setting import TaxSetting
from sqlalchemy.orm import Session

logger = logging.getLogger(__name__)


def check_tax_system_health(
    db: Session,
    business_id: int,
) -> Dict[str, Any]:
    """
    بررسی سلامت سامانه مالیاتی
    
    Args:
        db: Database session
        business_id: شناسه کسب‌وکار
    
    Returns:
        وضعیت سلامت سامانه
    """
    result = {
        "healthy": False,
        "timestamp": datetime.utcnow().isoformat(),
        "checks": {},
    }
    
    all_healthy = True
    
    # 1. بررسی تنظیمات
    tax_setting = (
        db.query(TaxSetting)
        .filter(TaxSetting.business_id == business_id)
        .first()
    )
    
    if not tax_setting:
        result["checks"]["settings"] = {
            "status": "error",
            "message": "تنظیمات مالیاتی یافت نشد",
        }
        all_healthy = False
    elif not (tax_setting.tax_memory_id and tax_setting.private_key and tax_setting.economic_code):
        result["checks"]["settings"] = {
            "status": "error",
            "message": "تنظیمات مالیاتی ناقص است",
        }
        all_healthy = False
    else:
        result["checks"]["settings"] = {
            "status": "ok",
            "message": "تنظیمات مالیاتی کامل است",
        }
    
    # 2. بررسی اتصال به سامانه (اگر تنظیمات موجود باشد)
    if tax_setting and all_healthy:
        try:
            settings = get_settings()
            client = MoadianClient(settings=settings, tax_setting=tax_setting)
            
            try:
                # تلاش برای احراز هویت
                client._ensure_authenticated()
                
                result["checks"]["connection"] = {
                    "status": "ok",
                    "message": "اتصال به سامانه برقرار است",
                }
                
                # بررسی token
                from app.core.cache import get_cache
                cache = get_cache()
                cache_key = f"moadian_token:{tax_setting.tax_memory_id}"
                token_data = cache.get(cache_key) if cache.enabled else None
                
                if token_data:
                    result["checks"]["authentication"] = {
                        "status": "ok",
                        "message": "احراز هویت موفق است",
                    }
                else:
                    result["checks"]["authentication"] = {
                        "status": "warning",
                        "message": "توکن احراز هویت یافت نشد",
                    }
                
            except Exception as e:
                result["checks"]["connection"] = {
                    "status": "error",
                    "message": f"خطا در اتصال: {str(e)}",
                }
                all_healthy = False
            finally:
                client.close()
                
        except Exception as e:
            result["checks"]["connection"] = {
                "status": "error",
                "message": f"خطا در ایجاد اتصال: {str(e)}",
            }
            all_healthy = False
    else:
        result["checks"]["connection"] = {
            "status": "skipped",
            "message": "بررسی اتصال به دلیل نبود تنظیمات انجام نشد",
        }
    
    # 3. بررسی Redis (برای cache و queue)
    from app.core.cache import get_cache
    cache = get_cache()
    if cache.enabled:
        try:
            cache.client.ping()
            result["checks"]["redis"] = {
                "status": "ok",
                "message": "Redis در دسترس است",
            }
        except Exception as e:
            result["checks"]["redis"] = {
                "status": "warning",
                "message": f"Redis در دسترس نیست: {str(e)}",
            }
    else:
        result["checks"]["redis"] = {
            "status": "warning",
            "message": "Redis غیرفعال است",
        }
    
    result["healthy"] = all_healthy
    return result

