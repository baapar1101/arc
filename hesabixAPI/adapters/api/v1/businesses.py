# Removed __future__ annotations to fix OpenAPI schema generation

from fastapi import APIRouter, Depends, Request, Query, HTTPException
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from adapters.api.v1.schemas import (
    BusinessCreateRequest, BusinessUpdateRequest, BusinessResponse,
    BusinessListResponse, BusinessSummaryResponse, SuccessResponse
)
from app.core.responses import success_response, format_datetime_fields
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_management
from app.services.business_service import (
    create_business, get_business_by_id, get_businesses_by_owner, get_user_businesses,
    update_business, delete_business, get_business_summary
)


router = APIRouter(prefix="/businesses", tags=["businesses"])


@router.post("", 
    summary="ایجاد کسب و کار جدید", 
    description="ایجاد کسب و کار جدید برای کاربر جاری",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "کسب و کار با موفقیت ایجاد شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "message": "کسب و کار با موفقیت ایجاد شد",
                        "data": {
                            "id": 1,
                            "name": "شرکت نمونه",
                            "business_type": "شرکت",
                            "business_field": "تولیدی",
                            "owner_id": 1,
                            "created_at": "2024-01-01T00:00:00Z"
                        }
                    }
                }
            }
        },
        400: {
            "description": "خطا در اعتبارسنجی داده‌ها"
        },
        401: {
            "description": "کاربر احراز هویت نشده است"
        }
    }
)
def create_new_business(
    request: Request,
    business_data: BusinessCreateRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
) -> dict:
    """ایجاد کسب و کار جدید"""
    owner_id = ctx.get_user_id()
    business = create_business(db, business_data, owner_id)
    formatted_data = format_datetime_fields(business, request)
    return success_response(formatted_data, request)


@router.post("/list", 
    summary="لیست کسب و کارهای کاربر", 
    description="دریافت لیست کسب و کارهای کاربر جاری با قابلیت فیلتر و جستجو",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "لیست کسب و کارها با موفقیت دریافت شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "message": "لیست کسب و کارها دریافت شد",
                        "data": {
                            "items": [
                                {
                                    "id": 1,
                                    "name": "شرکت نمونه",
                                    "business_type": "شرکت",
                                    "business_field": "تولیدی",
                                    "owner_id": 1,
                                    "created_at": "1403/01/01 00:00:00"
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
        }
    }
)
def list_user_businesses(
    request: Request,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    take: int = 10,
    skip: int = 0,
    sort_by: str = "created_at",
    sort_desc: bool = True,
    search: str = None
) -> dict:
    """لیست کسب و کارهای کاربر (مالک + عضو)"""
    user_id = ctx.get_user_id()
    query_dict = {
        "take": take,
        "skip": skip,
        "sort_by": sort_by,
        "sort_desc": sort_desc,
        "search": search
    }
    businesses = get_user_businesses(db, user_id, query_dict)
    formatted_data = format_datetime_fields(businesses, request)
    
    return success_response(formatted_data, request)


@router.get("/{business_id}", 
    summary="جزئیات کسب و کار", 
    description="دریافت جزئیات یک کسب و کار خاص",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "جزئیات کسب و کار با موفقیت دریافت شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "message": "جزئیات کسب و کار دریافت شد",
                        "data": {
                            "id": 1,
                            "name": "شرکت نمونه",
                            "business_type": "شرکت",
                            "business_field": "تولیدی",
                            "owner_id": 1,
                            "address": "تهران، خیابان ولیعصر",
                            "phone": "02112345678",
                            "created_at": "1403/01/01 00:00:00"
                        }
                    }
                }
            }
        },
        401: {
            "description": "کاربر احراز هویت نشده است"
        },
        404: {
            "description": "کسب و کار یافت نشد"
        }
    }
)
@router.post("/{business_id}/details", 
    summary="جزئیات کسب و کار", 
    description="دریافت جزئیات یک کسب و کار خاص",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "جزئیات کسب و کار با موفقیت دریافت شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "message": "جزئیات کسب و کار دریافت شد",
                        "data": {
                            "id": 1,
                            "name": "شرکت نمونه",
                            "business_type": "شرکت",
                            "business_field": "تولیدی",
                            "owner_id": 1,
                            "address": "تهران، خیابان ولیعصر",
                            "phone": "02112345678",
                            "created_at": "1403/01/01 00:00:00"
                        }
                    }
                }
            }
        },
        401: {
            "description": "کاربر احراز هویت نشده است"
        },
        404: {
            "description": "کسب و کار یافت نشد"
        }
    }
)
def get_business(
    request: Request,
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
) -> dict:
    """دریافت جزئیات کسب و کار"""
    owner_id = ctx.get_user_id()
    business = get_business_by_id(db, business_id, owner_id)
    
    if not business:
        raise HTTPException(status_code=404, detail="کسب و کار یافت نشد")
    
    formatted_data = format_datetime_fields(business, request)
    return success_response(formatted_data, request)


