from __future__ import annotations

from typing import List, Optional, Dict, Any
from sqlalchemy.orm import Session
from sqlalchemy import select, and_, func

from adapters.db.repositories.business_repo import BusinessRepository
from adapters.db.repositories.fiscal_year_repo import FiscalYearRepository
from adapters.db.models.currency import Currency, BusinessCurrency
from adapters.db.repositories.business_permission_repo import BusinessPermissionRepository
from adapters.db.models.business import Business, BusinessType, BusinessField
from adapters.api.v1.schemas import (
    BusinessCreateRequest, BusinessUpdateRequest, BusinessResponse,
    BusinessListResponse, BusinessSummaryResponse, PaginationInfo
)
from app.core.responses import format_datetime_fields


def create_business(db: Session, business_data: BusinessCreateRequest, owner_id: int) -> Dict[str, Any]:
    """ایجاد کسب و کار جدید"""
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

    db.refresh(created_business)

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


def get_user_businesses(db: Session, user_id: int, query_info: Dict[str, Any]) -> Dict[str, Any]:
    """دریافت لیست کسب و کارهای کاربر (مالک + عضو)"""
    business_repo = BusinessRepository(db)
    permission_repo = BusinessPermissionRepository(db)
    
    # دریافت کسب و کارهای مالک
    owned_businesses = business_repo.get_by_owner_id(user_id)
    
    # دریافت کسب و کارهای عضو
    member_permissions = permission_repo.get_user_member_businesses(user_id)
    member_business_ids = [perm.business_id for perm in member_permissions]
    member_businesses = []
    for business_id in member_business_ids:
        business = business_repo.get_by_id(business_id)
        if business:
            member_businesses.append(business)
    
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
            business_dict['permissions'] = permission_obj.business_permissions if permission_obj else {}
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


def update_business(db: Session, business_id: int, business_data: BusinessUpdateRequest, owner_id: int) -> Optional[Dict[str, Any]]:
    """ویرایش کسب و کار"""
    business_repo = BusinessRepository(db)
    business = business_repo.get_by_id(business_id)
    
    if not business or business.owner_id != owner_id:
        return None
    
    # به‌روزرسانی فیلدها
    update_data = business_data.dict(exclude_unset=True)
    for field, value in update_data.items():
        setattr(business, field, value)
    
    # ذخیره تغییرات
    updated_business = business_repo.update(business)
    
    return _business_to_dict(updated_business)


def delete_business(db: Session, business_id: int, owner_id: int) -> bool:
    """حذف کسب و کار"""
    business_repo = BusinessRepository(db)
    business = business_repo.get_by_id(business_id)
    
    if not business or business.owner_id != owner_id:
        return False
    
    business_repo.delete(business_id)
    return True


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
        "created_at": business.created_at,  # datetime object بماند
        "updated_at": business.updated_at   # datetime object بماند
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
