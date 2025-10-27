"""
API endpoints برای هزینه و درآمد (Expense & Income)
"""

from typing import Any, Dict
from fastapi import APIRouter, Depends, Request, Body
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_management_dep, require_business_access
from app.core.responses import success_response, format_datetime_fields
from adapters.api.v1.schemas import QueryInfo
from app.services.expense_income_service import (
    create_expense_income,
    list_expense_income,
    get_expense_income,
    update_expense_income,
    delete_expense_income,
    delete_multiple_expense_income,
)


router = APIRouter(tags=["expense-income"])


@router.post(
    "/businesses/{business_id}/expense-income/create",
    summary="ایجاد سند هزینه یا درآمد",
    description="ایجاد سند هزینه/درآمد با چند سطر حساب و چند طرف‌حساب",
)
@require_business_access("business_id")
async def create_expense_income_endpoint(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_management_dep),
):
    created = create_expense_income(db, business_id, ctx.get_user_id(), body)
    return success_response(
        data=format_datetime_fields(created, request),
        request=request,
        message="EXPENSE_INCOME_CREATED",
    )


@router.post(
    "/businesses/{business_id}/expense-income",
    summary="لیست اسناد هزینه/درآمد",
    description="دریافت لیست اسناد هزینه/درآمد با جستجو و صفحه‌بندی",
)
@require_business_access("business_id")
async def list_expense_income_endpoint(
    request: Request,
    business_id: int,
    query_info: QueryInfo = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    query_dict: Dict[str, Any] = {
        "take": query_info.take,
        "skip": query_info.skip,
        "sort_by": query_info.sort_by,
        "sort_desc": query_info.sort_desc,
        "search": query_info.search,
    }

    # Read extra body filters
    try:
        body_json = await request.json()
        if isinstance(body_json, dict):
            for key in ["document_type", "from_date", "to_date"]:
                if key in body_json:
                    query_dict[key] = body_json[key]
    except Exception:
        pass

    # Fiscal year from header
    try:
        fy_header = request.headers.get("X-Fiscal-Year-ID")
        if fy_header:
            query_dict["fiscal_year_id"] = int(fy_header)
    except Exception:
        pass

    result = list_expense_income(db, business_id, query_dict)
    result["items"] = [format_datetime_fields(item, request) for item in result.get("items", [])]
    return success_response(data=result, request=request, message="EXPENSE_INCOME_LIST_FETCHED")


@router.get(
    "/expense-income/{document_id}",
    summary="جزئیات سند هزینه/درآمد",
    description="دریافت جزئیات یک سند هزینه یا درآمد",
)
async def get_expense_income_endpoint(
    request: Request,
    document_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """دریافت جزئیات سند"""
    result = get_expense_income(db, document_id)
    
    if not result:
        from app.core.responses import ApiError
        raise ApiError(
            "DOCUMENT_NOT_FOUND",
            "Expense/Income document not found",
            http_status=404
        )
    
    # بررسی دسترسی
    business_id = result.get("business_id")
    if business_id and not ctx.can_access_business(business_id):
        from app.core.responses import ApiError
        raise ApiError("FORBIDDEN", "Access denied", http_status=403)
    
    return success_response(
        data=format_datetime_fields(result, request),
        request=request,
        message="EXPENSE_INCOME_DETAILS"
    )


@router.put(
    "/expense-income/{document_id}",
    summary="ویرایش سند هزینه/درآمد",
    description="ویرایش یک سند هزینه یا درآمد",
)
async def update_expense_income_endpoint(
    request: Request,
    document_id: int,
    body: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_management_dep),
):
    """ویرایش سند هزینه/درآمد"""
    updated = update_expense_income(db, document_id, ctx.get_user_id(), body)
    
    return success_response(
        data=format_datetime_fields(updated, request),
        request=request,
        message="EXPENSE_INCOME_UPDATED"
    )


@router.delete(
    "/expense-income/{document_id}",
    summary="حذف سند هزینه/درآمد",
    description="حذف یک سند هزینه یا درآمد",
)
async def delete_expense_income_endpoint(
    request: Request,
    document_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_management_dep),
):
    """حذف سند هزینه/درآمد"""
    success = delete_expense_income(db, document_id)
    
    if not success:
        from app.core.responses import ApiError
        raise ApiError("DELETE_FAILED", "Failed to delete document", http_status=500)
    
    return success_response(
        data={"deleted": True},
        request=request,
        message="EXPENSE_INCOME_DELETED"
    )


