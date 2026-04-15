from __future__ import annotations

from typing import List, Optional, Dict, Any
from datetime import datetime, timedelta
from sqlalchemy.orm import Session
from sqlalchemy import select, and_, func, or_
import logging

from adapters.db.repositories.business_repo import BusinessRepository
from adapters.db.repositories.fiscal_year_repo import FiscalYearRepository
from adapters.db.models.currency import Currency, BusinessCurrency
from adapters.db.repositories.business_permission_repo import BusinessPermissionRepository
from adapters.db.models.business import Business, BusinessType, BusinessField
from adapters.db.models.business_print_settings import BusinessPrintSettings
from adapters.db.models.document import Document
from adapters.db.models.person import Person
from adapters.db.models.product import Product
# Lazy import to avoid circular dependency
# from adapters.api.v1.schemas import (
#     BusinessCreateRequest, BusinessUpdateRequest, BusinessResponse,
#     BusinessListResponse, BusinessSummaryResponse, PaginationInfo
# )
from app.core.responses import format_datetime_fields, ApiError
from app.services.system_settings_service import get_wallet_settings

logger = logging.getLogger(__name__)


def _normalize_invoice_warehouse_release_mode(value) -> str:
    if value is None:
        return "draft"
    s = str(value).strip().lower()
    if s in ("none", "off", "no", "disabled"):
        return "none"
    if s in ("posted", "final", "confirmed"):
        return "posted"
    if s == "draft":
        return "draft"
    return "draft"


def ensure_wallet_currency_in_business(db: Session, business_id: int) -> bool:
    """
    بررسی و اضافه کردن ارز کیف پول به لیست ارزهای کسب و کار در صورت عدم وجود
    
    Args:
        db: Database session
        business_id: شناسه کسب‌وکار
        
    Returns:
        True اگر ارز اضافه شد، False اگر قبلاً وجود داشت
    """
    from app.core.responses import ApiError
    
    # دریافت کسب و کار
    business = db.query(Business).filter(Business.id == business_id).first()
    if not business:
        raise ApiError("BUSINESS_NOT_FOUND", "کسب‌وکار یافت نشد", http_status=404)
    
    # دریافت ارز کیف پول
    wallet_settings = get_wallet_settings(db)
    wallet_currency_id = wallet_settings.get("wallet_base_currency_id")
    
    if not wallet_currency_id:
        # اگر ارز کیف پول تنظیم نشده باشد، کاری نمی‌کنیم
        logger.warning("wallet_currency_not_set", business_id=business_id)
        return False
    
    wallet_currency_id = int(wallet_currency_id)
    
    # بررسی اینکه آیا ارز کیف پول همان ارز پیشفرض کسب و کار است
    if business.default_currency_id == wallet_currency_id:
        # ارز پیشفرض به صورت خودکار در لیست ارزها قرار دارد
        return False
    
    # بررسی اینکه آیا ارز کیف پول در لیست ارزهای جانبی وجود دارد
    existing = (
        db.query(BusinessCurrency)
        .filter(
            and_(
                BusinessCurrency.business_id == business_id,
                BusinessCurrency.currency_id == wallet_currency_id
            )
        )
        .first()
    )
    
    if existing:
        # ارز قبلاً اضافه شده است
        return False
    
    # بررسی وجود ارز در سیستم
    currency = db.query(Currency).filter(Currency.id == wallet_currency_id).first()
    if not currency:
        logger.warning("wallet_currency_not_found", business_id=business_id, currency_id=wallet_currency_id)
        return False
    
    # اضافه کردن ارز کیف پول به لیست ارزهای جانبی
    business_currency = BusinessCurrency(
        business_id=business_id,
        currency_id=wallet_currency_id
    )
    db.add(business_currency)
    db.flush()
    
    # Invalidate cache
    from app.core.cache import get_cache
    cache = get_cache()
    if cache.enabled:
        cache.delete(f"business_currencies:{business_id}")
    
    logger.info(
        "wallet_currency_added_to_business",
        business_id=business_id,
        currency_id=wallet_currency_id,
        currency_code=currency.code
    )
    
    return True


def check_business_creation_permission(db: Session, user_id: int) -> tuple[bool, str | None]:
    """
    بررسی اینکه آیا کاربر می‌تواند کسب و کار ایجاد کند یا نه
    
    Args:
        db: Database session
        user_id: شناسه کاربر
        
    Returns:
        Tuple[bool, str | None]:
        - (True, None): اجازه ایجاد دارد
        - (False, "پیام خطا"): اجازه ایجاد ندارد
    """
    from app.services.system_settings_service import get_business_creation_verification_requirement
    from adapters.db.models.user import User
    
    requirement = get_business_creation_verification_requirement(db)
    
    # بدون محدودیت
    if requirement == "none":
        return True, None
    
    # دریافت اطلاعات کاربر
    user = db.get(User, user_id)
    if not user:
        return False, "کاربر یافت نشد"
    
    email_verified = getattr(user, "email_verified", False)
    mobile_verified = getattr(user, "mobile_verified", False)
    
    # بررسی بر اساس requirement
    if requirement == "email_only":
        if not email_verified:
            return False, "برای ایجاد کسب و کار، شما باید ایمیل خود را تایید کنید. لطفاً به بخش 'تایید شماره موبایل و ایمیل' در تنظیمات حساب کاربری بروید."
        return True, None
    
    elif requirement == "mobile_only":
        if not mobile_verified:
            return False, "برای ایجاد کسب و کار، شما باید شماره موبایل خود را تایید کنید. لطفاً به بخش 'تایید شماره موبایل و ایمیل' در تنظیمات حساب کاربری بروید."
        return True, None
    
    elif requirement == "both":
        if not email_verified or not mobile_verified:
            missing = []
            if not email_verified:
                missing.append("ایمیل")
            if not mobile_verified:
                missing.append("شماره موبایل")
            return False, f"برای ایجاد کسب و کار، شما باید {' و '.join(missing)} خود را تایید کنید. لطفاً به بخش 'تایید شماره موبایل و ایمیل' در تنظیمات حساب کاربری بروید."
        return True, None
    
    elif requirement == "either":
        if not email_verified and not mobile_verified:
            return False, "برای ایجاد کسب و کار، شما باید حداقل ایمیل یا شماره موبایل خود را تایید کنید. لطفاً به بخش 'تایید شماره موبایل و ایمیل' در تنظیمات حساب کاربری بروید."
        return True, None
    
    # حالت پیش‌فرض: بدون محدودیت
    return True, None


