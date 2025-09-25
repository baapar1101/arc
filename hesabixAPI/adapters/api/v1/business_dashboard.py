# Removed __future__ annotations to fix OpenAPI schema generation

from fastapi import APIRouter, Depends, Request, HTTPException
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from adapters.api.v1.schemas import SuccessResponse
from app.core.responses import success_response, format_datetime_fields
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access
from app.services.business_dashboard_service import (
    get_business_dashboard_data, get_business_members, get_business_statistics
)

router = APIRouter(prefix="/business", tags=["business-dashboard"])


@router.post("/{business_id}/dashboard", 
    summary="دریافت داشبورد کسب و کار", 
    description="دریافت اطلاعات کلی و آمار کسب و کار",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "داشبورد کسب و کار با موفقیت دریافت شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "message": "داشبورد کسب و کار دریافت شد",
                        "data": {
                            "business_info": {
                                "id": 1,
                                "name": "شرکت نمونه",
                                "business_type": "شرکت",
                                "business_field": "تولیدی",
                                "owner_id": 1,
                                "created_at": "1403/01/01 00:00:00",
                                "member_count": 5
                            },
                            "statistics": {
                                "total_sales": 1000000.0,
                                "total_purchases": 500000.0,
                                "active_members": 5,
                                "recent_transactions": 25
                            },
                            "recent_activities": [
                                {
                                    "id": 1,
                                    "title": "فروش جدید",
                                    "description": "فروش محصول A به مبلغ 100,000 تومان",
                                    "icon": "sell",
                                    "time_ago": "2 ساعت پیش"
                                }
                            ]
                        }
                    }
                }
            }
        },
        401: {
            "description": "کاربر احراز هویت نشده است"
        },
        403: {
            "description": "دسترسی غیرمجاز به کسب و کار"
        },
        404: {
            "description": "کسب و کار یافت نشد"
        }
    }
)
@require_business_access("business_id")
def get_business_dashboard(
    request: Request,
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
) -> dict:
    """دریافت داشبورد کسب و کار"""
    dashboard_data = get_business_dashboard_data(db, business_id, ctx)
    formatted_data = format_datetime_fields(dashboard_data, request)
    return success_response(formatted_data, request)


@router.post("/{business_id}/members", 
    summary="لیست اعضای کسب و کار", 
    description="دریافت لیست اعضای کسب و کار",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "لیست اعضا با موفقیت دریافت شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "message": "لیست اعضا دریافت شد",
                        "data": {
                            "items": [
                                {
                                    "id": 1,
                                    "user_id": 2,
                                    "first_name": "احمد",
                                    "last_name": "احمدی",
                                    "email": "ahmad@example.com",
                                    "role": "مدیر فروش",
                                    "permissions": {
                                        "sales": {"write": True, "delete": True},
                                        "reports": {"export": True}
                                    },
                                    "joined_at": "1403/01/01 00:00:00"
                                }
                            ],
                            "pagination": {
                                "total": 1,
                                "page": 1,
                                "per_page": 10,
                                "total_pages": 1,
                                "has_next": False,
                                "has_prev": False
                            }
                        }
                    }
                }
            }
        },
        401: {
            "description": "کاربر احراز هویت نشده است"
        },
        403: {
            "description": "دسترسی غیرمجاز به کسب و کار"
        }
    }
)
@require_business_access("business_id")
def get_business_members(
    request: Request,
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
) -> dict:
    """لیست اعضای کسب و کار"""
    members_data = get_business_members(db, business_id, ctx)
    formatted_data = format_datetime_fields(members_data, request)
    return success_response(formatted_data, request)


