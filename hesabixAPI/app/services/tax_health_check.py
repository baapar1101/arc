"""
Health Check برای سامانه مالیاتی

توجه: Redis فقط برای cache/صف اختیاری است و نباید وضعیت «اتصال مودیان»
را قطع نشان دهد. احراز هویت بدون Redis با لاگین مستقیم انجام می‌شود.
"""

from __future__ import annotations

import logging
from typing import Any, Dict

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
    بررسی سلامت سامانه مالیاتی (تنظیمات + اتصال واقعی به مودیان).

    Redis در نتیجه گزارش می‌شود اما روی ``healthy`` اثر نمی‌گذارد.
    """
    result: Dict[str, Any] = {
        "healthy": False,
        "timestamp": datetime.utcnow().isoformat(),
        "checks": {},
    }

    connection_ok = False
    settings_ok = False

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
    elif not (tax_setting.tax_memory_id and tax_setting.private_key and tax_setting.economic_code):
        result["checks"]["settings"] = {
            "status": "error",
            "message": "تنظیمات مالیاتی ناقص است",
        }
    else:
        settings_ok = True
        result["checks"]["settings"] = {
            "status": "ok",
            "message": "تنظیمات مالیاتی کامل است",
        }

    # 2. بررسی اتصال به سامانه (مستقل از Redis)
    if tax_setting and settings_ok:
        client = None
        try:
            settings = get_settings()
            client = MoadianClient(settings=settings, tax_setting=tax_setting)
            api_version = getattr(client, "api_version", "v1")

            # لاگین واقعی؛ توکن در حافظهٔ کلاینت نگه داشته می‌شود (بدون نیاز به Redis)
            token = client.ensure_authenticated()

            if token:
                connection_ok = True
                result["checks"]["connection"] = {
                    "status": "ok",
                    "message": "اتصال به سامانه برقرار است",
                    "api_version": api_version,
                }
                result["checks"]["authentication"] = {
                    "status": "ok",
                    "message": "احراز هویت موفق است",
                    "api_version": api_version,
                }
            else:
                result["checks"]["connection"] = {
                    "status": "error",
                    "message": "توکن احراز هویت دریافت نشد",
                }
                result["checks"]["authentication"] = {
                    "status": "error",
                    "message": "احراز هویت ناموفق بود",
                }
        except Exception as e:
            logger.warning(
                "tax health connection check failed business_id=%s: %s",
                business_id,
                e,
                exc_info=True,
            )
            result["checks"]["connection"] = {
                "status": "error",
                "message": f"خطا در اتصال: {str(e)}",
            }
            result["checks"]["authentication"] = {
                "status": "error",
                "message": "احراز هویت انجام نشد",
            }
        finally:
            if client is not None:
                try:
                    client.close()
                except Exception:
                    pass
    else:
        result["checks"]["connection"] = {
            "status": "skipped",
            "message": "بررسی اتصال به دلیل نبود تنظیمات انجام نشد",
        }

    # 3. Redis — اختیاری؛ هرگز healthy را false نمی‌کند
    try:
        from app.core.cache import get_cache

        cache = get_cache()
        if cache.enabled:
            try:
                cache.client.ping()
                result["checks"]["redis"] = {
                    "status": "ok",
                    "message": "Redis در دسترس است (اختیاری برای کش توکن)",
                    "required_for_moadian": False,
                }
            except Exception as e:
                result["checks"]["redis"] = {
                    "status": "info",
                    "message": (
                        f"Redis در دسترس نیست ({e}). "
                        "اتصال مودیان بدون Redis هم کار می‌کند."
                    ),
                    "required_for_moadian": False,
                }
        else:
            result["checks"]["redis"] = {
                "status": "info",
                "message": "Redis غیرفعال است؛ اتصال مودیان بدون Redis برقرار می‌شود.",
                "required_for_moadian": False,
            }
    except Exception as e:
        result["checks"]["redis"] = {
            "status": "info",
            "message": f"بررسی Redis انجام نشد ({e})؛ برای مودیان الزامی نیست.",
            "required_for_moadian": False,
        }

    result["healthy"] = bool(settings_ok and connection_ok)
    return result
