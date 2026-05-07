from functools import wraps
from typing import Callable, Any, get_type_hints, Optional
import inspect
import json

from fastapi import Depends
from sqlalchemy.orm import Session
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import ApiError
from adapters.db.session import get_db
from fastapi import Request

from app.core.crm_web_chat_permissions import check_crm_web_chat_capability


def _extract_auth_context(args, kwargs):
    """جستجوی AuthContext در آرگومان‌های تابع"""
    for value in kwargs.values():
        if isinstance(value, AuthContext):
            return value
    for value in args:
        if isinstance(value, AuthContext):
            return value
    return None


def require_app_permission(permission: str):
    """Decorator برای بررسی دسترسی در سطح اپلیکیشن"""
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        async def wrapper(*args, **kwargs) -> Any:
            ctx = _extract_auth_context(args, kwargs)
            
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
        async def wrapper(*args, **kwargs) -> Any:
            ctx = _extract_auth_context(args, kwargs)
            
            if not ctx:
                raise ApiError("UNAUTHORIZED", "Authentication required", http_status=401)
            
            if not ctx.is_superadmin():
                raise ApiError("FORBIDDEN", "Superadmin access required", http_status=403)
            
            result = func(*args, **kwargs)
            if inspect.isawaitable(result):
                result = await result
            return result
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
            from adapters.db.session import get_db_session
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

            # دسترسی به DB و کاربر با استفاده از context manager برای جلوگیری از connection leak
            with get_db_session() as db:
                ctx = get_current_user(request, db)

                # استخراج business_id از kwargs یا path params
                business_id = kwargs.get(business_id_param)
                if business_id is None:
                    try:
                        business_id = request.path_params.get(business_id_param)
                    except Exception:
                        business_id = None

                if business_id:
                    logger.debug(f"require_business_access: Checking access for user {ctx.get_user_id()} to business {business_id}")
                    
                    has_access = ctx.can_access_business(int(business_id))
                    
                    if not has_access:
                        logger.warning(f"User {ctx.get_user_id()} does not have access to business {business_id}")
                        raise ApiError("FORBIDDEN", f"No access to business {business_id}", http_status=403)

            # فراخوانی تابع اصلی و await در صورت نیاز (خارج از context manager)
            result = func(*args, **kwargs)
            if inspect.isawaitable(result):
                result = await result
            return result
        # Preserve original signature so FastAPI sees correct parameters (including Request)
        sig = inspect.signature(func)
        wrapper.__signature__ = sig  # type: ignore[attr-defined]
        # Preserve/evaluate annotations; ensure 'request' is explicitly FastAPI Request
        try:
            evaluated = get_type_hints(func, globalns=getattr(func, "__globals__", None))  # type: ignore[attr-defined]
        except Exception:
            evaluated = getattr(func, "__annotations__", {})
        # Force request annotation if present in params
        if 'request' in sig.parameters:
            try:
                from fastapi import Request as _FastapiRequest  # local import to avoid cycles
                evaluated = dict(evaluated or {})
                evaluated['request'] = _FastapiRequest
            except Exception:
                pass
        wrapper.__annotations__ = evaluated  # type: ignore[attr-defined]
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


def require_business_access_dep(request: Request, db=Depends(get_db)) -> None:
    """FastAPI dependency برای بررسی دسترسی به کسب‌وکار در مسیرهای دارای business_id."""
    ctx = get_current_user(request, db)
    business_id = None
    try:
        business_id = request.path_params.get("business_id")
    except Exception:
        business_id = None
    if business_id is None:
        # اگر مسیر business_id ندارد، عبور می‌کنیم
        return
    if not ctx.can_access_business(int(business_id)):
        raise ApiError("FORBIDDEN", f"No access to business {business_id}", http_status=403)


