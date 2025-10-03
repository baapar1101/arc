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
    import logging
    logger = logging.getLogger(__name__)
    
    logger.info(f"=== get_business_info_with_permissions START ===")
    logger.info(f"Business ID: {business_id}")
    logger.info(f"User ID: {ctx.get_user_id()}")
    logger.info(f"User context business_id: {ctx.business_id}")
    logger.info(f"Is superadmin: {ctx.is_superadmin()}")
    logger.info(f"Is business owner: {ctx.is_business_owner(business_id)}")
    
    from adapters.db.models.business import Business
    from adapters.db.repositories.business_permission_repo import BusinessPermissionRepository
    
    # دریافت اطلاعات کسب و کار
    business = db.get(Business, business_id)
    if not business:
        logger.error(f"Business {business_id} not found")
        from app.core.responses import ApiError
        raise ApiError("NOT_FOUND", "Business not found", http_status=404)
    
    logger.info(f"Business found: {business.name} (Owner ID: {business.owner_id})")
    
    # دریافت دسترسی‌های کاربر
    permissions = {}
    
    # Debug logging
    logger.info(f"Checking permissions for user {ctx.get_user_id()}")
    logger.info(f"Is superadmin: {ctx.is_superadmin()}")
    logger.info(f"Is business owner of {business_id}: {ctx.is_business_owner(business_id)}")
    logger.info(f"Context business_id: {ctx.business_id}")
    
    if ctx.is_superadmin():
        logger.info("User is superadmin, but superadmin permissions don't apply to business operations")
        # SuperAdmin فقط برای مدیریت سیستم است، نه برای کسب و کارهای خاص
        # باید دسترسی‌های کسب و کار را از جدول business_permissions دریافت کند
        permission_repo = BusinessPermissionRepository(db)
        business_permission = permission_repo.get_by_user_and_business(ctx.get_user_id(), business_id)
        logger.info(f"Business permission object for superadmin: {business_permission}")
        
        if business_permission:
            permissions = business_permission.business_permissions or {}
            logger.info(f"Superadmin business permissions: {permissions}")
        else:
            logger.info("No business permission found for superadmin user")
            permissions = {}
    elif ctx.is_business_owner(business_id):
        logger.info("User is business owner, granting full permissions")
        # مالک کسب و کار تمام دسترسی‌ها را دارد
        permissions = {
            "people": {"add": True, "edit": True, "view": True, "delete": True},
            "products": {"add": True, "edit": True, "view": True, "delete": True},
            "bank_accounts": {"add": True, "edit": True, "view": True, "delete": True},
            "invoices": {"add": True, "edit": True, "view": True, "draft": True, "delete": True},
            "people_transactions": {"add": True, "edit": True, "view": True, "draft": True, "delete": True},
            "expenses_income": {"add": True, "edit": True, "view": True, "draft": True, "delete": True},
            "transfers": {"add": True, "edit": True, "view": True, "draft": True, "delete": True},
            "checks": {"add": True, "edit": True, "view": True, "delete": True, "return": True, "collect": True, "transfer": True},
            "accounting_documents": {"add": True, "edit": True, "view": True, "draft": True, "delete": True},
            "chart_of_accounts": {"add": True, "edit": True, "view": True, "delete": True},
            "opening_balance": {"edit": True, "view": True},
            "settings": {"print": True, "users": True, "history": True, "business": True},
            "categories": {"add": True, "edit": True, "view": True, "delete": True},
            "product_attributes": {"add": True, "edit": True, "view": True, "delete": True},
            "warehouses": {"add": True, "edit": True, "view": True, "delete": True},
            "warehouse_transfers": {"add": True, "edit": True, "view": True, "draft": True, "delete": True},
            "cash": {"add": True, "edit": True, "view": True, "delete": True},
            "petty_cash": {"add": True, "edit": True, "view": True, "delete": True},
            "wallet": {"view": True, "charge": True},
            "storage": {"view": True, "delete": True},
            "marketplace": {"buy": True, "view": True, "invoices": True},
            "price_lists": {"add": True, "edit": True, "view": True, "delete": True},
            "sms": {"history": True, "templates": True},
            "join": True
        }
    else:
        logger.info("User is not superadmin and not business owner, checking permissions")
        # دریافت دسترسی‌های کسب و کار از business_permissions
        permission_repo = BusinessPermissionRepository(db)
        # ترتیب آرگومان‌ها: (user_id, business_id)
        business_permission = permission_repo.get_by_user_and_business(ctx.get_user_id(), business_id)
        logger.info(f"Business permission object: {business_permission}")
        
        if business_permission:
            permissions = business_permission.business_permissions or {}
            logger.info(f"User permissions: {permissions}")
        else:
            logger.info("No business permission found for user")
    
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
    
    is_owner = ctx.is_business_owner(business_id)
    has_access = ctx.can_access_business(business_id)
    
    response_data = {
        "business_info": business_info,
        "user_permissions": permissions,
        "is_owner": is_owner,
        "role": "مالک" if is_owner else "عضو",
        "has_access": has_access
    }
    
    logger.info(f"Response data: {response_data}")
    logger.info(f"=== get_business_info_with_permissions END ===")
    
    formatted_data = format_datetime_fields(response_data, request)
    return success_response(formatted_data, request)
