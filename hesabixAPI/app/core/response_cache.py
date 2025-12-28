"""
Response Caching Middleware
برای cache کردن response های GET requests
"""

from __future__ import annotations

import hashlib
import json
import logging
from typing import Optional, Callable
from functools import wraps

from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware

from app.core.cache import get_cache
from app.core.auth_dependency import get_current_user, AuthContext
from adapters.db.session import get_db_session
from app.core.responses import ApiError

logger = logging.getLogger(__name__)

# Endpoints که نباید cache شوند
EXCLUDED_PATHS = {
    "/api/v1/health",
    "/api/v1/auth",
    "/api/v1/jobs",
    "/api/v1/admin",
}

# Endpoints که باید cache شوند (با TTL مشخص)
CACHE_CONFIG = {
    "/api/v1/products": {"ttl": 300, "vary_by": ["business_id", "user_id"]},  # 5 دقیقه
    "/api/v1/persons": {"ttl": 300, "vary_by": ["business_id", "user_id"]},  # 5 دقیقه
    "/api/v1/documents": {"ttl": 180, "vary_by": ["business_id", "user_id", "fiscal_year_id"]},  # 3 دقیقه
    "/api/v1/categories": {"ttl": 600, "vary_by": ["business_id"]},  # 10 دقیقه
    "/api/v1/accounts": {"ttl": 600, "vary_by": ["business_id"]},  # 10 دقیقه
}


def generate_cache_key(request: Request, vary_params: list[str] = None) -> str:
    """
    تولید کلید cache از request
    
    Args:
        request: FastAPI Request object
        vary_params: پارامترهایی که باید در cache key لحاظ شوند
    
    Returns:
        کلید cache
    """
    vary_params = vary_params or []
    
    # مسیر endpoint
    path = request.url.path
    
    # Query parameters (sorted برای consistency)
    query_params = dict(sorted(request.query_params.items()))
    
    # Headers مهم (فقط موارد غیرحساس/غیرقابل جعل برای authorization)
    headers = {}
    for header in ["Accept-Language"]:
        if header in request.headers:
            headers[header] = request.headers[header]

    # استخراج user_id/business_id به صورت امن:
    # نکته امنیتی: به X-Business-ID اعتماد نمی‌کنیم؛ از AuthContext (که خودش validate می‌کند) استفاده می‌کنیم.
    user_id: Optional[int] = None
    business_id: Optional[int] = None
    try:
        with get_db_session() as db:
            ctx = get_current_user(request, db)
            user_id = ctx.get_user_id()
            business_id = ctx.business_id
    except ApiError:
        # اگر احراز هویت نشد یا خطای دسترسی داشت، در cache-key user/business را لحاظ نمی‌کنیم
        user_id = None
        business_id = None
    except Exception:
        user_id = None
        business_id = None

    # fiscal_year_id هنوز از header می‌آید (کم‌ریسک برای cache-key)، اما به int محدودش می‌کنیم
    fiscal_year_id: Optional[int] = None
    fy_raw = request.headers.get("X-Fiscal-Year-ID")
    if fy_raw:
        try:
            fiscal_year_id = int(str(fy_raw).strip())
        except Exception:
            fiscal_year_id = None
    
    # ساخت cache key
    key_parts = [f"response:{path}"]
    
    # اضافه کردن query params
    if query_params:
        key_parts.append(f"query:{json.dumps(query_params, sort_keys=True)}")
    
    # اضافه کردن headers
    if headers:
        key_parts.append(f"headers:{json.dumps(headers, sort_keys=True)}")
    
    # اضافه کردن user_id اگر در vary_params باشد
    if "user_id" in vary_params and user_id:
        key_parts.append(f"user:{user_id}")
    
    # اضافه کردن business_id (امن: از ctx.business_id که validate شده)
    if "business_id" in vary_params and business_id:
        key_parts.append(f"business:{business_id}")
    
    # اضافه کردن fiscal_year_id
    if "fiscal_year_id" in vary_params and fiscal_year_id:
        key_parts.append(f"fiscal_year:{fiscal_year_id}")
    
    # Hash کردن برای کوتاه کردن key
    key_string = ":".join(key_parts)
    key_hash = hashlib.md5(key_string.encode()).hexdigest()
    
    return f"response_cache:{key_hash}"