def require_business_permission_dep(section: str, action: str = None, business_id_param: str = "business_id"):
    """FastAPI dependency برای بررسی دسترسی کسب و کار با business_id از path parameter.
    
    این dependency برای endpoint هایی استفاده می‌شود که business_id را در path دارند
    و باید دسترسی کسب و کار را با همان business_id چک کنند.
    
    Args:
        section: بخش دسترسی (مثل "people", "sales")
        action: عملیات دسترسی (مثل "add", "write"). اگر None باشد، فقط دسترسی به کسب و کار چک می‌شود
        business_id_param: نام پارامتر business_id در path (پیش‌فرض: "business_id")
    
    استفاده:
        _: None = Depends(require_business_permission_dep("people", "add"))
    """
    def _dependency(
        request: Request,
        auth_context: AuthContext = Depends(get_current_user),
        db: Session = Depends(get_db)
    ) -> None:
        import logging
        logger = logging.getLogger(__name__)
        
        # استخراج business_id از path parameters
        business_id = None
        try:
            business_id = request.path_params.get(business_id_param)
            if business_id:
                business_id = int(business_id)
        except (ValueError, TypeError, AttributeError) as e:
            logger.warning(f"Could not extract business_id from path: {e}")
            business_id = None
        
        if not business_id:
            raise ApiError("BAD_REQUEST", f"business_id parameter not found in path", http_status=400)
        
        logger.info(f"=== require_business_permission_dep ===")
        logger.info(f"Section: {section}, Action: {action}")
        logger.info(f"Business ID: {business_id}")
        logger.info(f"User ID: {auth_context.get_user_id()}")
        
        # بررسی دسترسی به کسب و کار
        if not auth_context.can_access_business(business_id):
            logger.warning(f"User {auth_context.get_user_id()} does not have access to business {business_id}")
            raise ApiError("FORBIDDEN", f"No access to business {business_id}", http_status=403)
        
        # اگر action مشخص نشده، فقط دسترسی به کسب و کار کافی است
        if action is None:
            logger.info(f"User {auth_context.get_user_id()} has access to business {business_id}")
            return
        
        # SuperAdmin تمام دسترسی‌ها را دارد
        if auth_context.is_superadmin():
            logger.info(f"User {auth_context.get_user_id()} is superadmin, granting permission")
            return
        
        # مالک کسب و کار تمام دسترسی‌ها را دارد
        if auth_context.is_business_owner(business_id):
            logger.info(f"User {auth_context.get_user_id()} is business owner of {business_id}, granting permission")
            return
        
        # بررسی دسترسی کسب و کار برای business_id مشخص شده
        # برای این کار باید مستقیماً از دیتابیس permission را بخوانیم
        # چون has_business_permission از self.business_id استفاده می‌کند
        from adapters.db.repositories.business_permission_repo import BusinessPermissionRepository
        repo = BusinessPermissionRepository(db)
        permission_obj = repo.get_by_user_and_business(auth_context.get_user_id(), business_id)
        
        if not permission_obj or not permission_obj.business_permissions:
            logger.warning(f"User {auth_context.get_user_id()} has no permissions for business {business_id}")
            raise ApiError("FORBIDDEN", f"Missing business permission: {section}.{action}", http_status=403)
        
        # نرمال‌سازی permissions
        permissions = auth_context._normalize_permissions_value(permission_obj.business_permissions)
        logger.info(f"User permissions for business {business_id}: {permissions}")
        
        # بررسی دسترسی بخش
        if section not in permissions:
            logger.warning(f"User {auth_context.get_user_id()} does not have section '{section}' for business {business_id}")
            raise ApiError("FORBIDDEN", f"Missing business permission: {section}.{action}", http_status=403)
        
        section_perms = permissions[section]
        
        # اگر بخش خالی است، فقط خواندن مجاز است
        if not section_perms:
            if action == "read" or action == "view":
                logger.info(f"User {auth_context.get_user_id()} has read permission for section '{section}'")
                return
            else:
                logger.warning(f"User {auth_context.get_user_id()} does not have permission '{section}.{action}' (only read)")
                raise ApiError("FORBIDDEN", f"Missing business permission: {section}.{action}", http_status=403)
        
        # بررسی دسترسی خاص
        # پشتیبانی از هم add و هم write برای سازگاری
        # همچنین پشتیبانی از edit برای add و بالعکس
        has_permission = (
            section_perms.get(action, False) or
            (action == "add" and (section_perms.get("write", False) or section_perms.get("edit", False))) or
            (action == "write" and (section_perms.get("add", False) or section_perms.get("edit", False))) or
            (action == "edit" and (section_perms.get("add", False) or section_perms.get("write", False)))
        )
        
        if not has_permission:
            logger.warning(f"User {auth_context.get_user_id()} does not have permission '{section}.{action}' for business {business_id}")
            raise ApiError("FORBIDDEN", f"Missing business permission: {section}.{action}", http_status=403)
        
        logger.info(f"User {auth_context.get_user_id()} has permission '{section}.{action}' for business {business_id}")
        logger.info(f"=== require_business_permission_dep END ===")
    
    return _dependency


