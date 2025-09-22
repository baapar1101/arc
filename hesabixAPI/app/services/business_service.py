from __future__ import annotations

from typing import List, Optional, Dict, Any
from sqlalchemy.orm import Session
from sqlalchemy import select, and_, func

from adapters.db.repositories.business_repo import BusinessRepository
from adapters.db.models.business import Business, BusinessType, BusinessField
from adapters.api.v1.schemas import (
    BusinessCreateRequest, BusinessUpdateRequest, BusinessResponse,
    BusinessListResponse, BusinessSummaryResponse, PaginationInfo
)
from app.core.responses import format_datetime_fields


def create_business(db: Session, business_data: BusinessCreateRequest, owner_id: int) -> Dict[str, Any]:
    """ایجاد کسب و کار جدید"""
    business_repo = BusinessRepository(db)
    
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
    return {
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
