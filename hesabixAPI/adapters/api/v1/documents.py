"""
API endpoints برای مدیریت اسناد حسابداری (General Accounting Documents)
"""

from typing import Any, Dict
from fastapi import APIRouter, Depends, Request, Body, Query
from fastapi.responses import Response
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access, require_business_management_dep
from app.core.responses import success_response, format_datetime_fields, ApiError
from app.services.document_service import (
    list_documents,
    get_document,
    delete_document,
    delete_multiple_documents,
    get_document_types_summary,
    export_documents_excel,
    create_manual_document,
    update_manual_document,
)
from adapters.api.v1.schema_models.document import (
    CreateManualDocumentRequest,
    UpdateManualDocumentRequest,
)


router = APIRouter(tags=["documents"])


@router.post(
    "/businesses/{business_id}/documents",
    summary="لیست اسناد حسابداری",
    description="دریافت لیست تمام اسناد حسابداری (عمومی و اتوماتیک) با فیلتر و صفحه‌بندی",
)
@require_business_access("business_id")
async def list_documents_endpoint(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """
    لیست اسناد حسابداری
    
    Body parameters:
        - document_type: نوع سند (expense, income, receipt, payment, transfer, manual)
        - fiscal_year_id: شناسه سال مالی
        - from_date: از تاریخ (ISO format)
        - to_date: تا تاریخ (ISO format)
        - currency_id: شناسه ارز
        - is_proforma: پیش‌فاکتور یا قطعی
        - search: جستجو در کد سند و توضیحات
        - sort_by: فیلد مرتب‌سازی (document_date, code, document_type, created_at)
        - sort_desc: ترتیب نزولی (true/false)
        - take: تعداد رکورد (1-1000)
        - skip: تعداد رکورد صرف‌نظر شده
    """
    query_dict: Dict[str, Any] = {
        "take": body.get("take", 50),
        "skip": body.get("skip", 0),
        "sort_by": body.get("sort_by", "document_date"),
        "sort_desc": body.get("sort_desc", True),
        "search": body.get("search"),
    }

    # فیلترهای اضافی
    for key in ["document_type", "from_date", "to_date", "currency_id", "is_proforma"]:
        if key in body:
            query_dict[key] = body[key]

    # سال مالی از header
    try:
        fy_header = request.headers.get("X-Fiscal-Year-ID")
        if fy_header:
            query_dict["fiscal_year_id"] = int(fy_header)
        elif "fiscal_year_id" in body:
            query_dict["fiscal_year_id"] = body["fiscal_year_id"]
    except Exception:
        pass

    result = list_documents(db, business_id, query_dict)
    
    # فرمت کردن تاریخ‌ها
    result["items"] = [
        format_datetime_fields(item, request) for item in result.get("items", [])
    ]
    
    return success_response(
        data=result,
        request=request,
        message="DOCUMENTS_LIST_FETCHED"
    )


@router.get(
    "/documents/{document_id}",
    summary="جزئیات سند حسابداری",
    description="دریافت جزئیات کامل یک سند شامل تمام سطرهای سند",
)
async def get_document_endpoint(
    request: Request,
    document_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """دریافت جزئیات کامل سند"""
    result = get_document(db, document_id)
    
    if not result:
        raise ApiError(
            "DOCUMENT_NOT_FOUND",
            "Document not found",
            http_status=404
        )
    
    # بررسی دسترسی
    business_id = result.get("business_id")
    if business_id and not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "Access denied", http_status=403)
    
    return success_response(
        data=format_datetime_fields(result, request),
        request=request,
        message="DOCUMENT_DETAILS_FETCHED"
    )


@router.delete(
    "/documents/{document_id}",
    summary="حذف سند حسابداری",
    description="حذف یک سند حسابداری (فقط اسناد عمومی manual قابل حذف هستند)",
)
async def delete_document_endpoint(
    request: Request,
    document_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_management_dep),
):
    """
    حذف سند حسابداری
    
    توجه: فقط اسناد عمومی (manual) قابل حذف هستند.
    اسناد اتوماتیک (expense, income, receipt, payment, ...) باید از منبع اصلی حذف شوند.
    """
    # دریافت سند برای بررسی دسترسی
    doc = get_document(db, document_id)
    if not doc:
        raise ApiError("DOCUMENT_NOT_FOUND", "Document not found", http_status=404)
    
    business_id = doc.get("business_id")
    if business_id and not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "Access denied", http_status=403)
    
    # حذف سند
    success = delete_document(db, document_id)
    
    return success_response(
        data={"deleted": success, "document_id": document_id},
        request=request,
        message="DOCUMENT_DELETED"
    )