def _permission_action_match(section_perms: dict, action: str) -> bool:
    if not isinstance(section_perms, dict):
        return False
    return (
        section_perms.get(action, False) or
        (action == "add" and (section_perms.get("write", False) or section_perms.get("edit", False))) or
        (action == "write" and (section_perms.get("add", False) or section_perms.get("edit", False))) or
        (action == "edit" and (section_perms.get("add", False) or section_perms.get("write", False))) or
        (action == "view" and section_perms.get("read", False)) or
        (action == "read" and section_perms.get("view", False))
    )


def get_business_permissions_for_user(auth_context: AuthContext, db: Session, business_id: int) -> Optional[dict]:
    from adapters.db.repositories.business_permission_repo import BusinessPermissionRepository
    repo = BusinessPermissionRepository(db)
    permission_obj = repo.get_by_user_and_business(auth_context.get_user_id(), business_id)
    if not permission_obj or not permission_obj.business_permissions:
        return None
    return auth_context._normalize_permissions_value(permission_obj.business_permissions)


def has_business_permission_for_business(
    auth_context: AuthContext,
    db: Session,
    business_id: int,
    section: str,
    action: str,
) -> bool:
    if auth_context.is_superadmin() or auth_context.is_business_owner(business_id):
        return True
    permissions = get_business_permissions_for_user(auth_context, db, business_id)
    if not permissions or section not in permissions:
        return False
    section_perms = permissions[section]
    if not section_perms:
        return action in ("read", "view")
    return _permission_action_match(section_perms, action)


_INVOICE_TYPE_PERMISSION_KEYS = {
    "invoice_sales": "sales",
    "invoice_sales_return": "sales_return",
    "invoice_purchase": "purchase",
    "invoice_purchase_return": "purchase_return",
    "invoice_waste": "waste",
    "invoice_direct_consumption": "direct_consumption",
    "invoice_production": "production",
}


def normalize_invoice_type_value(raw_value: object) -> Optional[str]:
    if raw_value is None:
        return None
    value = str(raw_value).strip()
    if not value:
        return None
    if value.startswith("invoice_"):
        return value
    candidate = f"invoice_{value}"
    if candidate in _INVOICE_TYPE_PERMISSION_KEYS:
        return candidate
    return value


def has_invoice_type_permission_for_business(
    auth_context: AuthContext,
    db: Session,
    business_id: int,
    invoice_type: object,
    action: str,
) -> bool:
    normalized_type = normalize_invoice_type_value(invoice_type)
    if not normalized_type:
        return False
    if has_business_permission_for_business(auth_context, db, business_id, "invoices", action):
        # Backward compatible default: legacy invoices.* means all invoice types.
        return True
    if auth_context.is_superadmin() or auth_context.is_business_owner(business_id):
        return True
    permissions = get_business_permissions_for_user(auth_context, db, business_id)
    if not permissions:
        return False
    type_key = _INVOICE_TYPE_PERMISSION_KEYS.get(normalized_type)
    if not type_key:
        return False
    section = permissions.get("invoice_types") or {}
    return bool(section.get(type_key, False))