class ResponseCacheMiddleware(BaseHTTPMiddleware):
    """Middleware برای cache کردن response های GET"""
    
    async def dispatch(self, request: Request, call_next: Callable):
        # فقط GET requests را cache می‌کنیم
        if request.method != "GET":
            return await call_next(request)
        
        # بررسی exclude paths
        for excluded_path in EXCLUDED_PATHS:
            if request.url.path.startswith(excluded_path):
                return await call_next(request)
        
        # بررسی cache config
        cache_config = None
        for path_prefix, config in CACHE_CONFIG.items():
            if request.url.path.startswith(path_prefix):
                cache_config = config
                break
        
        # اگر config وجود نداشت، cache نمی‌کنیم
        if not cache_config:
            return await call_next(request)
        
        # بررسی cache
        cache = get_cache()
        if not cache.enabled:
            return await call_next(request)
        
        # تولید cache key
        cache_key = generate_cache_key(
            request,
            vary_params=cache_config.get("vary_by", [])
        )
        
        # تلاش برای دریافت از cache
        cached_response = cache.get(cache_key)
        if cached_response is not None:
            logger.debug(f"Cache hit for {request.url.path}")
            return Response(
                content=json.dumps(cached_response),
                media_type="application/json",
                headers={
                    "X-Cache": "HIT",
                    "X-Cache-Key": cache_key,
                }
            )
        
        # اگر در cache نبود، request را پردازش کن
        response = await call_next(request)
        
        # فقط response های موفق را cache می‌کنیم
        if response.status_code == 200:
            try:
                # خواندن response body
                response_body = b""
                async for chunk in response.body_iterator:
                    response_body += chunk
                
                # Parse JSON
                try:
                    response_data = json.loads(response_body)
                    
                    # بررسی ساختار response (باید success=True باشد)
                    if isinstance(response_data, dict) and response_data.get("success"):
                        # Cache کردن
                        ttl = cache_config.get("ttl", 300)
                        cache.set(cache_key, response_data, ttl)
                        
                        logger.debug(f"Cached response for {request.url.path} with TTL {ttl}")
                        
                        # ساخت response جدید با body
                        new_response = Response(
                            content=response_body,
                            status_code=response.status_code,
                            headers=dict(response.headers),
                            media_type=response.media_type
                        )
                        new_response.headers["X-Cache"] = "MISS"
                        new_response.headers["X-Cache-Key"] = cache_key
                        return new_response
                except json.JSONDecodeError:
                    # اگر JSON نبود، cache نمی‌کنیم
                    # ساخت response جدید با body اصلی
                    return Response(
                        content=response_body,
                        status_code=response.status_code,
                        headers=dict(response.headers),
                        media_type=response.media_type
                    )
            except Exception as e:
                logger.warning(f"Error caching response: {e}")
                # در صورت خطا، response اصلی را برمی‌گردانیم
                # اما body را باید دوباره ساخت
                return Response(
                    content=response_body if 'response_body' in locals() else b"",
                    status_code=response.status_code,
                    headers=dict(response.headers),
                    media_type=response.media_type
                )
        
        return response


def cache_response(ttl: int = 300, vary_by: list[str] = None):
    """
    Decorator برای cache کردن response یک endpoint خاص
    
    Args:
        ttl: زمان انقضا به ثانیه
        vary_by: پارامترهایی که باید در cache key لحاظ شوند
    
    Example:
        @router.get("/products")
        @cache_response(ttl=600, vary_by=["business_id", "user_id"])
        async def get_products(...):
            ...
    """
    vary_by = vary_by or []
    
    def decorator(func: Callable):
        @wraps(func)
        async def wrapper(*args, **kwargs):
            # پیدا کردن request از args یا kwargs
            request = None
            for arg in args:
                if isinstance(arg, Request):
                    request = arg
                    break
            
            if request is None:
                request = kwargs.get("request")
            
            if request is None:
                # اگر request پیدا نشد، function را بدون cache اجرا کن
                return await func(*args, **kwargs)
            
            # تولید cache key
            cache_key = generate_cache_key(request, vary_params=vary_by)
            
            # بررسی cache
            cache = get_cache()
            if cache.enabled:
                cached_response = cache.get(cache_key)
                if cached_response is not None:
                    from fastapi.responses import JSONResponse
                    return JSONResponse(
                        content=cached_response,
                        headers={"X-Cache": "HIT", "X-Cache-Key": cache_key}
                    )
            
            # اجرای function
            response = await func(*args, **kwargs)
            
            # Cache کردن response
            if cache.enabled and isinstance(response, dict):
                if response.get("success"):
                    cache.set(cache_key, response, ttl)
                    # اگر response یک Response object است، header اضافه کن
                    if hasattr(response, "headers"):
                        response.headers["X-Cache"] = "MISS"
                        response.headers["X-Cache-Key"] = cache_key
            
            return response
        return wrapper
    return decorator


def invalidate_response_cache(pattern: str = None, path: str = None, **kwargs) -> int:
    """
    Invalidate cache برای یک endpoint یا pattern
    
    Args:
        pattern: Pattern برای invalidate (مثل "response_cache:products:*")
        path: مسیر endpoint (مثل "/api/v1/products")
        **kwargs: پارامترهای اضافی برای ساخت pattern
    
    Returns:
        تعداد کلیدهای invalidated
    """
    cache = get_cache()
    if not cache.enabled:
        return 0
    
    if pattern:
        return cache.delete_pattern(pattern)
    
    if path:
        # ساخت pattern از path
        pattern = f"response_cache:*{path}*"
        if kwargs:
            # اضافه کردن kwargs به pattern
            for key, value in kwargs.items():
                pattern += f":{key}:{value}"
        pattern += "*"
        return cache.delete_pattern(pattern)
    
    return 0

