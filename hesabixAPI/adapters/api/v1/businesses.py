# Removed __future__ annotations to fix OpenAPI schema generation

from typing import Dict, Any

from fastapi import APIRouter, Depends, Request, Query, HTTPException, UploadFile, File
from sqlalchemy.orm import Session
from uuid import UUID
import io

from adapters.db.session import get_db
from adapters.api.v1.schemas import (
    BusinessCreateRequest, BusinessUpdateRequest, BusinessResponse,
    BusinessListResponse, BusinessSummaryResponse, SuccessResponse
)
from app.core.responses import success_response, format_datetime_fields
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_management, require_business_access, require_business_permission_dep
from app.services.business_service import (
    create_business,
    get_business_by_id,
    get_businesses_by_owner,
    get_user_businesses,
    update_business,
    delete_business,
    get_business_summary,
    get_business_print_settings,
    update_business_print_settings,
)
from app.services.file_storage_service import FileStorageService
from adapters.db.models.business import Business
from starlette.responses import StreamingResponse


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
@require_business_access("business_id")
def update_business_info(
    request: Request,
    business_id: int,
    business_data: BusinessUpdateRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("settings", "business")),
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


@router.post(
    "/{business_id}/logo",
    summary="آپلود لوگوی کسب‌وکار",
    description="آپلود تصویر لوگوی کسب‌وکار و ذخیره شناسه فایل روی رکورد Business.",
    response_model=SuccessResponse,
)
@require_business_access("business_id")
async def upload_business_logo(
    request: Request,
    business_id: int,
    file: UploadFile = File(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("settings", "print")),
) -> dict:
    # بررسی وجود کسب‌وکار
    business = db.query(Business).filter(Business.id == business_id).first()
    if not business:
        raise HTTPException(status_code=404, detail="کسب و کار یافت نشد")

    storage = FileStorageService(db)
    
    # حذف فایل قدیمی لوگو اگر وجود داشته باشد
    if business.logo_file_id:
        try:
            old_file_id = UUID(str(business.logo_file_id))
            await storage.delete_file(old_file_id)
        except Exception:
            pass  # اگر فایل قدیمی وجود نداشت یا خطا رخ داد، ادامه می‌دهیم
    
    try:
        saved = await storage.upload_file(
            file=file,
            user_id=ctx.get_user_id(),
            module_context="business_logo",
            context_id=None,
            developer_data={"business_id": business_id, "type": "logo"},
            is_temporary=False,
            expires_in_days=3650,
            business_id=business_id,
            check_storage_limit=True,
        )
    except HTTPException as e:
        # اگر خطای محدودیت ذخیره‌سازی باشد، جزئیات را برمی‌گردانیم
        if e.status_code == 400 and isinstance(e.detail, dict) and e.detail.get("error") == "STORAGE_LIMIT_EXCEEDED":
            error_detail = {
                "success": False,
                "error": {
                    "code": "STORAGE_LIMIT_EXCEEDED",
                    "message": e.detail.get("message", "حجم فایل از محدودیت ذخیره‌سازی تجاوز می‌کند"),
                    "total_limit_gb": e.detail.get("total_limit_gb"),
                    "current_usage_gb": e.detail.get("current_usage_gb"),
                    "available_gb": e.detail.get("available_gb"),
                    "required_gb": e.detail.get("required_gb"),
                    "over_usage_gb": e.detail.get("over_usage_gb"),
                }
            }
            raise HTTPException(status_code=400, detail=error_detail)
        raise

    business.logo_file_id = saved.get("file_id")
    db.commit()

    return success_response(
        {
            "logo_file_id": business.logo_file_id,
            "file": saved,
        },
        request,
        "لوگوی کسب‌وکار با موفقیت ذخیره شد",
    )


@router.get(
    "/{business_id}/logo",
    summary="دریافت لوگوی کسب‌وکار",
    description="بازگرداندن تصویر لوگوی کسب‌وکار به‌صورت فایل برای نمایش در UI یا فاکتور.",
)
@require_business_access("business_id")
async def get_business_logo(
    request: Request,
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("settings", "print")),
):
    business = db.query(Business).filter(Business.id == business_id).first()
    if not business or not getattr(business, "logo_file_id", None):
        raise HTTPException(status_code=404, detail="لوگوی کسب و کار تنظیم نشده است")

    storage = FileStorageService(db)
    file_data = await storage.download_file(UUID(str(business.logo_file_id)))

    filename = file_data.get("filename") or "logo"
    return StreamingResponse(
        io.BytesIO(file_data["content"]),
        media_type=file_data.get("mime_type") or "image/png",
        headers={"Content-Disposition": f'inline; filename="{filename}"'},
    )