def allowed_invoice_types_for_business(
    auth_context: AuthContext,
    db: Session,
    business_id: int,
    action: str,
) -> list[str]:
    all_types = list(_INVOICE_TYPE_PERMISSION_KEYS.keys())
    if has_business_permission_for_business(auth_context, db, business_id, "invoices", action):
        return all_types
    if auth_context.is_superadmin() or auth_context.is_business_owner(business_id):
        return all_types
    permissions = get_business_permissions_for_user(auth_context, db, business_id) or {}
    section = permissions.get("invoice_types") or {}
    allowed = []
    for doc_type, key in _INVOICE_TYPE_PERMISSION_KEYS.items():
        if section.get(key, False):
            allowed.append(doc_type)
    return allowed


def require_invoice_type_permission_from_payload_dep(
    action: str,
    business_id_param: str = "business_id",
    payload_field: str = "invoice_type",
):
    async def _dependency(
        request: Request,
        auth_context: AuthContext = Depends(get_current_user),
        db: Session = Depends(get_db),
    ) -> None:
        try:
            business_id = int(request.path_params.get(business_id_param))
        except Exception:
            raise ApiError("BAD_REQUEST", "business_id parameter not found in path", http_status=400)

        if not auth_context.can_access_business(business_id):
            raise ApiError("FORBIDDEN", f"No access to business {business_id}", http_status=403)

        body = None
        try:
            body = await request.json()
        except Exception:
            raw = await request.body()
            if raw:
                try:
                    body = json.loads(raw.decode("utf-8"))
                except Exception:
                    body = None

        invoice_type = body.get(payload_field) if isinstance(body, dict) else None
        if not has_invoice_type_permission_for_business(auth_context, db, business_id, invoice_type, action):
            raise ApiError("FORBIDDEN", f"Missing invoice type permission for {invoice_type}", http_status=403)

    return _dependency