@router.post("/{business_id}/statistics", 
    summary="آمار کسب و کار", 
    description="دریافت آمار تفصیلی کسب و کار",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "آمار با موفقیت دریافت شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "message": "آمار دریافت شد",
                        "data": {
                            "sales_by_month": [
                                {"month": "1403/01", "amount": 500000},
                                {"month": "1403/02", "amount": 750000}
                            ],
                            "top_products": [
                                {"name": "محصول A", "sales_count": 100, "revenue": 500000}
                            ],
                            "member_activity": {
                                "active_today": 3,
                                "active_this_week": 5,
                                "total_members": 8
                            }
                        }
                    }
                }
            }
        },
        401: {
            "description": "کاربر احراز هویت نشده است"
        },
        403: {
            "description": "دسترسی غیرمجاز به کسب و کار"
        }
    }
)
@require_business_access("business_id")
def get_business_statistics(
    request: Request,
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
) -> dict:
    """آمار کسب و کار"""
    stats_data = get_business_statistics(db, business_id, ctx)
    formatted_data = format_datetime_fields(stats_data, request)
    return success_response(formatted_data, request)


@router.post("/{business_id}/info-with-permissions", 
    summary="دریافت اطلاعات کسب و کار و دسترسی‌ها", 
    description="دریافت اطلاعات کسب و کار همراه با دسترسی‌های کاربر",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "اطلاعات کسب و کار و دسترسی‌ها با موفقیت دریافت شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "message": "اطلاعات کسب و کار و دسترسی‌ها دریافت شد",
                        "data": {
                            "business_info": {
                                "id": 1,
                                "name": "شرکت نمونه",
                                "business_type": "شرکت",
                                "business_field": "تولیدی",
                                "owner_id": 1,
                                "address": "تهران، خیابان ولیعصر",
                                "phone": "02112345678",
                                "mobile": "09123456789",
                                "created_at": "1403/01/01 00:00:00"
                            },
                            "user_permissions": {
                                "people": {"add": True, "view": True, "edit": True, "delete": False},
                                "products": {"add": True, "view": True, "edit": False, "delete": False},
                                "invoices": {"add": True, "view": True, "edit": True, "delete": True}
                            },
                            "is_owner": False,
                            "role": "عضو",
                            "has_access": True
                        }
                    }
                }
            }
        },
        401: {
            "description": "کاربر احراز هویت نشده است"
        },
        403: {
            "description": "دسترسی غیرمجاز به کسب و کار"
        },
        404: {
            "description": "کسب و کار یافت نشد"
        }
    }
)
@require_business_access("business_id")
def get_business_info_with_permissions(
    request: Request,
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
) -> dict:
    """دریافت اطلاعات کسب و کار همراه با دسترسی‌های کاربر"""
    from adapters.db.models.business import Business
    from adapters.db.repositories.business_permission_repo import BusinessPermissionRepository
    
    # دریافت اطلاعات کسب و کار
    business = db.get(Business, business_id)
    if not business:
        from app.core.responses import ApiError
        raise ApiError("NOT_FOUND", "Business not found", http_status=404)
    
    # دریافت دسترسی‌های کاربر
    permissions = {}
    if not ctx.is_superadmin() and not ctx.is_business_owner(business_id):
        # دریافت دسترسی‌های کسب و کار از business_permissions
        permission_repo = BusinessPermissionRepository(db)
        # ترتیب آرگومان‌ها: (user_id, business_id)
        business_permission = permission_repo.get_by_user_and_business(ctx.get_user_id(), business_id)
        if business_permission:
            permissions = business_permission.business_permissions or {}
    
    business_info = {
        "id": business.id,
        "name": business.name,
        "business_type": business.business_type.value,
        "business_field": business.business_field.value,
        "owner_id": business.owner_id,
        "address": business.address,
        "phone": business.phone,
        "mobile": business.mobile,
        "created_at": business.created_at.isoformat(),
    }
    
    response_data = {
        "business_info": business_info,
        "user_permissions": permissions,
        "is_owner": ctx.is_business_owner(business_id),
        "role": "مالک" if ctx.is_business_owner(business_id) else "عضو",
        "has_access": ctx.can_access_business(business_id)
    }
    
    formatted_data = format_datetime_fields(response_data, request)
    return success_response(formatted_data, request)
