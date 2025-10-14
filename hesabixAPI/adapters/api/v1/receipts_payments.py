"""
API endpoints برای دریافت و پرداخت (Receipt & Payment)
"""

from typing import Any, Dict
from fastapi import APIRouter, Depends, Request, Body
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, format_datetime_fields, ApiError
from app.core.permissions import require_business_management_dep, require_business_access
from adapters.api.v1.schemas import QueryInfo
from app.services.receipt_payment_service import (
    create_receipt_payment,
    get_receipt_payment,
    list_receipts_payments,
    delete_receipt_payment,
)


router = APIRouter(tags=["receipts-payments"])


@router.post(
    "/businesses/{business_id}/receipts-payments",
    summary="لیست اسناد دریافت و پرداخت",
    description="دریافت لیست اسناد دریافت و پرداخت با فیلتر و جستجو",
)
@require_business_access("business_id")
async def list_receipts_payments_endpoint(
    request: Request,
    business_id: int,
    query_info: QueryInfo = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """
    لیست اسناد دریافت و پرداخت
    
    پارامترهای اضافی در body:
    - document_type: "receipt" یا "payment" (اختیاری)
    - from_date: تاریخ شروع (اختیاری)
    - to_date: تاریخ پایان (اختیاری)
    """
    query_dict: Dict[str, Any] = {
        "take": query_info.take,
        "skip": query_info.skip,
        "sort_by": query_info.sort_by,
        "sort_desc": query_info.sort_desc,
        "search": query_info.search,
    }
    
    # دریافت پارامترهای اضافی از body
    try:
        body_json = await request.json()
        if isinstance(body_json, dict):
            for key in ["document_type", "from_date", "to_date"]:
                if key in body_json:
                    query_dict[key] = body_json[key]
    except Exception:
        pass
    
    result = list_receipts_payments(db, business_id, query_dict)
    result["items"] = [format_datetime_fields(item, request) for item in result.get("items", [])]
    
    return success_response(
        data=result,
        request=request,
        message="RECEIPTS_PAYMENTS_LIST_FETCHED"
    )


@router.post(
    "/businesses/{business_id}/receipts-payments/create",
    summary="ایجاد سند دریافت یا پرداخت",
    description="ایجاد سند دریافت یا پرداخت جدید",
)
@require_business_access("business_id")
async def create_receipt_payment_endpoint(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_management_dep),
):
    """
    ایجاد سند دریافت یا پرداخت
    
    Body باید شامل موارد زیر باشد:
    {
        "document_type": "receipt" | "payment",
        "document_date": "2025-01-15T10:30:00",
        "currency_id": 1,
        "person_lines": [
            {
                "person_id": 123,
                "person_name": "علی احمدی",
                "amount": 1000000,
                "description": "توضیحات (اختیاری)"
            }
        ],
        "account_lines": [
            {
                "account_id": 456,
                "amount": 1000000,
                "transaction_type": "bank" | "cash_register" | "petty_cash" | "check",
                "transaction_date": "2025-01-15T10:30:00",
                "commission": 5000,  // اختیاری
                "description": "توضیحات (اختیاری)",
                // اطلاعات اضافی بر اساس نوع تراکنش:
                "bank_id": "123",  // برای نوع bank
                "bank_name": "بانک ملی",
                "cash_register_id": "456",  // برای نوع cash_register
                "cash_register_name": "صندوق اصلی",
                "petty_cash_id": "789",  // برای نوع petty_cash
                "petty_cash_name": "تنخواهگردان فروش",
                "check_id": "101",  // برای نوع check
                "check_number": "123456"
            }
        ],
        "extra_info": {}  // اختیاری
    }
    """
    created = create_receipt_payment(db, business_id, ctx.get_user_id(), body)
    
    return success_response(
        data=format_datetime_fields(created, request),
        request=request,
        message="RECEIPT_PAYMENT_CREATED"
    )


@router.get(
    "/receipts-payments/{document_id}",
    summary="جزئیات سند دریافت/پرداخت",
    description="دریافت جزئیات یک سند دریافت یا پرداخت",
)
async def get_receipt_payment_endpoint(
    request: Request,
    document_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """دریافت جزئیات سند"""
    result = get_receipt_payment(db, document_id)
    
    if not result:
        raise ApiError(
            "DOCUMENT_NOT_FOUND",
            "Receipt/Payment document not found",
            http_status=404
        )
    
    # بررسی دسترسی
    business_id = result.get("business_id")
    if business_id and not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "Access denied", http_status=403)
    
    return success_response(
        data=format_datetime_fields(result, request),
        request=request,
        message="RECEIPT_PAYMENT_DETAILS"
    )


@router.delete(
    "/receipts-payments/{document_id}",
    summary="حذف سند دریافت/پرداخت",
    description="حذف یک سند دریافت یا پرداخت",
)
async def delete_receipt_payment_endpoint(
    request: Request,
    document_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_management_dep),
):
    """حذف سند"""
    # دریافت سند برای بررسی دسترسی
    result = get_receipt_payment(db, document_id)
    
    if result:
        business_id = result.get("business_id")
        if business_id and not ctx.can_access_business(business_id):
            raise ApiError("FORBIDDEN", "Access denied", http_status=403)
    
    ok = delete_receipt_payment(db, document_id)
    
    if not ok:
        raise ApiError(
            "DOCUMENT_NOT_FOUND",
            "Receipt/Payment document not found",
            http_status=404
        )
    
    return success_response(
        data=None,
        request=request,
        message="RECEIPT_PAYMENT_DELETED"
    )