@router.post(
    "/{business_id}/stamp",
    summary="آپلود مهر/امضای کسب‌وکار",
    description="آپلود تصویر مهر یا امضای رسمی کسب‌وکار و ذخیره شناسه فایل روی رکورد Business.",
    response_model=SuccessResponse,
)
@require_business_access("business_id")
async def upload_business_stamp(
    request: Request,
    business_id: int,
    file: UploadFile = File(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("settings", "print")),
) -> dict:
    # بررسی وجود کسب‌وکار
    business = db.query(Business).filter(Business.id == business_id).first()
    if not business:
        raise HTTPException(status_code=404, detail="کسب و کار یافت نشد")

    storage = FileStorageService(db)
    
    # حذف فایل قدیمی مهر اگر وجود داشته باشد
    if business.stamp_file_id:
        try:
            old_file_id = UUID(str(business.stamp_file_id))
            await storage.delete_file(old_file_id)
        except Exception:
            pass  # اگر فایل قدیمی وجود نداشت یا خطا رخ داد، ادامه می‌دهیم
    
    try:
        saved = await storage.upload_file(
            file=file,
            user_id=ctx.get_user_id(),
            module_context="business_stamp",
            context_id=None,
            developer_data={"business_id": business_id, "type": "stamp"},
            is_temporary=False,
            expires_in_days=3650,
            business_id=business_id,
            check_storage_limit=True,
        )
    except HTTPException as e:
        # اگر خطای محدودیت ذخیره‌سازی باشد، جزئیات را برمی‌گردانیم
        if e.status_code == 400 and isinstance(e.detail, dict) and e.detail.get("error") == "STORAGE_LIMIT_EXCEEDED":
            error_detail = {
                "success": False,
                "error": {
                    "code": "STORAGE_LIMIT_EXCEEDED",
                    "message": e.detail.get("message", "حجم فایل از محدودیت ذخیره‌سازی تجاوز می‌کند"),
                    "total_limit_gb": e.detail.get("total_limit_gb"),
                    "current_usage_gb": e.detail.get("current_usage_gb"),
                    "available_gb": e.detail.get("available_gb"),
                    "required_gb": e.detail.get("required_gb"),
                    "over_usage_gb": e.detail.get("over_usage_gb"),
                }
            }
            raise HTTPException(status_code=400, detail=error_detail)
        raise

    business.stamp_file_id = saved.get("file_id")
    db.commit()

    return success_response(
        {
            "stamp_file_id": business.stamp_file_id,
            "file": saved,
        },
        request,
        "مهر/امضای کسب‌وکار با موفقیت ذخیره شد",
    )


@router.get(
    "/{business_id}/stamp",
    summary="دریافت مهر/امضای کسب‌وکار",
    description="بازگرداندن تصویر مهر یا امضای کسب‌وکار به‌صورت فایل برای نمایش در UI یا فاکتور.",
)
@require_business_access("business_id")
async def get_business_stamp(
    request: Request,
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("settings", "print")),
):
    business = db.query(Business).filter(Business.id == business_id).first()
    if not business or not getattr(business, "stamp_file_id", None):
        raise HTTPException(status_code=404, detail="مهر/امضای کسب و کار تنظیم نشده است")

    storage = FileStorageService(db)
    file_data = await storage.download_file(UUID(str(business.stamp_file_id)))

    filename = file_data.get("filename") or "stamp"
    return StreamingResponse(
        io.BytesIO(file_data["content"]),
        media_type=file_data.get("mime_type") or "image/png",
        headers={"Content-Disposition": f'inline; filename="{filename}"'},
    )


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


@router.get(
    "/{business_id}/print-settings",
    summary="تنظیمات چاپ فاکتورهای کسب‌وکار",
    description="دریافت تنظیمات چاپ فاکتور (لوگو، مهر، پرداخت‌ها، اقساط و متن انتهایی) به‌صورت پیش‌فرض و به تفکیک نوع فاکتور.",
    response_model=SuccessResponse,
)
@require_business_access("business_id")
def get_business_print_settings_endpoint(
    request: Request,
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("settings", "print")),
) -> dict:
    """دریافت تنظیمات چاپ فاکتورهای یک کسب‌وکار."""
    owner_id = ctx.get_user_id()
    business = get_business_by_id(db, business_id, owner_id)
    if not business:
        raise HTTPException(status_code=404, detail="کسب و کار یافت نشد")

    data = get_business_print_settings(db, business_id)
    return success_response(data, request)


@router.put(
    "/{business_id}/print-settings",
    summary="ویرایش تنظیمات چاپ فاکتورهای کسب‌وکار",
    description="ذخیره تنظیمات چاپ فاکتور (لوگو، مهر، پرداخت‌ها، اقساط و متن انتهایی) به‌صورت پیش‌فرض و به تفکیک نوع فاکتور.",
    response_model=SuccessResponse,
)
@require_business_access("business_id")
def update_business_print_settings_endpoint(
    request: Request,
    business_id: int,
    payload: Dict[str, Any],
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    _: None = Depends(require_business_permission_dep("settings", "print")),
) -> dict:
    """ویرایش تنظیمات چاپ فاکتورهای یک کسب‌وکار."""
    owner_id = ctx.get_user_id()
    business = get_business_by_id(db, business_id, owner_id)
    if not business:
        raise HTTPException(status_code=404, detail="کسب و کار یافت نشد")

    updated = update_business_print_settings(db, business_id, payload or {})
    return success_response(updated, request, "تنظیمات چاپ با موفقیت ذخیره شد")