@router.post(
    "/expense-income/bulk-delete",
    summary="حذف گروهی اسناد هزینه/درآمد",
    description="حذف چندین سند هزینه یا درآمد",
)
async def delete_multiple_expense_income_endpoint(
    request: Request,
    body: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_management_dep),
):
    """حذف گروهی اسناد"""
    document_ids = body.get("document_ids", [])
    if not document_ids:
        from app.core.responses import ApiError
        raise ApiError("INVALID_REQUEST", "document_ids is required", http_status=400)
    
    success = delete_multiple_expense_income(db, document_ids)
    
    if not success:
        from app.core.responses import ApiError
        raise ApiError("DELETE_FAILED", "Failed to delete documents", http_status=500)
    
    return success_response(
        data={"deleted_count": len(document_ids)},
        request=request,
        message="EXPENSE_INCOME_BULK_DELETED"
    )


@router.post(
    "/businesses/{business_id}/expense-income/export/excel",
    summary="خروجی Excel اسناد هزینه/درآمد",
    description="دریافت فایل Excel لیست اسناد هزینه/درآمد",
)
@require_business_access("business_id")
async def export_expense_income_excel_endpoint(
    request: Request,
    business_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """خروجی Excel"""
    from app.services.expense_income_service import export_expense_income_excel
    from fastapi.responses import Response
    
    # دریافت پارامترهای فیلتر
    query_dict = {}
    try:
        body_json = await request.json()
        if isinstance(body_json, dict):
            for key in ["document_type", "from_date", "to_date"]:
                if key in body_json:
                    query_dict[key] = body_json[key]
    except Exception:
        pass
    
    # سال مالی از هدر
    try:
        fy_header = request.headers.get("X-Fiscal-Year-ID")
        if fy_header:
            query_dict["fiscal_year_id"] = int(fy_header)
    except Exception:
        pass
    
    excel_data = export_expense_income_excel(db, business_id, query_dict)
    
    return Response(
        content=excel_data,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f"attachment; filename=expense_income_{business_id}.xlsx"}
    )


@router.post(
    "/businesses/{business_id}/expense-income/export/pdf",
    summary="خروجی PDF اسناد هزینه/درآمد",
    description="دریافت فایل PDF لیست اسناد هزینه/درآمد",
)
@require_business_access("business_id")
async def export_expense_income_pdf_endpoint(
    request: Request,
    business_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """خروجی PDF"""
    from app.services.expense_income_service import export_expense_income_pdf
    from fastapi.responses import Response
    
    # دریافت پارامترهای فیلتر
    query_dict = {}
    try:
        body_json = await request.json()
        if isinstance(body_json, dict):
            for key in ["document_type", "from_date", "to_date"]:
                if key in body_json:
                    query_dict[key] = body_json[key]
    except Exception:
        pass
    
    # سال مالی از هدر
    try:
        fy_header = request.headers.get("X-Fiscal-Year-ID")
        if fy_header:
            query_dict["fiscal_year_id"] = int(fy_header)
    except Exception:
        pass
    
    pdf_data = export_expense_income_pdf(db, business_id, query_dict)
    
    return Response(
        content=pdf_data,
        media_type="application/pdf",
        headers={"Content-Disposition": f"attachment; filename=expense_income_{business_id}.pdf"}
    )


@router.get(
    "/expense-income/{document_id}/pdf",
    summary="PDF یک سند هزینه/درآمد",
    description="دریافت فایل PDF یک سند هزینه یا درآمد",
)
async def get_expense_income_pdf_endpoint(
    request: Request,
    document_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """PDF یک سند"""
    from app.services.expense_income_service import generate_expense_income_pdf
    from fastapi.responses import Response
    
    # بررسی دسترسی
    doc = get_expense_income(db, document_id)
    if not doc:
        from app.core.responses import ApiError
        raise ApiError("DOCUMENT_NOT_FOUND", "Document not found", http_status=404)
    
    business_id = doc.get("business_id")
    if business_id and not ctx.can_access_business(business_id):
        from app.core.responses import ApiError
        raise ApiError("FORBIDDEN", "Access denied", http_status=403)
    
    pdf_data = generate_expense_income_pdf(db, document_id)
    
    return Response(
        content=pdf_data,
        media_type="application/pdf",
        headers={"Content-Disposition": f"attachment; filename=expense_income_{document_id}.pdf"}
    )


