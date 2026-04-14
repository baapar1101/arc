"""
مثال‌هایی از استفاده از سیستم دسترسی دو سطحی
"""

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import (
    require_superadmin,
    require_user_management,
    require_business_management,
    require_sales_write,
    require_sales_delete,
    require_accounting_write,
    require_reports_export,
    require_settings_manage_users,
    require_any_permission,
    require_business_access
)
from app.core.responses import ApiError

router = APIRouter()


# مثال 1: دسترسی‌های اپلیکیشن
@router.get("/admin/users")
@require_user_management()
def list_users(ctx: AuthContext = Depends(get_current_user)):
    """لیست کاربران - نیاز به دسترسی مدیریت کاربران در سطح اپلیکیشن"""
    return {"message": "User list", "user_id": ctx.get_user_id()}


@router.get("/admin/businesses")
@require_business_management()
def list_businesses(ctx: AuthContext = Depends(get_current_user)):
    """لیست کسب و کارها - نیاز به دسترسی مدیریت کسب و کارها"""
    return {"message": "Business list"}


@router.get("/admin/system-settings")
@require_superadmin()
def get_system_settings(ctx: AuthContext = Depends(get_current_user)):
    """تنظیمات سیستم - فقط superadmin"""
    return {"message": "System settings"}


# مثال 2: دسترسی‌های کسب و کار
@router.post("/business/{business_id}/sales")
@require_business_access("business_id")
@require_sales_write()
def create_sale(
    business_id: int,
    ctx: AuthContext = Depends(get_current_user)
):
    """ایجاد فروش - نیاز به دسترسی نوشتن در بخش فروش"""
    return {"message": f"Sale created for business {business_id}"}


@router.delete("/business/{business_id}/sales/{sale_id}")
@require_business_access("business_id")
@require_sales_delete()
def delete_sale(
    business_id: int,
    sale_id: int,
    ctx: AuthContext = Depends(get_current_user)
):
    """حذف فروش - نیاز به دسترسی حذف در بخش فروش"""
    return {"message": f"Sale {sale_id} deleted from business {business_id}"}


@router.post("/business/{business_id}/accounting/entries")
@require_business_access("business_id")
@require_accounting_write()
def create_accounting_entry(
    business_id: int,
    ctx: AuthContext = Depends(get_current_user)
):
    """ایجاد سند حسابداری - نیاز به دسترسی نوشتن در بخش حسابداری"""
    return {"message": f"Accounting entry created for business {business_id}"}


@router.get("/business/{business_id}/reports/export")
@require_business_access("business_id")
@require_reports_export()
def export_reports(
    business_id: int,
    ctx: AuthContext = Depends(get_current_user)
):
    """صادرات گزارش - نیاز به دسترسی صادرات گزارش"""
    return {"message": f"Reports exported for business {business_id}"}


@router.post("/business/{business_id}/users")
@require_business_access("business_id")
@require_settings_manage_users()
def add_business_user(
    business_id: int,
    ctx: AuthContext = Depends(get_current_user)
):
    """اضافه کردن کاربر به کسب و کار - نیاز به دسترسی مدیریت کاربران کسب و کار"""
    return {"message": f"User added to business {business_id}"}


# مثال 3: بررسی دسترسی‌های ترکیبی
@router.get("/business/{business_id}/dashboard")
@require_business_access("business_id")
def get_business_dashboard(
    business_id: int,
    ctx: AuthContext = Depends(get_current_user)
):
    """داشبورد کسب و کار - بررسی دسترسی‌های مختلف"""
    dashboard_data = {
        "business_id": business_id,
        "user_permissions": {
            "can_read_sales": ctx.can_read_section("sales"),
            "can_write_sales": ctx.can_write_section("sales"),
            "can_delete_sales": ctx.can_delete_section("sales"),
            "can_read_accounting": ctx.can_read_section("accounting"),
            "can_write_accounting": ctx.can_write_section("accounting"),
            "can_export_reports": ctx.can_export_section("reports"),
            "can_manage_users": ctx.can_manage_business_users(),
        }
    }
    
    return dashboard_data


# مثال 4: بررسی دسترسی‌های پویا
@router.get("/business/{business_id}/permissions")
@require_business_access("business_id")
def get_user_permissions(
    business_id: int,
    ctx: AuthContext = Depends(get_current_user)
):
    """دریافت دسترسی‌های کاربر برای کسب و کار"""
    return {
        "app_permissions": ctx.app_permissions,
        "business_permissions": ctx.business_permissions,
        "is_superadmin": ctx.is_superadmin(),
        "is_business_owner": ctx.is_business_owner(),
        "can_access_business": ctx.can_access_business(business_id),
        "permissions_info": {
            "has_automatic_app_permissions": ctx.is_superadmin(),
            "has_automatic_business_permissions": ctx.is_business_owner(),
            "effective_permissions": {
                "can_manage_users": ctx.can_manage_users(),
                "can_manage_businesses": ctx.can_manage_businesses(),
                "can_write_sales": ctx.can_write_section("sales"),
                "can_delete_sales": ctx.can_delete_section("sales"),
                "can_approve_sales": ctx.can_approve_section("sales"),
                "can_export_reports": ctx.can_export_section("reports"),
            }
        }
    }


# مثال 5: بررسی دسترسی‌های پیچیده
@router.get("/business/{business_id}/sales/analytics")
@require_business_access("business_id")
def get_sales_analytics(
    business_id: int,
    ctx: AuthContext = Depends(get_current_user)
):
    """تحلیل فروش - نیاز به دسترسی خواندن فروش و صادرات گزارش"""
    if not ctx.has_any_permission("sales", "read"):
        raise ApiError("FORBIDDEN", "No permission to read sales data")
    
    if not ctx.has_any_permission("reports", "export"):
        raise ApiError("FORBIDDEN", "No permission to export analytics")
    
    return {"message": f"Sales analytics for business {business_id}"}


# مثال 6: مدیریت دسترسی‌ها (فقط superadmin)
@router.post("/admin/business/{business_id}/users/{user_id}/permissions")
@require_superadmin()
def update_user_business_permissions(
    business_id: int,
    user_id: int,
    permissions: dict,
    ctx: AuthContext = Depends(get_current_user)
):
    """به‌روزرسانی دسترسی‌های کاربر در کسب و کار - فقط superadmin"""
    # اینجا باید منطق به‌روزرسانی دسترسی‌ها پیاده‌سازی شود
    return {
        "message": f"Permissions updated for user {user_id} in business {business_id}",
        "permissions": permissions
    }