def require_business_permission_by_entity_dep(
    section: str,
    action: str,
    entity_model,
    entity_id_param: str = None,
    business_id_field: str = "business_id",
    allow_null_business_id: bool = False,
    business_id_param: str = "business_id",
    entity_validator: Callable = None
):
    """FastAPI dependency برای بررسی دسترسی کسب و کار برای endpoint هایی که business_id در path ندارند.
    
    این dependency برای endpoint هایی استفاده می‌شود که ID دیگری در path دارند (مثل person_id, document_id)
    و باید ابتدا business_id را از entity بگیرند و سپس permission را چک کنند.
    
    Args:
        section: بخش دسترسی (مثل "people", "bank_accounts")
        action: عملیات دسترسی (مثل "add", "write", "delete")
        entity_model: مدل SQLAlchemy برای entity (مثل Person, Document)
        entity_id_param: نام پارامتر entity_id در path (مثل "person_id", "document_id")
                         اگر None باشد، از نام مدل استفاده می‌شود (مثل Person -> "person_id")
        business_id_field: نام فیلد business_id در مدل (پیش‌فرض: "business_id")
        allow_null_business_id: اگر True باشد، موجودیت‌هایی با business_id = None (مثل حساب‌های عمومی) را پشتیبانی می‌کند
                                در این صورت از business_id موجود در path استفاده می‌شود
        business_id_param: نام پارامتر business_id در path (پیش‌فرض: "business_id")
        entity_validator: تابع اختیاری برای اعتبارسنجی entity (مثل بررسی نوع سند)
                         اگر مشخص شده باشد و entity معتبر نباشد، خطای 404 برمی‌گرداند
                         تابع باید entity را به عنوان آرگومان بگیرد و True/False برگرداند
    
    استفاده:
        _: None = Depends(require_business_permission_by_entity_dep("people", "edit", Person, "person_id"))
        # برای موجودیت‌های عمومی (مثل Account):
        _: None = Depends(require_business_permission_by_entity_dep("chart_of_accounts", "view", Account, "account_id", allow_null_business_id=True))
        # با validator:
        _: None = Depends(require_business_permission_by_entity_dep("people_transactions", "delete", Document, "document_id", entity_validator=_validate_receipt_payment))
    """
    import logging
    logger = logging.getLogger(__name__)
    
    # اگر entity_id_param مشخص نشده، از نام مدل استفاده می‌کنیم
    if entity_id_param is None:
        model_name = entity_model.__name__.lower()
        # تبدیل نام مدل به snake_case برای پارامتر
        if model_name.endswith('y'):
            entity_id_param = model_name[:-1] + "_id"  # Person -> person_id
        elif model_name.endswith('s'):
            entity_id_param = model_name + "_id"  # Checks -> checks_id
        else:
            entity_id_param = model_name + "_id"
    
    def _dependency(
        request: Request,
        auth_context: AuthContext = Depends(get_current_user),
        db: Session = Depends(get_db),
    ) -> None:
        # استخراج entity_id از path parameters
        entity_id = None
        try:
            # از path_params بگیریم
            entity_id = request.path_params.get(entity_id_param)
            
            if entity_id:
                entity_id = int(entity_id)
        except (ValueError, TypeError, AttributeError, KeyError) as e:
            logger.warning(f"Could not extract {entity_id_param} from path: {e}")
            entity_id = None
        
        if not entity_id:
            raise ApiError("BAD_REQUEST", f"{entity_id_param} parameter not found in path", http_status=400)
        
        logger.info(f"=== require_business_permission_by_entity_dep ===")
        logger.info(f"Section: {section}, Action: {action}")
        logger.info(f"Entity ID: {entity_id}, Entity ID Param: {entity_id_param}")
        logger.info(f"User ID: {auth_context.get_user_id()}")
        
        # دریافت entity از دیتابیس
        entity = db.get(entity_model, entity_id)
        if not entity:
            logger.warning(f"Entity {entity_id} not found for model {entity_model.__name__}")
            raise ApiError("NOT_FOUND", f"Entity not found", http_status=404)
        
        # اعتبارسنجی entity با استفاده از validator (اگر مشخص شده باشد)
        if entity_validator is not None:
            if not entity_validator(entity):
                logger.warning(f"Entity {entity_id} failed validation")
                raise ApiError("NOT_FOUND", f"Entity not found", http_status=404)
        
        # استخراج business_id از entity
        business_id = getattr(entity, business_id_field, None)
        
        # اگر entity دارای business_id نیست و allow_null_business_id فعال است، از business_id موجود در path استفاده می‌کنیم
        if not business_id and allow_null_business_id:
            try:
                path_business_id = request.path_params.get(business_id_param)
                if path_business_id:
                    business_id = int(path_business_id)
                    logger.info(f"Entity {entity_id} is public (business_id is None), using business_id from path: {business_id}")
                else:
                    logger.error(f"Entity {entity_id} does not have {business_id_field} and {business_id_param} not found in path")
                    raise ApiError("BAD_REQUEST", f"Entity does not have business_id and {business_id_param} not found in path", http_status=400)
            except (ValueError, TypeError, AttributeError, KeyError) as e:
                logger.error(f"Could not extract {business_id_param} from path: {e}")
                raise ApiError("BAD_REQUEST", f"Entity does not have business_id and could not extract {business_id_param} from path", http_status=400)
        elif not business_id:
            logger.error(f"Entity {entity_id} does not have {business_id_field} field")
            raise ApiError("BAD_REQUEST", f"Entity does not have business_id", http_status=400)
        
        logger.info(f"Business ID extracted from entity: {business_id}")
        
        # بررسی دسترسی به کسب و کار
        if not auth_context.can_access_business(business_id):
            logger.warning(f"User {auth_context.get_user_id()} does not have access to business {business_id}")
            raise ApiError("FORBIDDEN", f"No access to business {business_id}", http_status=403)
        
        # SuperAdmin تمام دسترسی‌ها را دارد
        if auth_context.is_superadmin():
            logger.info(f"User {auth_context.get_user_id()} is superadmin, granting permission")
            return
        
        # مالک کسب و کار تمام دسترسی‌ها را دارد
        if auth_context.is_business_owner(business_id):
            logger.info(f"User {auth_context.get_user_id()} is business owner of {business_id}, granting permission")
            return
        
        # بررسی دسترسی کسب و کار برای business_id مشخص شده
        from adapters.db.repositories.business_permission_repo import BusinessPermissionRepository
        repo = BusinessPermissionRepository(db)
        permission_obj = repo.get_by_user_and_business(auth_context.get_user_id(), business_id)
        
        if not permission_obj or not permission_obj.business_permissions:
            logger.warning(f"User {auth_context.get_user_id()} has no permissions for business {business_id}")
            raise ApiError("FORBIDDEN", f"Missing business permission: {section}.{action}", http_status=403)
        
        # نرمال‌سازی permissions
        permissions = auth_context._normalize_permissions_value(permission_obj.business_permissions)
        logger.info(f"User permissions for business {business_id}: {permissions}")
        
        # بررسی دسترسی بخش
        if section not in permissions:
            logger.warning(f"User {auth_context.get_user_id()} does not have section '{section}' for business {business_id}")
            raise ApiError("FORBIDDEN", f"Missing business permission: {section}.{action}", http_status=403)
        
        section_perms = permissions[section]
        
        # اگر بخش خالی است، فقط خواندن مجاز است
        if not section_perms:
            if action == "read" or action == "view":
                logger.info(f"User {auth_context.get_user_id()} has read permission for section '{section}'")
                return
            else:
                logger.warning(f"User {auth_context.get_user_id()} does not have permission '{section}.{action}' (only read)")
                raise ApiError("FORBIDDEN", f"Missing business permission: {section}.{action}", http_status=403)
        
        # بررسی دسترسی خاص
        # پشتیبانی از هم add و هم write برای سازگاری
        # همچنین پشتیبانی از edit برای add و بالعکس
        has_permission = (
            section_perms.get(action, False) or
            (action == "add" and (section_perms.get("write", False) or section_perms.get("edit", False))) or
            (action == "write" and (section_perms.get("add", False) or section_perms.get("edit", False))) or
            (action == "edit" and (section_perms.get("add", False) or section_perms.get("write", False)))
        )
        
        if not has_permission:
            logger.warning(f"User {auth_context.get_user_id()} does not have permission '{section}.{action}' for business {business_id}")
            raise ApiError("FORBIDDEN", f"Missing business permission: {section}.{action}", http_status=403)
        
        logger.info(f"User {auth_context.get_user_id()} has permission '{section}.{action}' for business {business_id}")
        logger.info(f"=== require_business_permission_by_entity_dep END ===")
    
    return _dependency