@router.post(
    "/documents/bulk-delete",
    summary="حذف گروهی اسناد",
    description="حذف گروهی اسناد حسابداری (فقط اسناد manual حذف می‌شوند)",
)
async def bulk_delete_documents_endpoint(
    request: Request,
    body: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_management_dep),
):
    """
    حذف گروهی اسناد
    
    Body:
        document_ids: لیست شناسه‌های سند
    
    توجه: اسناد اتوماتیک نادیده گرفته می‌شوند و باید از منبع اصلی حذف شوند.
    """
    document_ids = body.get("document_ids", [])
    if not document_ids:
        raise ApiError(
            "INVALID_REQUEST",
            "document_ids is required",
            http_status=400
        )
    
    result = delete_multiple_documents(db, document_ids)
    
    return success_response(
        data=result,
        request=request,
        message="DOCUMENTS_BULK_DELETED"
    )


@router.get(
    "/businesses/{business_id}/documents/types-summary",
    summary="خلاصه آماری انواع اسناد",
    description="دریافت خلاصه آماری تعداد هر نوع سند",
)
@require_business_access("business_id")
async def get_document_types_summary_endpoint(
    request: Request,
    business_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """دریافت خلاصه آماری انواع اسناد"""
    summary = get_document_types_summary(db, business_id)
    
    total = sum(summary.values())
    
    return success_response(
        data={"summary": summary, "total": total},
        request=request,
        message="DOCUMENT_TYPES_SUMMARY_FETCHED"
    )


@router.post(
    "/businesses/{business_id}/documents/export/excel",
    summary="خروجی Excel اسناد",
    description="دریافت فایل Excel لیست اسناد حسابداری",
)
@require_business_access("business_id")
async def export_documents_excel_endpoint(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(default={}),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """
    خروجی Excel لیست اسناد
    
    Body: فیلترهای مشابه لیست اسناد
    """
    filters = {}
    
    # فیلترها
    for key in ["document_type", "from_date", "to_date", "currency_id", "is_proforma"]:
        if key in body:
            filters[key] = body[key]
    
    # سال مالی از header
    try:
        fy_header = request.headers.get("X-Fiscal-Year-ID")
        if fy_header:
            filters["fiscal_year_id"] = int(fy_header)
        elif "fiscal_year_id" in body:
            filters["fiscal_year_id"] = body["fiscal_year_id"]
    except Exception:
        pass
    
    excel_data = export_documents_excel(db, business_id, filters)
    
    return Response(
        content=excel_data,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={
            "Content-Disposition": f"attachment; filename=documents_{business_id}.xlsx"
        }
    )


@router.get(
    "/documents/{document_id}/pdf",
    summary="PDF یک سند",
    description="دریافت فایل PDF یک سند حسابداری",
)
async def get_document_pdf_endpoint(
    request: Request,
    document_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """
    PDF یک سند
    
    TODO: پیاده‌سازی تولید PDF برای سند
    """
    # بررسی دسترسی
    doc = get_document(db, document_id)
    if not doc:
        raise ApiError("DOCUMENT_NOT_FOUND", "Document not found", http_status=404)
    
    business_id = doc.get("business_id")
    if business_id and not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "Access denied", http_status=403)
    
    # TODO: تولید PDF
    raise ApiError(
        "NOT_IMPLEMENTED",
        "PDF generation is not implemented yet",
        http_status=501
    )


@router.post(
    "/businesses/{business_id}/documents/manual",
    summary="ایجاد سند حسابداری دستی",
    description="ایجاد یک سند حسابداری دستی جدید با سطرهای مورد نظر",
)
@require_business_access("business_id")
async def create_manual_document_endpoint(
    request: Request,
    business_id: int,
    body: CreateManualDocumentRequest,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_management_dep),
):
    """
    ایجاد سند حسابداری دستی
    
    Body:
        - code: کد سند (اختیاری - خودکار تولید می‌شود)
        - document_date: تاریخ سند
        - fiscal_year_id: شناسه سال مالی (اختیاری - اگر نباشد، سال مالی فعال استفاده می‌شود)
        - currency_id: شناسه ارز
        - is_proforma: پیش‌فاکتور یا قطعی
        - description: توضیحات سند
        - lines: سطرهای سند (حداقل 2 سطر)
        - extra_info: اطلاعات اضافی
    
    نکته: اگر fiscal_year_id ارسال نشود، سیستم به ترتیب زیر عمل می‌کند:
        1. از X-Fiscal-Year-ID header می‌خواند
        2. سال مالی فعال (is_last=True) را انتخاب می‌کند
        3. اگر سال مالی فعال نداشت، خطا برمی‌گرداند
    
    اعتبارسنجی‌ها:
        - سند باید متوازن باشد (مجموع بدهکار = مجموع بستانکار)
        - حداقل 2 سطر داشته باشد
        - هر سطر باید یا بدهکار یا بستانکار داشته باشد (نه هر دو صفر)
    """
    # دریافت سال مالی از header یا body
    fiscal_year_id = body.fiscal_year_id
    if not fiscal_year_id:
        try:
            fy_header = request.headers.get("X-Fiscal-Year-ID")
            if fy_header:
                fiscal_year_id = int(fy_header)
        except Exception:
            pass
    
    # اگر fiscal_year_id نبود، سال مالی فعال (is_last=True) را پیدا کن
    if not fiscal_year_id:
        from adapters.db.models.fiscal_year import FiscalYear
        active_fy = db.query(FiscalYear).filter(
            FiscalYear.business_id == business_id,
            FiscalYear.is_last == True
        ).first()
        
        if active_fy:
            fiscal_year_id = active_fy.id
        else:
            raise ApiError(
                "FISCAL_YEAR_REQUIRED",
                "No active fiscal year found for this business. Please create a fiscal year first.",
                http_status=400
            )
    
    # تبدیل Pydantic model به dict
    data = body.model_dump()
    data["lines"] = [line.model_dump() for line in body.lines]
    
    # ایجاد سند
    result = create_manual_document(
        db=db,
        business_id=business_id,
        fiscal_year_id=fiscal_year_id,
        user_id=ctx.get_user_id(),
        data=data,
    )
    
    return success_response(
        data=format_datetime_fields(result, request),
        request=request,
        message="MANUAL_DOCUMENT_CREATED"
    )


@router.put(
    "/documents/{document_id}",
    summary="ویرایش سند حسابداری دستی",
    description="ویرایش یک سند حسابداری دستی (فقط اسناد manual قابل ویرایش هستند)",
)
async def update_manual_document_endpoint(
    request: Request,
    document_id: int,
    body: UpdateManualDocumentRequest,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_management_dep),
):
    """
    ویرایش سند حسابداری دستی
    
    Body:
        - code: کد سند
        - document_date: تاریخ سند
        - currency_id: شناسه ارز
        - is_proforma: پیش‌فاکتور یا قطعی
        - description: توضیحات سند
        - lines: سطرهای سند (اختیاری - اگر ارسال شود جایگزین سطرهای قبلی می‌شود)
        - extra_info: اطلاعات اضافی
    
    توجه:
        - فقط اسناد manual قابل ویرایش هستند
        - اسناد اتوماتیک باید از منبع اصلی ویرایش شوند
    """
    # بررسی دسترسی
    doc = get_document(db, document_id)
    if not doc:
        raise ApiError("DOCUMENT_NOT_FOUND", "Document not found", http_status=404)
    
    business_id = doc.get("business_id")
    if business_id and not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "Access denied", http_status=403)
    
    # تبدیل Pydantic model به dict (فقط فیلدهای set شده)
    data = body.model_dump(exclude_unset=True)
    if "lines" in data and data["lines"] is not None:
        data["lines"] = [line.model_dump() for line in body.lines]
    
    # ویرایش سند
    result = update_manual_document(
        db=db,
        document_id=document_id,
        data=data,
    )
    
    return success_response(
        data=format_datetime_fields(result, request),
        request=request,
        message="MANUAL_DOCUMENT_UPDATED"
    )

