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
from app.services.pdf.template_renderer import render_template


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
    """خروجی PDF (با پشتیبانی قالب سفارشی expense_income/list)"""
    from fastapi.responses import Response
    from weasyprint import HTML
    from weasyprint.text.fonts import FontConfiguration
    from app.core.i18n import negotiate_locale
    from html import escape
    import datetime, json
    # دریافت پارامترهای فیلتر و تنظیمات
    try:
        body = await request.json()
    except Exception:
        body = {}
    # ساخت query برای لیست
    query_dict = {
        "take": int(body.get("take", 1000)),
        "skip": int(body.get("skip", 0)),
        "sort_by": body.get("sort_by"),
        "sort_desc": bool(body.get("sort_desc", False)),
        "search": body.get("search"),
        "search_fields": body.get("search_fields"),
        "filters": body.get("filters"),
        "document_type": body.get("document_type"),
        "from_date": body.get("from_date"),
        "to_date": body.get("to_date"),
    }
    # سال مالی از هدر
    try:
        fy_header = request.headers.get("X-Fiscal-Year-ID")
        if fy_header:
            query_dict["fiscal_year_id"] = int(fy_header)
        elif body.get("fiscal_year_id") is not None:
            query_dict["fiscal_year_id"] = int(body.get("fiscal_year_id"))
    except Exception:
        pass
    # دریافت داده‌ها
    from app.services.expense_income_service import list_expense_income
    from adapters.db.models.business import Business
    from app.core.responses import format_datetime_fields
    result = list_expense_income(db, business_id, query_dict)
    items = result.get("items", [])
    items = [format_datetime_fields(item, request) for item in items]
    # ستون‌ها
    headers: list[str] = []
    keys: list[str] = []
    export_columns = body.get("export_columns")
    if export_columns:
        for col in export_columns:
            key = col.get("key")
            label = col.get("label", key)
            if key:
                keys.append(str(key))
                headers.append(str(label))
    else:
        default_columns = [
            ("code", "کد سند"),
            ("document_type_name", "نوع سند"),
            ("document_date", "تاریخ سند"),
            ("total_amount", "مبلغ کل"),
            ("created_by_name", "ایجادکننده"),
            ("registered_at", "تاریخ ثبت"),
        ]
        for key, label in default_columns:
            if items and key in items[0]:
                keys.append(key)
                headers.append(label)
    # اطلاعات کسب‌وکار
    business_name = ""
    try:
        b = db.query(Business).filter(Business.id == business_id).first()
        if b is not None:
            business_name = b.name or ""
    except Exception:
        business_name = ""
    # Locale
    locale = negotiate_locale(request.headers.get("Accept-Language"))
    is_fa = locale == "fa"
    now = datetime.datetime.now().strftime('%Y/%m/%d %H:%M')
    title_text = "لیست اسناد هزینه/درآمد" if is_fa else "Expense/Income List"
    label_biz = "کسب و کار" if is_fa else "Business"
    label_date = "تاریخ تولید" if is_fa else "Generated Date"
    footer_text = f"تولید شده در {now}" if is_fa else f"Generated at {now}"
    headers_html = ''.join(f'<th>{escape(header)}</th>' for header in headers)
    rows_html = []
    for item in items:
        row_cells = []
        for key in keys:
            value = item.get(key, "")
            if isinstance(value, list):
                value = ", ".join(str(v) for v in value)
            elif isinstance(value, dict):
                value = json.dumps(value, ensure_ascii=False)
            row_cells.append(f'<td>{escape(str(value))}</td>')
        rows_html.append(f'<tr>{"".join(row_cells)}</tr>')
    # کانتکست برای قالب سفارشی
    template_context = {
        "title_text": title_text,
        "business_name": business_name,
        "generated_at": now,
        "is_fa": is_fa,
        "headers": headers,
        "keys": keys,
        "items": items,
        "table_headers_html": headers_html,
        "table_rows_html": "".join(rows_html),
    }
    # تلاش برای رندر با قالب سفارشی
    resolved_html = None
    try:
        from app.services.report_template_service import ReportTemplateService
        explicit_template_id = None
        try:
            if body.get("template_id") is not None:
                explicit_template_id = int(body.get("template_id"))
        except Exception:
            explicit_template_id = None
        resolved_html = ReportTemplateService.try_render_resolved(
            db=db,
            business_id=business_id,
            module_key="expense_income",
            subtype="list",
            context=template_context,
            explicit_template_id=explicit_template_id,
        )
    except Exception:
        resolved_html = None
    # HTML پیش‌فرض با قالب فایل
    disposition = "attachment"
    try:
        disposition = str(body.get("disposition") or "attachment")
    except Exception:
        disposition = "attachment"
    paper_size = None
    orientation = None
    try:
        paper_size = body.get("paper_size")
        orientation = body.get("orientation")
    except Exception:
        pass
    final_html = resolved_html or render_template(
        "pdf/expense_income/list.html",
        {
            **template_context,
            "title_text": title_text,
            "paper_size": paper_size,
            "orientation": orientation,
            "footer_text": footer_text,
        },
    )
    pdf_bytes = HTML(string=final_html).write_pdf(font_config=FontConfiguration())
    filename = f"expense_income_{business_id}_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf"
    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f"{disposition}; filename={filename}",
            "Content-Length": str(len(pdf_bytes)),
            "Access-Control-Expose-Headers": "Content-Disposition",
        },
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


