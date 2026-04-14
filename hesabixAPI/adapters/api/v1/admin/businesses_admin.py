from __future__ import annotations

from typing import Dict, Any, Optional
from decimal import Decimal
import structlog

from fastapi import APIRouter, Depends, Request, Body, Path
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, format_datetime_fields
from app.core.permissions import require_superadmin
from app.services.business_service import get_all_businesses_admin
from app.services.wallet_service import get_wallet_overview, add_gift_balance_admin

logger = structlog.get_logger()


router = APIRouter(prefix="/admin/businesses", tags=["admin-businesses"])


@router.post(
    "/list",
    summary="لیست تمام کسب و کارها (سوپر ادمین)",
    description="دریافت لیست تمام کسب و کارهای سیستم با قابلیت فیلتر، جستجو و صفحه‌بندی (فقط برای سوپر ادمین)",
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
                                    "owner": {
                                        "id": 1,
                                        "email": "owner@example.com",
                                        "mobile": "09123456789",
                                        "first_name": "احمد",
                                        "last_name": "احمدی",
                                        "full_name": "احمد احمدی"
                                    },
                                    "address": "تهران، خیابان ولیعصر",
                                    "phone": "02112345678",
                                    "mobile": "09123456789",
                                    "national_id": "1234567890",
                                    "province": "تهران",
                                    "city": "تهران",
                                    "created_at": "1403/01/01 00:00:00"
                                }
                            ],
                            "pagination": {
                                "total": 100,
                                "page": 1,
                                "per_page": 10,
                                "total_pages": 10,
                                "has_next": True,
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
            "description": "دسترسی غیرمجاز - فقط سوپر ادمین"
        }
    }
)
@require_superadmin()
async def list_all_businesses_admin(
    request: Request,
    payload: Dict[str, Any] = Body(default_factory=dict),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    """دریافت لیست تمام کسب و کارهای سیستم (فقط سوپر ادمین)"""
    
    # استخراج QueryInfo از payload
    query_info_dict = {
        "take": payload.get("take", 20),
        "skip": payload.get("skip", 0),
        "sort_by": payload.get("sort_by", "created_at"),
        "sort_desc": payload.get("sort_desc", True),
        "search": payload.get("search"),
    }
    
    # ساخت query_dict از QueryInfo و فیلترهای اضافی
    query_dict = {
        "take": query_info_dict["take"],
        "skip": query_info_dict["skip"],
        "sort_by": query_info_dict["sort_by"],
        "sort_desc": query_info_dict["sort_desc"],
        "search": query_info_dict["search"],
    }
    
    # استخراج فیلترهای اضافی از payload
    for key in ["business_type", "business_field", "province", "city"]:
        if key in payload and payload.get(key) is not None:
            query_dict[key] = payload.get(key)
    
    businesses = get_all_businesses_admin(db, query_dict)
    
    # تبدیل به فرمت مورد انتظار DataTableWidget
    items = businesses.get("items", [])
    pagination = businesses.get("pagination", {})
    
    # فرمت تاریخ‌ها (format_datetime_fields برای dictionary کار می‌کند)
    formatted_items = []
    for item in items:
        formatted_item = format_datetime_fields(item, request)
        formatted_items.append(formatted_item)
    
    # ساخت پاسخ در فرمت DataTableWidget
    response_data = {
        "items": formatted_items,
        "total": pagination.get("total", 0),
        "page": pagination.get("page", 1),
        "limit": pagination.get("per_page", query_info_dict["take"]),
        "total_pages": pagination.get("total_pages", 1),
    }
    
    return success_response(response_data, request)


@router.get(
    "/{business_id}/wallet",
    summary="اطلاعات کیف‌پول کسب‌وکار (سوپر ادمین)",
    description="دریافت اطلاعات کیف‌پول کسب‌وکار شامل موجودی قابل استفاده، موجودی در انتظار و وضعیت (فقط برای سوپر ادمین)",
    responses={
        200: {
            "description": "اطلاعات کیف‌پول با موفقیت دریافت شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "message": "اطلاعات کیف‌پول دریافت شد",
                        "data": {
                            "business_id": 1,
                            "available_balance": 1000000.0,
                            "pending_balance": 0.0,
                            "status": "active",
                            "base_currency_code": "IRR",
                            "base_currency_id": 1
                        }
                    }
                }
            }
        },
        401: {
            "description": "کاربر احراز هویت نشده است"
        },
        403: {
            "description": "دسترسی غیرمجاز - فقط سوپر ادمین"
        },
        404: {
            "description": "کسب‌وکار یافت نشد"
        }
    }
)
@require_superadmin()
def get_business_wallet_admin(
    request: Request,
    business_id: int = Path(..., description="شناسه کسب‌وکار"),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    """دریافت اطلاعات کیف‌پول کسب‌وکار (فقط سوپر ادمین)"""
    data = get_wallet_overview(db, business_id)
    formatted_data = format_datetime_fields(data, request)
    return success_response(formatted_data, request)


@router.post(
    "/{business_id}/wallet/add-gift",
    summary="افزودن موجودی هدیه به کیف‌پول (سوپر ادمین)",
    description="افزودن موجودی هدیه به کیف‌پول کسب‌وکار توسط مدیر سیستم. این عملیات یک سند حسابداری ایجاد می‌کند (فقط برای سوپر ادمین)",
    responses={
        200: {
            "description": "موجودی هدیه با موفقیت اضافه شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "message": "موجودی هدیه با موفقیت اضافه شد",
                        "data": {
                            "transaction_id": 123,
                            "business_id": 1,
                            "amount": 500000.0,
                            "available_balance": 1500000.0,
                            "pending_balance": 0.0,
                            "status": "active",
                            "document_id": 456
                        }
                    }
                }
            }
        },
        400: {
            "description": "مبلغ نامعتبر است"
        },
        401: {
            "description": "کاربر احراز هویت نشده است"
        },
        403: {
            "description": "دسترسی غیرمجاز - فقط سوپر ادمین"
        },
        404: {
            "description": "کسب‌وکار یافت نشد"
        }
    }
)
@require_superadmin()
def add_gift_balance_business_admin(
    request: Request,
    business_id: int = Path(..., description="شناسه کسب‌وکار"),
    payload: Dict[str, Any] = Body(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    """افزودن موجودی هدیه به کیف‌پول کسب‌وکار (فقط سوپر ادمین)"""
    logger.info(
        "add_gift_balance_endpoint_start",
        business_id=business_id,
        payload=payload,
        user_id=ctx.get_user_id()
    )
    
    amount = payload.get("amount")
    if amount is None:
        logger.error("add_gift_balance_endpoint_missing_amount", payload=payload)
        from app.core.responses import ApiError
        raise ApiError("INVALID_AMOUNT", "مبلغ الزامی است", http_status=400)
    
    amount = Decimal(str(amount))
    description = payload.get("description")
    reason = payload.get("reason")
    user_id = ctx.get_user_id()
    
    logger.debug(
        "add_gift_balance_endpoint_calling_service",
        business_id=business_id,
        user_id=user_id,
        amount=float(amount),
        description=description,
        reason=reason
    )
    
    try:
        data = add_gift_balance_admin(
            db=db,
            business_id=business_id,
            user_id=user_id,
            amount=amount,
            description=description,
            reason=reason,
        )
        
        logger.info(
            "add_gift_balance_endpoint_service_success",
            business_id=business_id,
            transaction_id=data.get("transaction_id"),
            final_balance=data.get("available_balance")
        )
        
        # بررسی وضعیت session قبل از commit
        logger.debug(
            "add_gift_balance_endpoint_session_status",
            is_active=db.is_active,
            in_transaction=db.in_transaction() if hasattr(db, 'in_transaction') else None,
            dirty=len(db.dirty),
            new=len(db.new),
            deleted=len(db.deleted)
        )
        
        # Commit تغییرات
        try:
            db.commit()
            logger.info(
                "add_gift_balance_endpoint_commit_success",
                business_id=business_id,
                transaction_id=data.get("transaction_id")
            )
        except Exception as commit_error:
            logger.error(
                "add_gift_balance_endpoint_commit_error",
                error=str(commit_error),
                error_type=type(commit_error).__name__,
                business_id=business_id,
                exc_info=True
            )
            db.rollback()
            raise
        
        # بررسی مجدد بعد از commit
        logger.debug(
            "add_gift_balance_endpoint_after_commit",
            business_id=business_id,
            is_active=db.is_active
        )
        
        formatted_data = format_datetime_fields(data, request)
        logger.info(
            "add_gift_balance_endpoint_completed",
            business_id=business_id,
            transaction_id=data.get("transaction_id"),
            final_balance=data.get("available_balance")
        )
        
        return success_response(formatted_data, request, message="موجودی هدیه با موفقیت اضافه شد")
    except Exception as e:
        logger.error(
            "add_gift_balance_endpoint_error",
            error=str(e),
            error_type=type(e).__name__,
            business_id=business_id,
            exc_info=True
        )
        db.rollback()
        raise

