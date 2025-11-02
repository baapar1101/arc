from functools import wraps
from typing import Callable, Any, get_type_hints
import inspect

from fastapi import Depends
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import ApiError


def require_app_permission(permission: str):
    """Decorator برای بررسی دسترسی در سطح اپلیکیشن"""
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        async def wrapper(*args, **kwargs) -> Any:
            # پیدا کردن AuthContext در kwargs
            ctx = None
            for key, value in kwargs.items():
                if isinstance(value, AuthContext):
                    ctx = value
                    break
            
            if not ctx:
                raise ApiError("UNAUTHORIZED", "Authentication required", http_status=401)
            
            if not ctx.has_app_permission(permission):
                raise ApiError("FORBIDDEN", f"Missing app permission: {permission}", http_status=403)
            result = func(*args, **kwargs)
            if inspect.isawaitable(result):
                result = await result
            return result
        return wrapper
    return decorator


def require_business_permission(section: str, action: str):
    """Decorator برای بررسی دسترسی در سطح کسب و کار"""
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        def wrapper(*args, **kwargs) -> Any:
            ctx = get_current_user()
            if not ctx.has_business_permission(section, action):
                raise ApiError("FORBIDDEN", f"Missing business permission: {section}.{action}", http_status=403)
            return func(*args, **kwargs)
        return wrapper
    return decorator


def require_any_permission(section: str, action: str):
    """Decorator برای بررسی دسترسی در هر دو سطح (app یا business)"""
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        def wrapper(*args, **kwargs) -> Any:
            ctx = get_current_user()
            if not ctx.has_any_permission(section, action):
                raise ApiError("FORBIDDEN", f"Missing permission: {section}.{action}", http_status=403)
            return func(*args, **kwargs)
        return wrapper
    return decorator


def require_superadmin():
    """Decorator برای بررسی superadmin بودن"""
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        def wrapper(*args, **kwargs) -> Any:
            ctx = get_current_user()
            if not ctx.is_superadmin():
                raise ApiError("FORBIDDEN", "Superadmin access required", http_status=403)
            return func(*args, **kwargs)
        return wrapper
    return decorator


def require_business_access(business_id_param: str = "business_id"):
    """Decorator برای بررسی دسترسی به کسب و کار خاص.
    امضای اصلی endpoint حفظ می‌شود و Request از آرگومان‌ها استخراج می‌گردد.
    """
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        async def wrapper(*args, **kwargs) -> Any:
            import logging
            from fastapi import Request
            logger = logging.getLogger(__name__)

            # یافتن Request در args/kwargs
            request = None
            for arg in args:
                if isinstance(arg, Request):
                    request = arg
                    break
            if request is None:
                request = kwargs.get('request')
            if request is None:
                logger.error("Request not found in function arguments")
                raise ApiError("INTERNAL_ERROR", "Request not found", http_status=500)

            # دسترسی به DB و کاربر
            from adapters.db.session import get_db
            db = next(get_db())
            ctx = get_current_user(request, db)

            # استخراج business_id از kwargs یا path params
            business_id = kwargs.get(business_id_param)
            if business_id is None:
                try:
                    business_id = request.path_params.get(business_id_param)
                except Exception:
                    business_id = None

            if business_id:
                logger.info(f"=== require_business_access decorator ===")
                logger.info(f"Checking access for user {ctx.get_user_id()} to business {business_id}")
                logger.info(f"User context business_id: {ctx.business_id}")
                logger.info(f"Is superadmin: {ctx.is_superadmin()}")
                
                has_access = ctx.can_access_business(int(business_id))
                logger.info(f"Access check result: {has_access}")
                
                if not has_access:
                    logger.warning(f"User {ctx.get_user_id()} does not have access to business {business_id}")
                    raise ApiError("FORBIDDEN", f"No access to business {business_id}", http_status=403)
                else:
                    logger.info(f"User {ctx.get_user_id()} has access to business {business_id}")
            else:
                logger.info("No business_id provided, skipping access check")

            # فراخوانی تابع اصلی و await در صورت نیاز
            result = func(*args, **kwargs)
            if inspect.isawaitable(result):
                result = await result
            return result
        # Preserve original signature so FastAPI sees correct parameters (including Request)
        wrapper.__signature__ = inspect.signature(func)  # type: ignore[attr-defined]
        # Also preserve evaluated type annotations to avoid ForwardRef issues under __future__.annotations
        try:
            wrapper.__annotations__ = get_type_hints(func, globalns=getattr(func, "__globals__", None))  # type: ignore[attr-defined]
        except Exception:
            # Fallback to original annotations (may be string-based) if evaluation fails
            wrapper.__annotations__ = getattr(func, "__annotations__", {})
        return wrapper
    return decorator


# Decorator های ترکیبی برای استفاده آسان
def require_sales_write():
    """دسترسی نوشتن در بخش فروش"""
    return require_any_permission("sales", "write")


def require_sales_delete():
    """دسترسی حذف در بخش فروش"""
    return require_any_permission("sales", "delete")


def require_sales_approve():
    """دسترسی تأیید در بخش فروش"""
    return require_any_permission("sales", "approve")


def require_purchases_write():
    """دسترسی نوشتن در بخش خرید"""
    return require_any_permission("purchases", "write")


def require_accounting_write():
    """دسترسی نوشتن در بخش حسابداری"""
    return require_any_permission("accounting", "write")


def require_inventory_write():
    """دسترسی نوشتن در بخش موجودی"""
    return require_any_permission("inventory", "write")


def require_reports_export():
    """دسترسی صادرات گزارش"""
    return require_any_permission("reports", "export")


def require_settings_manage_users():
    """دسترسی مدیریت کاربران کسب و کار"""
    return require_any_permission("settings", "manage_users")


def require_user_management():
    """دسترسی مدیریت کاربران در سطح اپلیکیشن"""
    return require_app_permission("user_management")


def require_business_management():
    """دسترسی مدیریت کسب و کارها"""
    return require_app_permission("business_management")


def require_system_settings():
    """دسترسی تنظیمات سیستم"""
    return require_app_permission("system_settings")


def require_permission(permission: str):
    """Decorator عمومی برای بررسی دسترسی - wrapper برای require_app_permission"""
    return require_app_permission(permission)


# =========================
# FastAPI Dependencies (for Depends)
# =========================
def require_app_permission_dep(permission: str):
    """FastAPI dependency جهت بررسی دسترسی در سطح اپلیکیشن.

    استفاده:
        _: None = Depends(require_app_permission_dep("business_management"))
    """
    def _dependency(auth_context: AuthContext = Depends(get_current_user)) -> None:
        if not auth_context.has_app_permission(permission):
            raise ApiError("FORBIDDEN", f"Missing app permission: {permission}", http_status=403)
    return _dependency


def require_business_management_dep(auth_context: AuthContext = Depends(get_current_user)) -> None:
    """FastAPI dependency برای بررسی مجوز مدیریت کسب و کارها."""
    if not auth_context.has_app_permission("business_management"):
        raise ApiError("FORBIDDEN", "Missing app permission: business_management", http_status=403)


def require_business_access_dep(auth_context: AuthContext = Depends(get_current_user)) -> None:
    """FastAPI dependency برای بررسی دسترسی به کسب و کار."""
    # در اینجا می‌توانید منطق بررسی دسترسی به کسب و کار را پیاده‌سازی کنید
    # برای مثال: بررسی اینکه آیا کاربر دسترسی به کسب و کار دارد
    pass
