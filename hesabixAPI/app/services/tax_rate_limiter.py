"""
Rate Limiting برای ارسال فاکتورها به سامانه مالیاتی
"""

from __future__ import annotations

import time
import logging
from typing import Dict, Any, Optional
from datetime import datetime, timedelta

from app.core.cache import get_cache
from app.core.responses import ApiError

logger = logging.getLogger(__name__)


class TaxRateLimiter:
    """Rate limiter برای عملیات مالیاتی"""
    
    def __init__(self):
        self.cache = get_cache()
        self.enabled = self.cache.enabled
    
    def check_rate_limit(
        self,
        business_id: int,
        operation: str = "send_invoice",
        max_requests: int = 100,
        window_seconds: int = 3600,  # 1 ساعت
    ) -> tuple[bool, Optional[Dict[str, Any]]]:
        """
        بررسی rate limit
        
        Args:
            business_id: شناسه کسب‌وکار
            operation: نوع عملیات
            max_requests: حداکثر تعداد درخواست
            window_seconds: بازه زمانی (ثانیه)
        
        Returns:
            (allowed: bool, info: Optional[Dict]) - info شامل اطلاعات rate limit
        """
        if not self.enabled:
            return True, None
        
        cache_key = f"tax_rate_limit:{business_id}:{operation}"
        now = time.time()
        
        # دریافت اطلاعات فعلی
        rate_data = self.cache.get(cache_key)
        
        if not rate_data or not isinstance(rate_data, dict):
            # اولین درخواست
            rate_data = {
                "count": 1,
                "window_start": now,
                "reset_at": now + window_seconds,
            }
            self.cache.set(cache_key, rate_data, ttl=window_seconds)
            return True, {
                "remaining": max_requests - 1,
                "reset_at": datetime.fromtimestamp(rate_data["reset_at"]).isoformat(),
            }
        
        window_start = rate_data.get("window_start", now)
        count = rate_data.get("count", 0)
        
        # بررسی اینکه آیا window منقضی شده
        if now >= rate_data.get("reset_at", now + window_seconds):
            # شروع window جدید
            rate_data = {
                "count": 1,
                "window_start": now,
                "reset_at": now + window_seconds,
            }
            self.cache.set(cache_key, rate_data, ttl=window_seconds)
            return True, {
                "remaining": max_requests - 1,
                "reset_at": datetime.fromtimestamp(rate_data["reset_at"]).isoformat(),
            }
        
        # بررسی limit
        if count >= max_requests:
            reset_at = datetime.fromtimestamp(rate_data["reset_at"]).isoformat()
            return False, {
                "limit_exceeded": True,
                "current_count": count,
                "max_requests": max_requests,
                "reset_at": reset_at,
            }
        
        # افزایش تعداد
        rate_data["count"] = count + 1
        remaining = max_requests - rate_data["count"]
        self.cache.set(cache_key, rate_data, ttl=int(rate_data["reset_at"] - now))
        
        return True, {
            "remaining": remaining,
            "current_count": rate_data["count"],
            "reset_at": datetime.fromtimestamp(rate_data["reset_at"]).isoformat(),
        }
    
    def get_rate_limit_info(
        self,
        business_id: int,
        operation: str = "send_invoice",
    ) -> Dict[str, Any]:
        """دریافت اطلاعات rate limit"""
        if not self.enabled:
            return {"enabled": False}
        
        cache_key = f"tax_rate_limit:{business_id}:{operation}"
        rate_data = self.cache.get(cache_key)
        
        if not rate_data:
            return {
                "enabled": True,
                "current_count": 0,
                "remaining": 100,  # default
            }
        
        now = time.time()
        if now >= rate_data.get("reset_at", now + 3600):
            return {
                "enabled": True,
                "current_count": 0,
                "remaining": 100,
            }
        
        return {
            "enabled": True,
            "current_count": rate_data.get("count", 0),
            "remaining": 100 - rate_data.get("count", 0),  # default max
            "reset_at": datetime.fromtimestamp(rate_data["reset_at"]).isoformat(),
        }


# Global instance
_rate_limiter: Optional[TaxRateLimiter] = None


def get_tax_rate_limiter() -> TaxRateLimiter:
    """دریافت instance از TaxRateLimiter"""
    global _rate_limiter
    if _rate_limiter is None:
        _rate_limiter = TaxRateLimiter()
    return _rate_limiter