def create_business(db: Session, business_data, owner_id: int) -> Dict[str, Any]:
    """ایجاد کسب و کار جدید"""
    # Lazy import to avoid circular dependency
    from adapters.api.v1.schemas import BusinessCreateRequest
    from app.core.responses import ApiError
    
    # بررسی دسترسی ایجاد کسب و کار
    can_create, error_message = check_business_creation_permission(db, owner_id)
    if not can_create:
        raise ApiError(
            "BUSINESS_CREATION_NOT_ALLOWED",
            error_message or "شما اجازه ایجاد کسب و کار را ندارید",
            http_status=403
        )
    
    business_repo = BusinessRepository(db)
    fiscal_repo = FiscalYearRepository(db)
    
    # تبدیل enum values به مقادیر فارسی
    # business_data.business_type و business_data.business_field قبلاً مقادیر فارسی هستند
    business_type_enum = business_data.business_type
    business_field_enum = business_data.business_field
    
    # ذخیره در دیتابیس
    created_business = business_repo.create_business(
        name=business_data.name,
        business_type=business_type_enum,
        business_field=business_field_enum,
        owner_id=owner_id,
        default_currency_id=getattr(business_data, "default_currency_id", None),
        address=business_data.address,
        phone=business_data.phone,
        mobile=business_data.mobile,
        national_id=business_data.national_id,
        registration_number=business_data.registration_number,
        economic_id=business_data.economic_id,
        country=business_data.country,
        province=business_data.province,
        city=business_data.city,
        postal_code=business_data.postal_code
    )
    
    # ایجاد سال‌های مالی اولیه (در صورت ارسال)
    if getattr(business_data, "fiscal_years", None):
        # فقط یک سال با is_last=True نگه داریم (آخرین مورد True باشد)
        last_true_index = None
        for idx, fy in enumerate(business_data.fiscal_years or []):
            if fy.is_last:
                last_true_index = idx
        for idx, fy in enumerate(business_data.fiscal_years or []):
            fiscal_repo.create_fiscal_year(
                business_id=created_business.id,
                title=fy.title,
                start_date=fy.start_date,
                end_date=fy.end_date,
                is_last=(idx == last_true_index) if last_true_index is not None else (idx == len(business_data.fiscal_years) - 1)
            )

    # مدیریت ارزها
    currency_ids: list[int] = []
    if getattr(business_data, "currency_ids", None):
        currency_ids = list(dict.fromkeys(business_data.currency_ids))  # unique
    default_currency_id = getattr(business_data, "default_currency_id", None)
    if default_currency_id:
        if default_currency_id not in currency_ids:
            currency_ids.insert(0, default_currency_id)

    # اعتبارسنجی وجود ارزها
    if currency_ids:
        existing_ids = [cid for (cid,) in db.query(Currency.id).filter(Currency.id.in_(currency_ids)).all()]
        if set(existing_ids) != set(currency_ids):
            missing = set(currency_ids) - set(existing_ids)
            raise ValueError(f"Invalid currency ids: {sorted(list(missing))}")

        # درج ارتباطات در business_currencies
        for cid in currency_ids:
            bc = BusinessCurrency(business_id=created_business.id, currency_id=cid)
            db.add(bc)
        db.commit()

    # بررسی و اضافه کردن ارز کیف پول در صورت نیاز
    # اگر ارز پیشفرض کسب و کار با ارز کیف پول متفاوت باشد، ارز کیف پول را به ارزهای جانبی اضافه می‌کنیم
    try:
        ensure_wallet_currency_in_business(db, created_business.id)
    except Exception as e:
        # در صورت خطا، لاگ می‌کنیم اما ایجاد کسب‌وکار را متوقف نمی‌کنیم
        logger.warning("failed_to_add_wallet_currency", business_id=created_business.id, error=str(e))

    db.refresh(created_business)

    # اعمال خودکار سیاست‌های پیش‌فرض درآمدزایی اسناد
    try:
        # Lazy import to avoid circular imports (document_monetization_service <-> wallet_service <-> business_service)
        from app.services.document_monetization_service import apply_default_policies_to_business
        apply_default_policies_to_business(db, created_business.id, user_id=owner_id)
    except Exception as e:
        # در صورت خطا، لاگ می‌کنیم اما ایجاد کسب‌وکار را متوقف نمی‌کنیم
        import structlog
        logger = structlog.get_logger()
        logger.warning("failed_to_apply_default_policies", business_id=created_business.id, error=str(e))

    # تبدیل به response format
    return _business_to_dict(created_business)


def get_business_by_id(db: Session, business_id: int, owner_id: int) -> Optional[Dict[str, Any]]:
    """دریافت کسب و کار بر اساس شناسه"""
    business_repo = BusinessRepository(db)
    business = business_repo.get_by_id(business_id)
    
    if not business or business.owner_id != owner_id:
        return None
    
    return _business_to_dict(business)


