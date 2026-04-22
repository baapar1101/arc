# Removed __future__ annotations to fix OpenAPI schema generation

import structlog
from datetime import datetime
from fastapi import APIRouter, Depends, Request, HTTPException
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from adapters.api.v1.schemas import SuccessResponse
from app.core.responses import success_response, format_datetime_fields
from app.core.response_cache import cache_response
from app.core.cache import get_cache
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access
from app.services.business_dashboard_service import (
    get_business_dashboard_data, get_business_members, get_business_statistics
)
from app.services.dashboard_widgets_service import (
    get_widget_definitions,
    get_dashboard_layout_profile,
    save_dashboard_layout_profile,
    get_widgets_batch_data,
    get_business_default_layout,
    save_business_default_layout,
)

logger = structlog.get_logger()
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
@cache_response(ttl=60, vary_by=["business_id"])
async def get_business_dashboard(
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
    
    # دریافت اطلاعات کسب و کار با eager loading برای default_currency و currencies
    from sqlalchemy.orm import joinedload
    business = db.query(Business).options(
        joinedload(Business.default_currency),
        joinedload(Business.currencies)
    ).filter(Business.id == business_id).first()
    if not business:
        from app.core.responses import ApiError
        raise ApiError("NOT_FOUND", "Business not found", http_status=404)
    
    # دریافت دسترسی‌های کاربر
    permissions = {}
    
    if ctx.is_superadmin():
        # SuperAdmin فقط برای مدیریت سیستم است، نه برای کسب و کارهای خاص
        # باید دسترسی‌های کسب و کار را از جدول business_permissions دریافت کند
        permission_repo = BusinessPermissionRepository(db)
        business_permission = permission_repo.get_by_user_and_business(ctx.get_user_id(), business_id)
        
        if business_permission:
            permissions = business_permission.business_permissions or {}
        else:
            permissions = {}
    elif ctx.is_business_owner(business_id):
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
            "fiscal_years": {"view": True, "edit": True, "close": True, "rollback": True},
            "currency_revaluation": {"add": True, "edit": True, "view": True, "delete": True},
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
        # دریافت دسترسی‌های کسب و کار از business_permissions
        permission_repo = BusinessPermissionRepository(db)
        # ترتیب آرگومان‌ها: (user_id, business_id)
        business_permission = permission_repo.get_by_user_and_business(ctx.get_user_id(), business_id)
        
        if business_permission:
            permissions = business_permission.business_permissions or {}
    
    # استفاده از _business_to_dict برای دریافت اطلاعات کامل کسب و کار شامل default_currency و currencies
    from app.services.business_service import _business_to_dict
    business_dict = _business_to_dict(business)
    
    # استخراج فیلدهای مورد نیاز برای business_info
    created_at_value = business_dict.get("created_at")
    if isinstance(created_at_value, datetime):
        created_at_str = created_at_value.isoformat()
    else:
        created_at_str = str(created_at_value) if created_at_value else ""
    
    business_info = {
        "id": business_dict["id"],
        "name": business_dict["name"],
        "business_type": business_dict["business_type"],
        "business_field": business_dict["business_field"],
        "owner_id": business_dict["owner_id"],
        "address": business_dict["address"],
        "phone": business_dict["phone"],
        "mobile": business_dict["mobile"],
        "created_at": created_at_str,
    }
    
    is_owner = ctx.is_business_owner(business_id)
    has_access = ctx.can_access_business(business_id)
    
    response_data = {
        "business_info": business_info,
        "user_permissions": permissions,
        "is_owner": is_owner,
        "role": "مالک" if is_owner else "عضو",
        "has_access": has_access,
        # اضافه کردن default_currency و currencies به response
        "default_currency": business_dict.get("default_currency"),
        "currencies": business_dict.get("currencies", []),
    }
    
    logger.info(f"=== get_business_info_with_permissions END ===")
    
    formatted_data = format_datetime_fields(response_data, request)
    return success_response(formatted_data, request)


# === Dashboard Widgets (Responsive/Per-User) ===
@router.get("/{business_id}/dashboard/widgets/definitions",
    summary="تعاریف ویجت‌های داشبورد",
    description="لیست ویجت‌های قابل استفاده برای کاربر فعلی (بر اساس مجوزها) + ستون‌بندی رسپانسیو",
    response_model=SuccessResponse,
)
@require_business_access("business_id")
def list_dashboard_widget_definitions(
    request: Request,
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    # بهینه‌سازی: فقط business_id را تنظیم می‌کنیم و business_permissions را lazy load می‌کنیم
    # این باعث می‌شود query های اضافی انجام نشود
    if ctx.business_id != business_id:
        # تنظیم business_id در ctx موجود (بدون ساخت instance جدید)
        ctx.business_id = business_id
        # Lazy load business_permissions فقط اگر نیاز باشد
        ctx.business_permissions = ctx._get_business_permissions()
    
    cache = get_cache()
    cache_key = f"dashboard_widgets_definitions:{business_id}:{ctx.get_user_id()}"

    if cache.enabled:
        cached = cache.get(cache_key)
        if cached is not None:
            return success_response(cached, request)
    
    data = get_widget_definitions(db=db, business_id=business_id, user_id=ctx.get_user_id(), ctx=ctx)

    if cache.enabled:
        cache.set(cache_key, data, ttl=300)

    return success_response(data, request)


@router.get("/{business_id}/dashboard/layout",
    summary="دریافت چیدمان داشبورد (پروفایل رسپانسیو)",
    description="چیدمان کاربر برای یک breakpoint مشخص را برمی‌گرداند. در نبود، از پیش‌فرض سیستم استفاده می‌کند.",
    response_model=SuccessResponse,
)
@require_business_access("business_id")
def get_dashboard_layout(
    request: Request,
    business_id: int,
    breakpoint: str = "md",
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    cache = get_cache()
    cache_key = f"dashboard_layout:{business_id}:{ctx.get_user_id()}:{breakpoint}"

    if cache.enabled:
        cached = cache.get(cache_key)
        if cached is not None:
            return success_response(cached, request)

    profile = get_dashboard_layout_profile(
        db=db,
        business_id=business_id,
        user_id=ctx.get_user_id(),
        breakpoint=breakpoint,
    )

    if cache.enabled:
        cache.set(cache_key, profile, ttl=300)

    return success_response(profile, request)


@router.put("/{business_id}/dashboard/layout",
    summary="ذخیره چیدمان داشبورد (پروفایل رسپانسیو)",
    description="چیدمان کاربر برای breakpoint مشخص را ذخیره می‌کند.",
    response_model=SuccessResponse,
)
@require_business_access("business_id")
def put_dashboard_layout(
    request: Request,
    business_id: int,
    payload: dict,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    breakpoint = str(payload.get("breakpoint") or "md")
    items = payload.get("items") or []
    result = save_dashboard_layout_profile(
        db=db,
        business_id=business_id,
        user_id=ctx.get_user_id(),
        breakpoint=breakpoint,
        items=items,
    )

    # Invalidate cache برای layout همین کاربر/کسب‌وکار
    cache = get_cache()
    if cache.enabled:
        cache_key = f"dashboard_layout:{business_id}:{ctx.get_user_id()}:{breakpoint}"
        cache.delete(cache_key)

    return success_response(result, request)


@router.post("/{business_id}/dashboard/data",
    summary="دریافت داده‌ی ویجت‌ها (Batch)",
    description="کلیدهای ویجت را می‌گیرد و داده‌ی هر ویجت را در یک پاسخ برمی‌گرداند. برای query های طولانی از background job استفاده می‌کند.",
    response_model=SuccessResponse,
)
@require_business_access("business_id")
def post_dashboard_widgets_data(
    request: Request,
    business_id: int,
    payload: dict,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    """
    دریافت داده‌های dashboard widgets
    به صورت خودکار تصمیم می‌گیرد که از background job استفاده کند یا نه
    """
    from fastapi import Query
    cache = get_cache()
    widget_keys = payload.get("widget_keys") or []
    filters = dict(payload.get("filters") or {})
    # تزریق سال مالی از هدر درخواست برای ویجت‌هایی که به آن نیاز دارند
    fiscal_year_id_header = request.headers.get("X-Fiscal-Year-ID")
    if fiscal_year_id_header and filters.get("fiscal_year_id") is None:
        try:
            filters["fiscal_year_id"] = int(fiscal_year_id_header)
        except (ValueError, TypeError):
            pass
    calendar_type = ctx.calendar_type if hasattr(ctx, 'calendar_type') else "gregorian"
    use_queue = payload.get("use_queue", False)  # پارامتر اختیاری از payload

    # تصمیم‌گیری خودکار: اگر تعداد widget ها زیاد است یا query های سنگین داریم، از queue استفاده کن
    # ویجت‌های سنگین: top_selling_products, sales_bar_chart
    heavy_widgets = {"top_selling_products", "sales_bar_chart"}
    has_heavy_widgets = any(key in heavy_widgets for key in widget_keys)
    use_background = use_queue or len(widget_keys) > 5 or has_heavy_widgets
    
    if use_background:
        # استفاده از background job برای پردازش
        from app.core.queue import get_queue_service, QUEUE_DEFAULT
        from app.services.jobs.dashboard_job import process_dashboard_widgets_job
        
        queue_service = get_queue_service()
        if queue_service and queue_service.enabled:
            # ایجاد job در queue
            job = queue_service.enqueue(
                process_dashboard_widgets_job,
                business_id=business_id,
                user_id=ctx.get_user_id(),
                widget_keys=[str(k) for k in widget_keys],
                filters=filters,
                calendar_type=calendar_type,
                queue_name=QUEUE_DEFAULT,
                timeout=300,  # 5 دقیقه timeout
                result_ttl=3600,  # نتیجه را 1 ساعت نگه دار
            )
            
            if job:
                return success_response({
                    "job_id": job.id,
                    "status": "queued",
                    "message": "Dashboard widgets are being processed in background. Use GET /api/v1/jobs/{job_id} to check status."
                }, request)
        
        # اگر queue در دسترس نبود، به صورت sync اجرا کن (fallback)
    
    # اجرای sync برای query های سریع
    # توجه: FastAPI خودش session را مدیریت می‌کند، نیازی به close دستی نیست
    cache_key = None
    if cache.enabled and not use_background:
        # ساخت کلید کش بر اساس بیزنس، کاربر، نوع تقویم، ویجت‌ها و فیلترها
        import json, hashlib
        widgets_part = ",".join(sorted(str(k) for k in widget_keys))
        filters_json = json.dumps(filters, sort_keys=True, ensure_ascii=False)
        filters_hash = hashlib.sha256(filters_json.encode("utf-8")).hexdigest()[:16]
        cache_key = f"dashboard_data:{business_id}:{ctx.get_user_id()}:{calendar_type}:{widgets_part}:{filters_hash}"
        cached = cache.get(cache_key)
        if cached is not None:
            return success_response(cached, request)

    data = get_widgets_batch_data(
        db=db,
        business_id=business_id,
        user_id=ctx.get_user_id(),
        widget_keys=[str(k) for k in widget_keys],
        filters=filters,
        calendar_type=calendar_type,
    )
    formatted = format_datetime_fields(data, request)

    if cache.enabled and cache_key:
        cache.set(cache_key, formatted, ttl=30)

    return success_response(formatted, request)


@router.get("/{business_id}/dashboard/layout/default",
    summary="پیش‌فرض چیدمان کسب‌وکار (GET)",
    description="چیدمان پیش‌فرض منتشر شده توسط مالک کسب‌وکار را برمی‌گرداند (در صورت وجود).",
    response_model=SuccessResponse,
)
@require_business_access("business_id")
def get_business_default_dashboard_layout(
    request: Request,
    business_id: int,
    breakpoint: str = "md",
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    profile = get_business_default_layout(db=db, business_id=business_id, breakpoint=breakpoint)
    return success_response(profile or {}, request)


@router.put("/{business_id}/dashboard/layout/default",
    summary="انتشار چیدمان پیش‌فرض کسب‌وکار (PUT)",
    description="مالک کسب‌وکار می‌تواند چیدمان پیش‌فرض را برای breakpoint مشخص منتشر کند.",
    response_model=SuccessResponse,
)
@require_business_access("business_id")
def put_business_default_dashboard_layout(
    request: Request,
    business_id: int,
    payload: dict,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    # فقط مالک کسب‌وکار
    if not ctx.is_business_owner(business_id):
        raise HTTPException(status_code=403, detail="Only business owner can publish default layout")
    breakpoint = str(payload.get("breakpoint") or "md")
    items = payload.get("items") or []
    result = save_business_default_layout(db=db, business_id=business_id, breakpoint=breakpoint, items=items)
    return success_response(result, request)