@router.put("/{business_id}", 
    summary="ویرایش کسب و کار", 
    description="ویرایش اطلاعات یک کسب و کار",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "کسب و کار با موفقیت ویرایش شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "message": "کسب و کار با موفقیت ویرایش شد",
                        "data": {
                            "id": 1,
                            "name": "شرکت نمونه ویرایش شده",
                            "business_type": "شرکت",
                            "business_field": "تولیدی",
                            "owner_id": 1,
                            "updated_at": "2024-01-01T12:00:00Z"
                        }
                    }
                }
            }
        },
        400: {
            "description": "خطا در اعتبارسنجی داده‌ها"
        },
        401: {
            "description": "کاربر احراز هویت نشده است"
        },
        404: {
            "description": "کسب و کار یافت نشد"
        }
    }
)
@require_business_management()
def update_business_info(
    request: Request,
    business_id: int,
    business_data: BusinessUpdateRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
) -> dict:
    """ویرایش کسب و کار"""
    owner_id = ctx.get_user_id()
    business = update_business(db, business_id, business_data, owner_id)
    
    if not business:
        raise HTTPException(status_code=404, detail="کسب و کار یافت نشد")
    
    formatted_data = format_datetime_fields(business, request)
    return success_response(formatted_data, request, "کسب و کار با موفقیت ویرایش شد")


@router.delete("/{business_id}", 
    summary="حذف کسب و کار", 
    description="حذف یک کسب و کار",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "کسب و کار با موفقیت حذف شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "message": "کسب و کار با موفقیت حذف شد",
                        "data": {"ok": True}
                    }
                }
            }
        },
        401: {
            "description": "کاربر احراز هویت نشده است"
        },
        404: {
            "description": "کسب و کار یافت نشد"
        }
    }
)
def delete_business_info(
    request: Request,
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
) -> dict:
    """حذف کسب و کار"""
    owner_id = ctx.get_user_id()
    success = delete_business(db, business_id, owner_id)
    
    if not success:
        raise HTTPException(status_code=404, detail="کسب و کار یافت نشد")
    
    return success_response({"ok": True}, request, "کسب و کار با موفقیت حذف شد")


@router.post("/stats", 
    summary="آمار کسب و کارها", 
    description="دریافت آمار کلی کسب و کارهای کاربر",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "آمار کسب و کارها با موفقیت دریافت شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "message": "آمار کسب و کارها دریافت شد",
                        "data": {
                            "total_businesses": 5,
                            "by_type": {
                                "شرکت": 2,
                                "مغازه": 1,
                                "فروشگاه": 2
                            },
                            "by_field": {
                                "تولیدی": 3,
                                "خدماتی": 2
                            }
                        }
                    }
                }
            }
        },
        401: {
            "description": "کاربر احراز هویت نشده است"
        }
    }
)
def get_business_stats(
    request: Request,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db)
) -> dict:
    """آمار کسب و کارها"""
    owner_id = ctx.get_user_id()
    stats = get_business_summary(db, owner_id)
    return success_response(stats, request)