def get_businesses_by_owner(db: Session, owner_id: int, query_info: Dict[str, Any]) -> Dict[str, Any]:
    """دریافت لیست کسب و کارهای یک مالک"""
    business_repo = BusinessRepository(db)
    
    # دریافت کسب و کارها
    businesses = business_repo.get_by_owner_id(owner_id)
    
    # اعمال فیلترها
    if query_info.get('search'):
        search_term = query_info['search']
        businesses = [b for b in businesses if search_term.lower() in b.name.lower()]
    
    # اعمال مرتب‌سازی
    sort_by = query_info.get('sort_by', 'created_at')
    sort_desc = query_info.get('sort_desc', True)
    
    if sort_by == 'name':
        businesses.sort(key=lambda x: x.name, reverse=sort_desc)
    elif sort_by == 'business_type':
        businesses.sort(key=lambda x: x.business_type.value, reverse=sort_desc)
    elif sort_by == 'created_at':
        businesses.sort(key=lambda x: x.created_at, reverse=sort_desc)
    
    # صفحه‌بندی
    total = len(businesses)
    skip = query_info.get('skip', 0)
    take = query_info.get('take', 10)
    
    start_idx = skip
    end_idx = skip + take
    paginated_businesses = businesses[start_idx:end_idx]
    
    # محاسبه اطلاعات صفحه‌بندی
    total_pages = (total + take - 1) // take
    current_page = (skip // take) + 1
    
    # Lazy import to avoid circular dependency
    from adapters.api.v1.schemas import PaginationInfo
    pagination = PaginationInfo(
        total=total,
        page=current_page,
        per_page=take,
        total_pages=total_pages,
        has_next=current_page < total_pages,
        has_prev=current_page > 1
    )
    
    # تبدیل به response format
    items = [_business_to_dict(business) for business in paginated_businesses]
    
    return {
        "items": items,
        "pagination": pagination.dict(),
        "query_info": query_info
    }


def get_user_businesses(db: Session, user_id: int, query_info: Dict[str, Any], include_deleted_for_owner: bool = True) -> Dict[str, Any]:
    """
    دریافت لیست کسب و کارهای کاربر (مالک + عضو)
    
    قوانین نمایش:
    - برای مالک: کسب و کارهای حذف شده را نشان می‌دهد (اگر auto_delete_at نگذشته باشد) - قابل کنترل با include_deleted_for_owner
    - برای سایر کاربران: کسب و کارهای حذف شده را نشان نمی‌دهد
    
    Args:
        db: Session دیتابیس
        user_id: شناسه کاربر
        query_info: اطلاعات جستجو و صفحه‌بندی
        include_deleted_for_owner: آیا کسب‌وکارهای حذف‌شده برای مالک نمایش داده شوند؟ (پیش‌فرض True)
    """
    business_repo = BusinessRepository(db)
    permission_repo = BusinessPermissionRepository(db)
    
    # دریافت کسب و کارهای مالک (شامل حذف شده‌ها که هنوز مهلت دارند - بسته به پارامتر)
    owned_businesses = business_repo.get_by_owner_id(user_id, include_deleted=include_deleted_for_owner)
    
    # دریافت کسب و کارهای عضو (فقط غیرحذف شده‌ها)
    member_permissions = permission_repo.get_user_member_businesses(user_id)
    member_business_ids = [perm.business_id for perm in member_permissions]
    member_businesses = []
    for business_id in member_business_ids:
        business = business_repo.get_by_id(business_id)
        if business:
            # فیلتر کردن حذف شده‌ها برای اعضا
            if business.deleted_at is None:
                member_businesses.append(business)
            # یا اگر حذف شده اما auto_delete_at نگذشته (فقط برای مالک - که قبلاً در owned_businesses است)
    
    # ترکیب لیست‌ها
    all_businesses = []
    
    # اضافه کردن کسب و کارهای مالک با نقش owner
    for business in owned_businesses:
        business_dict = _business_to_dict(business)
        business_dict['is_owner'] = True
        business_dict['role'] = 'مالک'
        business_dict['permissions'] = {}
        all_businesses.append(business_dict)
    
    # اضافه کردن کسب و کارهای عضو با نقش member
    for business in member_businesses:
        # اگر قبلاً به عنوان مالک اضافه شده، نادیده بگیر
        if business.id not in [b['id'] for b in all_businesses]:
            business_dict = _business_to_dict(business)
            business_dict['is_owner'] = False
            business_dict['role'] = 'عضو'
            # دریافت دسترسی‌های کاربر برای این کسب و کار
            permission_obj = permission_repo.get_by_user_and_business(user_id, business.id)
            if permission_obj and permission_obj.business_permissions:
                perms = permission_obj.business_permissions
                # Normalize to dict to avoid legacy list format
                if isinstance(perms, dict):
                    business_dict['permissions'] = perms
                elif isinstance(perms, list):
                    try:
                        if all(isinstance(item, list) and len(item) == 2 for item in perms):
                            business_dict['permissions'] = {k: v for k, v in perms if isinstance(k, str)}
                        elif all(isinstance(item, dict) for item in perms):
                            merged = {}
                            for it in perms:
                                merged.update({k: v for k, v in it.items()})
                            business_dict['permissions'] = merged
                        else:
                            business_dict['permissions'] = {}
                    except Exception:
                        business_dict['permissions'] = {}
                else:
                    business_dict['permissions'] = {}
            else:
                business_dict['permissions'] = {}
            all_businesses.append(business_dict)
    
    # اعمال فیلترها
    if query_info.get('search'):
        search_term = query_info['search']
        all_businesses = [b for b in all_businesses if search_term.lower() in b['name'].lower()]
    
    # اعمال مرتب‌سازی
    sort_by = query_info.get('sort_by', 'created_at')
    sort_desc = query_info.get('sort_desc', True)
    
    if sort_by == 'name':
        all_businesses.sort(key=lambda x: x['name'], reverse=sort_desc)
    elif sort_by == 'business_type':
        all_businesses.sort(key=lambda x: x['business_type'], reverse=sort_desc)
    elif sort_by == 'created_at':
        all_businesses.sort(key=lambda x: x['created_at'], reverse=sort_desc)
    
    # صفحه‌بندی
    total = len(all_businesses)
    skip = query_info.get('skip', 0)
    take = query_info.get('take', 10)
    
    start_idx = skip
    end_idx = skip + take
    paginated_businesses = all_businesses[start_idx:end_idx]
    
    # محاسبه اطلاعات صفحه‌بندی
    total_pages = (total + take - 1) // take
    current_page = (skip // take) + 1
    
    # Lazy import to avoid circular dependency
    from adapters.api.v1.schemas import PaginationInfo
    pagination = PaginationInfo(
        total=total,
        page=current_page,
        per_page=take,
        total_pages=total_pages,
        has_next=current_page < total_pages,
        has_prev=current_page > 1
    )
    
    return {
        "items": paginated_businesses,
        "pagination": pagination.dict(),
        "query_info": query_info
    }


def update_business(db: Session, business_id: int, business_data, owner_id: int) -> Optional[Dict[str, Any]]:
    """ویرایش کسب و کار"""
    # Lazy import to avoid circular dependency
    from adapters.api.v1.schemas import BusinessUpdateRequest
    from app.core.responses import ApiError
    from adapters.db.models.currency import Currency, BusinessCurrency
    
    business_repo = BusinessRepository(db)
    business = business_repo.get_by_id(business_id)
    
    if not business or business.owner_id != owner_id:
        return None
    
    # به‌روزرسانی فیلدها
    update_data = business_data.dict(exclude_unset=True)
    
    # مدیریت ارز پیش‌فرض
    if "default_currency_id" in update_data:
        new_default_currency_id = update_data.pop("default_currency_id")
        
        # بررسی اینکه آیا کسب‌وکار قبلاً ارز پیش‌فرض تنظیم کرده است
        if business.default_currency_id is not None:
            raise ApiError(
                "CANNOT_CHANGE_DEFAULT_CURRENCY",
                "کسب‌وکار شما قبلاً ارز پیش‌فرض تنظیم کرده است و امکان تغییر آن وجود ندارد",
                http_status=400
            )
        
        # بررسی وجود ارز
        if new_default_currency_id is not None:
            currency = db.query(Currency).filter(Currency.id == int(new_default_currency_id)).first()
            if not currency:
                raise ApiError("CURRENCY_NOT_FOUND", "ارز یافت نشد", http_status=404)
            
            # تنظیم ارز پیش‌فرض
            business.default_currency_id = int(new_default_currency_id)
            
            # اضافه کردن به business_currencies اگر وجود نداشته باشد
            existing_bc = (
                db.query(BusinessCurrency)
                .filter(
                    and_(
                        BusinessCurrency.business_id == business_id,
                        BusinessCurrency.currency_id == int(new_default_currency_id)
                    )
                )
                .first()
            )
            
            if not existing_bc:
                bc = BusinessCurrency(business_id=business_id, currency_id=int(new_default_currency_id))
                db.add(bc)
                db.flush()
    
    # به‌روزرسانی سایر فیلدها
    for field, value in update_data.items():
        setattr(business, field, value)
    
    # ذخیره تغییرات
    updated_business = business_repo.update(business)
    
    return _business_to_dict(updated_business)


def check_currency_usage_in_documents(db: Session, business_id: int, currency_id: int) -> int:
    """
    بررسی تعداد اسناد استفاده‌کننده از یک ارز در کسب‌وکار
    
    Args:
        db: Database session
        business_id: شناسه کسب‌وکار
        currency_id: شناسه ارز
        
    Returns:
        تعداد اسناد استفاده‌کننده از این ارز
    """
    from sqlalchemy import func
    
    count = (
        db.query(func.count(Document.id))
        .filter(
            and_(
                Document.business_id == business_id,
                Document.currency_id == currency_id
            )
        )
        .scalar()
    )
    return count or 0


def add_business_currency(db: Session, business_id: int, currency_id: int, owner_id: int) -> Dict[str, Any]:
    """
    اضافه کردن ارز جانبی به کسب‌وکار
    
    Args:
        db: Database session
        business_id: شناسه کسب‌وکار
        currency_id: شناسه ارز
        owner_id: شناسه مالک کسب‌وکار
        
    Returns:
        اطلاعات ارز اضافه شده
        
    Raises:
        ApiError: در صورت خطا
    """
    from app.core.responses import ApiError
    
    # بررسی وجود کسب‌وکار و مالکیت
    business = db.query(Business).filter(Business.id == business_id).first()
    if not business:
        raise ApiError("NOT_FOUND", "کسب‌وکار یافت نشد", http_status=404)
    
    if business.owner_id != owner_id:
        raise ApiError("FORBIDDEN", "شما دسترسی به این کسب‌وکار را ندارید", http_status=403)
    
    # بررسی وجود ارز
    currency = db.query(Currency).filter(Currency.id == currency_id).first()
    if not currency:
        raise ApiError("NOT_FOUND", "ارز یافت نشد", http_status=404)
    
    # بررسی اینکه ارز پیش‌فرض نیست
    if business.default_currency_id == currency_id:
        raise ApiError(
            "CANNOT_ADD_DEFAULT_AS_SECONDARY",
            "ارز پیش‌فرض به صورت خودکار در لیست ارزها قرار دارد",
            http_status=400
        )
    
    # بررسی تکراری نبودن
    existing = (
        db.query(BusinessCurrency)
        .filter(
            and_(
                BusinessCurrency.business_id == business_id,
                BusinessCurrency.currency_id == currency_id
            )
        )
        .first()
    )
    
    if existing:
        raise ApiError(
            "CURRENCY_ALREADY_ADDED",
            "این ارز قبلاً به کسب‌وکار اضافه شده است",
            http_status=400
        )
    
    # اضافه کردن ارز
    business_currency = BusinessCurrency(
        business_id=business_id,
        currency_id=currency_id
    )
    db.add(business_currency)
    db.commit()
    db.refresh(business_currency)
    
    # Invalidate cache
    from app.core.cache import get_cache
    cache = get_cache()
    if cache.enabled:
        cache.delete(f"business_currencies:{business_id}")
    
    return {
        "id": currency.id,
        "name": currency.name,
        "title": currency.title,
        "symbol": currency.symbol,
        "code": currency.code,
        "is_default": False,
    }


def remove_business_currency(db: Session, business_id: int, currency_id: int, owner_id: int) -> None:
    """
    حذف ارز جانبی از کسب‌وکار
    
    Args:
        db: Database session
        business_id: شناسه کسب‌وکار
        currency_id: شناسه ارز
        owner_id: شناسه مالک کسب‌وکار
        
    Raises:
        ApiError: در صورت خطا
    """
    from app.core.responses import ApiError
    
    # بررسی وجود کسب‌وکار و مالکیت
    business = db.query(Business).filter(Business.id == business_id).first()
    if not business:
        raise ApiError("NOT_FOUND", "کسب‌وکار یافت نشد", http_status=404)
    
    if business.owner_id != owner_id:
        raise ApiError("FORBIDDEN", "شما دسترسی به این کسب‌وکار را ندارید", http_status=403)
    
    # بررسی اینکه ارز پیش‌فرض نیست
    if business.default_currency_id == currency_id:
        raise ApiError(
            "CANNOT_DELETE_DEFAULT_CURRENCY",
            "ارز پیش‌فرض قابل حذف نیست",
            http_status=400
        )
    
    # بررسی استفاده در اسناد
    document_count = check_currency_usage_in_documents(db, business_id, currency_id)
    if document_count > 0:
        raise ApiError(
            "CURRENCY_IN_USE",
            f"این ارز در {document_count} سند حسابداری استفاده شده و قابل حذف نیست",
            http_status=400
        )
    
    # حذف ارز
    business_currency = (
        db.query(BusinessCurrency)
        .filter(
            and_(
                BusinessCurrency.business_id == business_id,
                BusinessCurrency.currency_id == currency_id
            )
        )
        .first()
    )
    
    if not business_currency:
        raise ApiError("NOT_FOUND", "این ارز در لیست ارزهای کسب‌وکار یافت نشد", http_status=404)
    
    db.delete(business_currency)
    db.commit()
    
    # Invalidate cache
    from app.core.cache import get_cache
    cache = get_cache()
    if cache.enabled:
        cache.delete(f"business_currencies:{business_id}")


def delete_business(db: Session, business_id: int, owner_id: int) -> bool:
    """حذف کسب و کار (قدیمی - برای سازگاری با backward compatibility)"""
    return delete_business_soft(db, business_id, owner_id, None, owner_id) is not None


def _check_deletion_restrictions(db: Session, business_id: int) -> Dict[str, Any]:
    """بررسی محدودیت‌های حذف کسب و کار"""
    restrictions = {
        "can_delete": True,
        "has_finalized_invoices": False,
        "finalized_invoices_count": 0,
        "has_tax_workspace_invoices": False,
        "tax_workspace_invoices_count": 0,
        "has_locked_documents": False,
        "locked_documents_count": 0,
    }
    
    # بررسی فاکتورهای نهایی شده
    finalized_docs = db.query(Document).filter(
        Document.business_id == business_id,
        Document.document_type.in_(['invoice', 'invoice_return', 'proforma'])
    ).all()
    
    finalized_count = 0
    for doc in finalized_docs:
        extra_info = doc.extra_info or {}
        if isinstance(extra_info, dict):
            tax_status = extra_info.get("tax_status", "")
            if isinstance(tax_status, str) and tax_status.strip() == "finalized":
                finalized_count += 1
    
    restrictions["finalized_invoices_count"] = finalized_count
    restrictions["has_finalized_invoices"] = finalized_count > 0
    
    # بررسی فاکتورهای در کارپوشه مودیان
    tax_workspace_count = 0
    for doc in finalized_docs:
        extra_info = doc.extra_info or {}
        if isinstance(extra_info, dict):
            tax_workspace = extra_info.get("tax_workspace", False)
            if tax_workspace:
                tax_workspace_count += 1
    
    restrictions["tax_workspace_invoices_count"] = tax_workspace_count
    restrictions["has_tax_workspace_invoices"] = tax_workspace_count > 0
    
    # بررسی اسناد قفل شده
    locked_count = 0
    all_docs = db.query(Document).filter(Document.business_id == business_id).all()
    for doc in all_docs:
        extra_info = doc.extra_info or {}
        developer_settings = doc.developer_settings or {}
        if isinstance(extra_info, dict):
            if extra_info.get("locked") or extra_info.get("is_locked"):
                locked_count += 1
        elif isinstance(developer_settings, dict):
            if developer_settings.get("locked") or developer_settings.get("is_locked"):
                locked_count += 1
    
    restrictions["locked_documents_count"] = locked_count
    restrictions["has_locked_documents"] = locked_count > 0
    
    # بررسی نهایی
    restrictions["can_delete"] = (
        not restrictions["has_finalized_invoices"] and
        not restrictions["has_tax_workspace_invoices"] and
        not restrictions["has_locked_documents"]
    )
    
    return restrictions


def _format_restriction_error(restrictions: Dict[str, Any]) -> str:
    """فرمت کردن پیام خطای محدودیت‌ها"""
    errors = []
    if restrictions["has_finalized_invoices"]:
        errors.append(f"{restrictions['finalized_invoices_count']} فاکتور نهایی شده وجود دارد")
    if restrictions["has_tax_workspace_invoices"]:
        errors.append(f"{restrictions['tax_workspace_invoices_count']} فاکتور در کارپوشه مودیان وجود دارد")
    if restrictions["has_locked_documents"]:
        errors.append(f"{restrictions['locked_documents_count']} سند قفل شده وجود دارد")
    
    return "نمی‌توان کسب و کار را حذف کرد: " + "، ".join(errors)


def get_business_delete_info(db: Session, business_id: int, owner_id: int) -> Dict[str, Any]:
    """دریافت اطلاعات مرتبط با حذف کسب و کار"""
    business = db.query(Business).filter(Business.id == business_id).first()
    if not business:
        raise ApiError("BUSINESS_NOT_FOUND", "کسب و کار یافت نشد", http_status=404)
    
    # بررسی مالکیت
    if business.owner_id != owner_id:
        raise ApiError("FORBIDDEN", "فقط مالک کسب و کار می‌تواند آن را حذف کند", http_status=403)
    
    # بررسی محدودیت‌ها
    restrictions = _check_deletion_restrictions(db, business_id)
    
    # آمار کلی
    total_documents = db.query(Document).filter(Document.business_id == business_id).count()
    total_persons = db.query(Person).filter(Person.business_id == business_id).count()
    total_products = db.query(Product).filter(Product.business_id == business_id).count()
    
    return {
        "business": {
            "id": business.id,
            "name": business.name,
        },
        "restrictions": restrictions,
        "statistics": {
            "total_documents": total_documents,
            "total_persons": total_persons,
            "total_products": total_products,
        }
    }


def delete_business_soft(
    db: Session,
    business_id: int,
    owner_id: int,
    deletion_reason: str | None = None,
    requested_by: int | None = None
) -> Dict[str, Any] | None:
    """
    حذف نرم کسب و کار با بررسی‌های امنیتی و ایجاد بکاپ خودکار
    """
    business_repo = BusinessRepository(db)
    business = business_repo.get_by_id(business_id)
    
    if not business or business.owner_id != owner_id:
        raise ApiError("BUSINESS_NOT_FOUND", "کسب و کار یافت نشد", http_status=404)
    
    # بررسی اینکه قبلاً حذف نشده باشد
    if business.deleted_at is not None:
        raise ApiError("ALREADY_DELETED", "کسب و کار قبلاً حذف شده است", http_status=400)
    
    # بررسی محدودیت‌ها
    restrictions = _check_deletion_restrictions(db, business_id)
    if not restrictions["can_delete"]:
        error_msg = _format_restriction_error(restrictions)
        raise ApiError("CANNOT_DELETE_BUSINESS", error_msg, http_status=409)
    
    # ایجاد بکاپ خودکار قبل از حذف
    backup_result = None
    try:
        from adapters.api.v1.business_backups import _perform_backup
        
        # ساخت AuthContext موقت برای بکاپ
        class TempAuthContext:
            def get_user_id(self):
                return owner_id
        
        temp_ctx = TempAuthContext()
        backup_data = _perform_backup(db, temp_ctx, business_id)
        
        # ذخیره بکاپ
        from app.services.file_storage_service import FileStorageService
        storage = FileStorageService(db)
        import anyio
        from fastapi import UploadFile
        import io
        
        async def _upload_backup():
            filename = f"business_{business_id}_auto_backup_before_deletion_{datetime.utcnow().strftime('%Y%m%dT%H%M%SZ')}.hbx"
            faux_upload = UploadFile(
                filename=filename,
                file=io.BytesIO(backup_data["zip_bytes"])
            )
            saved = await storage.upload_file(
                faux_upload,
                user_id=owner_id,
                module_context="business_auto_backup",
                developer_data={
                    "business_id": business_id,
                    "backup_type": "auto_before_deletion",
                    "schema_version": backup_data["metadata"]["schema_version"],
                },
                is_temporary=False,
                expires_in_days=3650,  # 10 سال
                business_id=business_id,
                check_storage_limit=False,  # بکاپ خودکار محدودیت ندارد
            )
            return saved
        
        backup_result = anyio.run(_upload_backup)
        logger.info(f"Auto backup created for business {business_id}: {backup_result.get('id')}")
    except Exception as e:
        logger.error(f"Failed to create auto backup for business {business_id}: {e}")
        # اگر بکاپ ناموفق بود، حذف را ادامه می‌دهیم اما هشدار می‌دهیم
    
    # انجام Soft Delete
    now = datetime.utcnow()
    business.deleted_at = now
    business.deletion_requested_at = now
    business.deletion_requested_by = requested_by or owner_id
    business.deletion_reason = deletion_reason
    business.auto_delete_at = now + timedelta(days=30)  # 30 روز بعد
    
    db.commit()
    db.refresh(business)
    
    # لاگ عملیات
    logger.info(
        f"Business {business_id} soft deleted by user {owner_id}",
        extra={
            "business_id": business_id,
            "deleted_by": owner_id,
            "deleted_at": now.isoformat(),
            "auto_delete_at": business.auto_delete_at.isoformat(),
            "backup_created": backup_result is not None,
        }
    )
    
    return {
        "business_id": business_id,
        "deleted_at": business.deleted_at.isoformat(),
        "auto_delete_at": business.auto_delete_at.isoformat(),
        "restore_deadline_days": 30,
        "backup_created": backup_result is not None,
        "backup_id": backup_result.get("id") if backup_result else None,
    }


def restore_business(db: Session, business_id: int, owner_id: int) -> Dict[str, Any]:
    """بازیابی کسب و کار حذف شده (فقط در 30 روز اول)"""
    business = db.query(Business).filter(Business.id == business_id).first()
    
    if not business:
        raise ApiError("BUSINESS_NOT_FOUND", "کسب و کار یافت نشد", http_status=404)
    
    # بررسی مالکیت
    if business.owner_id != owner_id:
        raise ApiError("FORBIDDEN", "فقط مالک می‌تواند کسب و کار را بازیابی کند", http_status=403)
    
    # بررسی اینکه حذف شده باشد
    if business.deleted_at is None:
        raise ApiError("NOT_DELETED", "کسب و کار حذف نشده است", http_status=400)
    
    # بررسی مهلت بازیابی
    if business.auto_delete_at and datetime.utcnow() > business.auto_delete_at:
        raise ApiError(
            "RESTORE_EXPIRED",
            "مهلت بازیابی کسب و کار به پایان رسیده است. امکان بازیابی وجود ندارد.",
            http_status=410
        )
    
    # بازیابی
    business.deleted_at = None
    business.deletion_requested_at = None
    business.deletion_requested_by = None
    business.deletion_reason = None
    business.auto_delete_at = None
    
    db.commit()
    db.refresh(business)
    
    logger.info(f"Business {business_id} restored by user {owner_id}")
    
    return {
        "business_id": business_id,
        "restored_at": datetime.utcnow().isoformat()
    }


def get_business_summary(db: Session, owner_id: int) -> Dict[str, Any]:
    """دریافت خلاصه آمار کسب و کارها"""
    business_repo = BusinessRepository(db)
    businesses = business_repo.get_by_owner_id(owner_id)
    
    # شمارش بر اساس نوع
    by_type = {}
    for business_type in BusinessType:
        by_type[business_type.value] = len([b for b in businesses if b.business_type == business_type])
    
    # شمارش بر اساس زمینه فعالیت
    by_field = {}
    for business_field in BusinessField:
        by_field[business_field.value] = len([b for b in businesses if b.business_field == business_field])
    
    return {
        "total_businesses": len(businesses),
        "by_type": by_type,
        "by_field": by_field
    }


def get_business_print_settings(db: Session, business_id: int) -> Dict[str, Any]:
    """
    دریافت تنظیمات چاپ فاکتورهای یک کسب‌وکار.

    - رکوردی با document_type = 'all' به عنوان تنظیمات عمومی (پیش‌فرض) استفاده می‌شود.
    - در صورت وجود رکورد برای نوع سند خاص، همان برای آن نوع استفاده می‌شود.
    - اگر هیچ رکوردی وجود نداشته باشد، مقادیر پیش‌فرض (همه روشن، بدون متن پاورقی) برگردانده می‌شود.
    """
    rows = (
        db.query(BusinessPrintSettings)
        .filter(BusinessPrintSettings.business_id == business_id)
        .all()
    )

    def _row_to_dict(row: BusinessPrintSettings) -> Dict[str, Any]:
        return {
            "document_type": row.document_type,
            "show_logo": bool(getattr(row, "show_logo", True)),
            "show_stamp": bool(getattr(row, "show_stamp", True)),
            "show_payments": bool(getattr(row, "show_payments", True)),
            "show_installment_plan": bool(getattr(row, "show_installment_plan", True)),
            "footer_note": getattr(row, "footer_note", None),
        }

    default_settings: Dict[str, Any] = {
        "document_type": "all",
        "show_logo": True,
        "show_stamp": True,
        "show_payments": True,
        "show_installment_plan": True,
        "footer_note": None,
    }
    per_type: Dict[str, Any] = {}

    for row in rows:
        data = _row_to_dict(row)
        if row.document_type == "all":
            default_settings = data
        else:
            per_type[row.document_type] = data

    return {
        "default": default_settings,
        "per_type": per_type,
    }


def update_business_print_settings(
    db: Session,
    business_id: int,
    settings_payload: Dict[str, Any],
) -> Dict[str, Any]:
    """
    به‌روزرسانی تنظیمات چاپ فاکتورهای یک کسب‌وکار.

    ورودی انتظار دارد ساختاری شبیه:
    {
      "default": { ... },
      "per_type": {
        "invoice_sales": { ... },
        "invoice_purchase": { ... },
        ...
      }
    }
    """
    default_data = (settings_payload or {}).get("default") or {}
    per_type_data: Dict[str, Any] = (settings_payload or {}).get("per_type") or {}

    # کمک‌کننده برای گرفتن مقدار بولین با پیش‌فرض
    def _get_bool(d: Dict[str, Any], key: str, default: bool) -> bool:
        val = d.get(key)
        if isinstance(val, bool):
            return val
        if isinstance(val, (int, float)):
            return bool(val)
        if isinstance(val, str):
            s = val.strip().lower()
            if s in {"true", "1", "yes", "on"}:
                return True
            if s in {"false", "0", "no", "off"}:
                return False
        return default

    # ابتدا رکورد تنظیمات عمومی (all) را به‌روزرسانی یا ایجاد می‌کنیم
    default_row = (
        db.query(BusinessPrintSettings)
        .filter(
            BusinessPrintSettings.business_id == business_id,
            BusinessPrintSettings.document_type == "all",
        )
        .first()
    )
    if default_data:
        if not default_row:
            default_row = BusinessPrintSettings(
                business_id=business_id,
                document_type="all",
            )
            db.add(default_row)
        default_row.show_logo = _get_bool(default_data, "show_logo", True)
        default_row.show_stamp = _get_bool(default_data, "show_stamp", True)
        default_row.show_payments = _get_bool(default_data, "show_payments", True)
        default_row.show_installment_plan = _get_bool(
            default_data,
            "show_installment_plan",
            True,
        )
        default_row.footer_note = (
            (default_data.get("footer_note") or None)
            if isinstance(default_data.get("footer_note"), str)
            else default_data.get("footer_note")
        )

    # سپس تنظیمات اختصاصی هر نوع سند را به‌روزرسانی / ایجاد می‌کنیم
    # document_type فقط برای انواعی نگهداری می‌شود که در per_type ارسال شده‌اند.
    existing_rows = (
        db.query(BusinessPrintSettings)
        .filter(
            BusinessPrintSettings.business_id == business_id,
            BusinessPrintSettings.document_type != "all",
        )
        .all()
    )
    existing_map: Dict[str, BusinessPrintSettings] = {
        r.document_type: r for r in existing_rows
    }

    # انواعی که باید نگه داشته شوند
    keep_types = set()

    for doc_type, cfg in per_type_data.items():
        if not isinstance(cfg, dict):
            continue
        doc_type_str = str(doc_type).strip()
        if not doc_type_str:
            continue
        keep_types.add(doc_type_str)
        row = existing_map.get(doc_type_str)
        if not row:
            row = BusinessPrintSettings(
                business_id=business_id,
                document_type=doc_type_str,
            )
            db.add(row)
        row.show_logo = _get_bool(cfg, "show_logo", True)
        row.show_stamp = _get_bool(cfg, "show_stamp", True)
        row.show_payments = _get_bool(cfg, "show_payments", True)
        row.show_installment_plan = _get_bool(
            cfg,
            "show_installment_plan",
            True,
        )
        row.footer_note = (
            (cfg.get("footer_note") or None)
            if isinstance(cfg.get("footer_note"), str)
            else cfg.get("footer_note")
        )

    # سایر رکوردهای موجود که دیگر در per_type نیستند حذف می‌شوند
    for doc_type, row in existing_map.items():
        if doc_type not in keep_types:
            db.delete(row)

    db.commit()

    return get_business_print_settings(db, business_id)


def get_all_businesses_admin(db: Session, query_info: Dict[str, Any]) -> Dict[str, Any]:
    """دریافت لیست همه کسب و کارها برای ادمین (فقط سوپر ادمین)"""
    from adapters.db.models.user import User
    from adapters.api.v1.schemas import PaginationInfo
    from sqlalchemy import or_, func
    
    business_repo = BusinessRepository(db)
    
    # ساخت کوئری پایه
    query = db.query(Business)
    
    # اعمال فیلتر جستجو
    if query_info.get('search'):
        search_term = query_info['search'].lower()
        search_conditions = [
            func.lower(Business.name).contains(search_term)
        ]
        
        # اضافه کردن شرایط جستجو برای فیلدهای اختیاری (که ممکن است null باشند)
        search_conditions.append(func.lower(Business.phone).contains(search_term))
        search_conditions.append(func.lower(Business.mobile).contains(search_term))
        search_conditions.append(func.lower(Business.national_id).contains(search_term))
        search_conditions.append(func.lower(Business.economic_id).contains(search_term))
        
        query = query.filter(or_(*search_conditions))
    
    # فیلتر بر اساس نوع کسب و کار
    if query_info.get('business_type'):
        from adapters.db.models.business import BusinessType
        try:
            business_type = BusinessType(query_info['business_type'])
            query = query.filter(Business.business_type == business_type)
        except (ValueError, KeyError):
            pass
    
    # فیلتر بر اساس زمینه فعالیت
    if query_info.get('business_field'):
        from adapters.db.models.business import BusinessField
        try:
            business_field = BusinessField(query_info['business_field'])
            query = query.filter(Business.business_field == business_field)
        except (ValueError, KeyError):
            pass
    
    # فیلتر بر اساس استان
    if query_info.get('province'):
        query = query.filter(Business.province == query_info['province'])
    
    # فیلتر بر اساس شهر
    if query_info.get('city'):
        query = query.filter(Business.city == query_info['city'])
    
    # شمارش کل
    total = query.count()
    
    # اعمال مرتب‌سازی
    sort_by = query_info.get('sort_by', 'created_at')
    sort_desc = query_info.get('sort_desc', True)
    
    if sort_by == 'name':
        order_by = Business.name.desc() if sort_desc else Business.name.asc()
    elif sort_by == 'business_type':
        order_by = Business.business_type.desc() if sort_desc else Business.business_type.asc()
    elif sort_by == 'owner_id':
        order_by = Business.owner_id.desc() if sort_desc else Business.owner_id.asc()
    else:  # created_at (پیش‌فرض)
        order_by = Business.created_at.desc() if sort_desc else Business.created_at.asc()
    
    query = query.order_by(order_by)
    
    # اعمال صفحه‌بندی
    skip = query_info.get('skip', 0)
    take = query_info.get('take', 10)
    businesses = query.offset(skip).limit(take).all()
    
    # محاسبه اطلاعات صفحه‌بندی
    total_pages = (total + take - 1) // take if take > 0 else 1
    current_page = (skip // take) + 1 if take > 0 else 1
    
    pagination = PaginationInfo(
        total=total,
        page=current_page,
        per_page=take,
        total_pages=total_pages,
        has_next=current_page < total_pages,
        has_prev=current_page > 1
    )
    
    # تبدیل کسب و کارها به dictionary و افزودن اطلاعات مالک
    items = []
    for business in businesses:
        business_dict = _business_to_dict(business)
        
        # افزودن اطلاعات مالک
        owner = db.get(User, business.owner_id)
        if owner:
            business_dict['owner'] = {
                'id': owner.id,
                'email': owner.email,
                'mobile': owner.mobile,
                'first_name': owner.first_name,
                'last_name': owner.last_name,
                'full_name': f"{owner.first_name or ''} {owner.last_name or ''}".strip() or owner.email or owner.mobile
            }
        else:
            business_dict['owner'] = None
        
        items.append(business_dict)
    
    return {
        "items": items,
        "pagination": pagination.dict(),
        "query_info": query_info
    }


def _business_to_dict(business: Business) -> Dict[str, Any]:
    """تبدیل مدل کسب و کار به dictionary"""
    data = {
        "id": business.id,
        "name": business.name,
        "business_type": business.business_type.value,
        "business_field": business.business_field.value,
        "owner_id": business.owner_id,
        "address": business.address,
        "phone": business.phone,
        "mobile": business.mobile,
        "national_id": business.national_id,
        "registration_number": business.registration_number,
        "economic_id": business.economic_id,
        "country": business.country,
        "province": business.province,
        "city": business.city,
        "postal_code": business.postal_code,
        # فایل‌های گرافیکی مرتبط با کسب‌وکار
        "logo_file_id": getattr(business, "logo_file_id", None),
        "stamp_file_id": getattr(business, "stamp_file_id", None),
        # تنظیمات اعتبار
        "default_credit_limit": float(business.default_credit_limit) if getattr(business, "default_credit_limit", None) is not None else None,
        "check_credit_enabled_by_default": bool(getattr(business, "check_credit_enabled_by_default", False)),
        # تنظیمات محاسبه سود فاکتور
        "invoice_profit_calculation_method": getattr(business, "invoice_profit_calculation_method", None),
        "invoice_profit_calculation_basis": getattr(business, "invoice_profit_calculation_basis", None),
        "invoice_profit_include_overhead": bool(getattr(business, "invoice_profit_include_overhead", False)),
        "invoice_profit_overhead_type": getattr(business, "invoice_profit_overhead_type", None),
        "invoice_profit_overhead_percent": float(business.invoice_profit_overhead_percent) if getattr(business, "invoice_profit_overhead_percent", None) is not None else None,
        "invoice_profit_calculation_type": getattr(business, "invoice_profit_calculation_type", None),
        "invoice_sync_update_sales_price_enabled": bool(getattr(business, "invoice_sync_update_sales_price_enabled", False)),
        "invoice_sync_update_purchase_price_enabled": bool(getattr(business, "invoice_sync_update_purchase_price_enabled", False)),
        "invoice_sync_sales_price_basis": getattr(business, "invoice_sync_sales_price_basis", None),
        "invoice_sync_purchase_price_basis": getattr(business, "invoice_sync_purchase_price_basis", None),
        "invoice_warehouse_release_mode": _normalize_invoice_warehouse_release_mode(
            getattr(business, "invoice_warehouse_release_mode", None),
        ),
        "allow_negative_inventory_for_bulk": bool(getattr(business, "allow_negative_inventory_for_bulk", False)),
        "allow_negative_inventory_for_unique": bool(getattr(business, "allow_negative_inventory_for_unique", False)),
        "warehouse_transfer_require_positive_stock": bool(
            getattr(business, "warehouse_transfer_require_positive_stock", True),
        ),
        "created_at": business.created_at,  # datetime object بماند
        "updated_at": business.updated_at,   # datetime object بماند
        # Soft Delete fields
        "deleted_at": business.deleted_at.isoformat() if getattr(business, "deleted_at", None) else None,
        "deletion_requested_at": business.deletion_requested_at.isoformat() if getattr(business, "deletion_requested_at", None) else None,
        "auto_delete_at": business.auto_delete_at.isoformat() if getattr(business, "auto_delete_at", None) else None,
        "is_deleted": getattr(business, "deleted_at", None) is not None,
        "is_deletion_pending": (
            getattr(business, "deleted_at", None) is not None and
            getattr(business, "auto_delete_at", None) is not None and
            datetime.utcnow() < business.auto_delete_at
        ),
    }

    # ارز پیشفرض
    if getattr(business, "default_currency", None):
        c = business.default_currency
        data["default_currency"] = {
            "id": c.id,
            "code": c.code,
            "title": c.title,
            "symbol": c.symbol,
        }
    else:
        data["default_currency"] = None

    # ارزهای فعال کسب‌وکار
    if getattr(business, "currencies", None):
        data["currencies"] = [
            {"id": c.id, "code": c.code, "title": c.title, "symbol": c.symbol}
            for c in business.currencies
        ]
    else:
        data["currencies"] = []

    return data
