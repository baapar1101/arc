from __future__ import annotations

from typing import List, Optional, Dict, Any
from sqlalchemy.orm import Session
from sqlalchemy import select, and_, func
from datetime import datetime, timedelta

from adapters.db.repositories.business_repo import BusinessRepository
from adapters.db.repositories.business_permission_repo import BusinessPermissionRepository
from adapters.db.repositories.user_repo import UserRepository
from adapters.db.models.business import Business
from adapters.db.models.business_permission import BusinessPermission
from adapters.db.models.user import User
from app.core.auth_dependency import AuthContext


def get_business_dashboard_data(db: Session, business_id: int, ctx: AuthContext) -> Dict[str, Any]:
    """دریافت داده‌های داشبورد کسب و کار"""
    business_repo = BusinessRepository(db)
    business = business_repo.get_by_id(business_id)
    
    if not business:
        raise ValueError("کسب و کار یافت نشد")
    
    # بررسی دسترسی کاربر
    if not ctx.can_access_business(business_id):
        raise ValueError("دسترسی غیرمجاز")
    
    # دریافت اطلاعات کسب و کار
    business_info = _get_business_info(business, db)
    
    # دریافت آمار
    statistics = _get_business_statistics(business_id, db)
    
    # دریافت فعالیت‌های اخیر
    recent_activities = _get_recent_activities(business_id, db)
    
    return {
        "business_info": business_info,
        "statistics": statistics,
        "recent_activities": recent_activities
    }


def get_business_members(db: Session, business_id: int, ctx: AuthContext) -> Dict[str, Any]:
    """دریافت لیست اعضای کسب و کار"""
    if not ctx.can_access_business(business_id):
        raise ValueError("دسترسی غیرمجاز")
    
    permission_repo = BusinessPermissionRepository(db)
    user_repo = UserRepository(db)
    
    # دریافت دسترسی‌های کسب و کار
    permissions = permission_repo.get_business_users(business_id)
    
    members = []
    for permission in permissions:
        user = user_repo.get_by_id(permission.user_id)
        if user:
            members.append({
                "id": permission.id,
                "user_id": user.id,
                "first_name": user.first_name,
                "last_name": user.last_name,
                "email": user.email,
                "mobile": user.mobile,
                "role": _get_user_role(permission.business_permissions),
                "permissions": permission.business_permissions or {},
                "joined_at": permission.created_at.isoformat()
            })
    
    return {
        "items": members,
        "pagination": {
            "total": len(members),
            "page": 1,
            "per_page": len(members),
            "total_pages": 1,
            "has_next": False,
            "has_prev": False
        }
    }


def get_business_statistics(db: Session, business_id: int, ctx: AuthContext) -> Dict[str, Any]:
    """دریافت آمار تفصیلی کسب و کار"""
    if not ctx.can_access_business(business_id):
        raise ValueError("دسترسی غیرمجاز")
    
    # آمار فروش ماهانه (نمونه)
    sales_by_month = [
        {"month": "2024-01", "amount": 500000},
        {"month": "2024-02", "amount": 750000},
        {"month": "2024-03", "amount": 600000}
    ]
    
    # پرفروش‌ترین محصولات (نمونه)
    top_products = [
        {"name": "محصول A", "sales_count": 100, "revenue": 500000},
        {"name": "محصول B", "sales_count": 80, "revenue": 400000},
        {"name": "محصول C", "sales_count": 60, "revenue": 300000}
    ]
    
    # آمار فعالیت اعضا
    permission_repo = BusinessPermissionRepository(db)
    members = permission_repo.get_business_users(business_id)
    
    member_activity = {
        "active_today": len([m for m in members if m.created_at.date() == datetime.now().date()]),
        "active_this_week": len([m for m in members if m.created_at >= datetime.now() - timedelta(days=7)]),
        "total_members": len(members)
    }
    
    return {
        "sales_by_month": sales_by_month,
        "top_products": top_products,
        "member_activity": member_activity
    }


def _get_business_info(business: Business, db: Session) -> Dict[str, Any]:
    """دریافت اطلاعات کسب و کار"""
    permission_repo = BusinessPermissionRepository(db)
    member_count = len(permission_repo.get_business_users(business.id))
    
    return {
        "id": business.id,
        "name": business.name,
        "business_type": business.business_type.value,
        "business_field": business.business_field.value,
        "owner_id": business.owner_id,
        "address": business.address,
        "phone": business.phone,
        "mobile": business.mobile,
        "created_at": business.created_at.isoformat(),
        "member_count": member_count
    }


def _get_business_statistics(business_id: int, db: Session) -> Dict[str, Any]:
    """دریافت آمار کلی کسب و کار"""
    # در اینجا می‌توانید آمار واقعی را از جداول مربوطه دریافت کنید
    # فعلاً داده‌های نمونه برمی‌گردانیم
    return {
        "total_sales": 1000000.0,
        "total_purchases": 500000.0,
        "active_members": 5,
        "recent_transactions": 25
    }


def _get_recent_activities(business_id: int, db: Session) -> List[Dict[str, Any]]:
    """دریافت فعالیت‌های اخیر"""
    # در اینجا می‌توانید فعالیت‌های واقعی را از جداول مربوطه دریافت کنید
    # فعلاً داده‌های نمونه برمی‌گردانیم
    return [
        {
            "id": 1,
            "title": "فروش جدید",
            "description": "فروش محصول A به مبلغ 100,000 تومان",
            "icon": "sell",
            "time_ago": "2 ساعت پیش"
        },
        {
            "id": 2,
            "title": "عضو جدید",
            "description": "احمد احمدی به تیم اضافه شد",
            "icon": "person_add",
            "time_ago": "5 ساعت پیش"
        },
        {
            "id": 3,
            "title": "گزارش ماهانه",
            "description": "گزارش فروش ماه ژانویه تولید شد",
            "icon": "assessment",
            "time_ago": "1 روز پیش"
        }
    ]


def _get_user_role(permissions: Optional[Dict[str, Any]]) -> str:
    """تعیین نقش کاربر بر اساس دسترسی‌ها"""
    if not permissions:
        return "عضو"
    
    # بررسی دسترسی‌های مختلف برای تعیین نقش
    if permissions.get("settings", {}).get("manage_users"):
        return "مدیر"
    elif permissions.get("sales", {}).get("write"):
        return "مدیر فروش"
    elif permissions.get("accounting", {}).get("write"):
        return "حسابدار"
    else:
        return "عضو"