def require_crm_web_chat_dep(capability: str, business_id_param: str = "business_id"):
	"""دسترسی ریزدانه چت وب: view | reply | manage_widgets | edit_conversations | delete_messages + legacy crm.view/write."""

	def _dependency(
		request: Request,
		auth_context: AuthContext = Depends(get_current_user),
		db: Session = Depends(get_db),
	) -> None:
		business_id = None
		try:
			business_id = request.path_params.get(business_id_param)
			if business_id:
				business_id = int(business_id)
		except (ValueError, TypeError, AttributeError):
			business_id = None
		if not business_id:
			raise ApiError("BAD_REQUEST", "business_id parameter not found in path", http_status=400)
		if not auth_context.can_access_business(business_id):
			raise ApiError("FORBIDDEN", f"No access to business {business_id}", http_status=403)
		if auth_context.is_superadmin():
			return
		if auth_context.is_business_owner(business_id):
			return
		from adapters.db.repositories.business_permission_repo import BusinessPermissionRepository

		repo = BusinessPermissionRepository(db)
		permission_obj = repo.get_by_user_and_business(auth_context.get_user_id(), business_id)
		if not permission_obj or not permission_obj.business_permissions:
			raise ApiError("FORBIDDEN", f"Missing crm web chat permission: {capability}", http_status=403)
		permissions = auth_context._normalize_permissions_value(permission_obj.business_permissions)
		if not check_crm_web_chat_capability(permissions, capability):
			raise ApiError("FORBIDDEN", f"Missing crm web chat permission: {capability}", http_status=403)

	return _dependency
