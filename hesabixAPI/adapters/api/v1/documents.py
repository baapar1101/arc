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
from app.services.pdf.template_renderer import render_template
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


@router.post(
    "/businesses/{business_id}/documents/export/pdf",
    summary="خروجی PDF لیست اسناد حسابداری",
    description="دریافت فایل PDF لیست اسناد حسابداری با پشتیبانی از قالب سفارشی (documents/list)",
)
@require_business_access("business_id")
async def export_documents_pdf_endpoint(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(default={}),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """خروجی PDF لیست اسناد حسابداری"""
    from fastapi.responses import Response
    from weasyprint import HTML
    from weasyprint.text.fonts import FontConfiguration
    from app.core.i18n import negotiate_locale
    from html import escape
    import datetime, json
    # فیلترهایی مشابه export_documents_excel
    filters = {}
    for key in ["document_type", "from_date", "to_date", "currency_id", "is_proforma"]:
        if key in body:
            filters[key] = body[key]
    # سال مالی از header یا body
    try:
        fy_header = request.headers.get("X-Fiscal-Year-ID")
        if fy_header:
            filters["fiscal_year_id"] = int(fy_header)
        elif "fiscal_year_id" in body:
            filters["fiscal_year_id"] = body["fiscal_year_id"]
    except Exception:
        pass
    # دریافت داده‌ها
    result = list_documents(db, business_id, {**filters, "take": body.get("take", 1000), "skip": body.get("skip", 0)})
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
            ("total_debit", "جمع بدهکار"),
            ("total_credit", "جمع بستانکار"),
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
        from adapters.db.models.business import Business
        b = db.query(Business).filter(Business.id == business_id).first()
        if b is not None:
            business_name = b.name or ""
    except Exception:
        business_name = ""
    # Locale
    locale = negotiate_locale(request.headers.get("Accept-Language"))
    is_fa = locale == "fa"
    now = datetime.datetime.now().strftime('%Y/%m/%d %H:%M')
    title_text = "لیست اسناد حسابداری" if is_fa else "Documents List"
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
    # کانتکست قالب
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
            module_key="documents",
            subtype="list",
            context=template_context,
            explicit_template_id=explicit_template_id,
        )
    except Exception:
        resolved_html = None
    # HTML پیش‌فرض با قالب فایل + پارامترها
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
    html_content = resolved_html or render_template(
        "pdf/documents/list.html",
        {
            **template_context,
            "title_text": title_text,
            "paper_size": paper_size,
            "orientation": orientation,
            "footer_text": footer_text,
        },
    )
    pdf_bytes = HTML(string=html_content).write_pdf(font_config=FontConfiguration())
    filename = f"documents_{business_id}_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf"
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
    template_id: int | None = None,
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
    
    # رندر با قالب سفارشی (documents/detail) یا خروجی پیش‌فرض
    from weasyprint import HTML
    from weasyprint.text.fonts import FontConfiguration
    from app.core.i18n import negotiate_locale
    from html import escape
    import datetime, re

    # اطلاعات کسب‌وکار
    business_name = ""
    try:
        from adapters.db.models.business import Business
        b = db.query(Business).filter(Business.id == business_id).first()
        if b is not None:
            business_name = b.name or ""
    except Exception:
        business_name = ""

    # Locale
    locale = negotiate_locale(request.headers.get("Accept-Language"))
    is_fa = locale == "fa"
    now = datetime.datetime.now().strftime("%Y/%m/%d %H:%M")
    
    # تبدیل تاریخ سند به تقویم شمسی
    document_date_jalali = None
    if doc.get("document_date"):
        try:
            from app.core.calendar import CalendarConverter
            dt = datetime.datetime.fromisoformat(str(doc.get("document_date")).replace("Z", "+00:00"))
            formatted = CalendarConverter.format_datetime(dt, "jalali")
            document_date_jalali = formatted.get('formatted', formatted.get('date_only', ''))
        except Exception:
            pass
    
    # جمع‌آوری اطلاعات assets (مثلاً لوگو کسب‌وکار)
    business_logo = None
    try:
        from adapters.db.models.business import Business
        b = db.query(Business).filter(Business.id == business_id).first()
        if b and hasattr(b, 'logo_url') and b.logo_url:
            business_logo = b.logo_url
    except Exception:
        pass

    # کانتکست قالب
    template_context = {
        "business_id": business_id,
        "business_name": business_name,
        "document": doc,
        "lines": doc.get("lines", []),
        "code": doc.get("code"),
        "document_type": doc.get("document_type"),
        "document_date": doc.get("document_date"),
        "document_date_jalali": document_date_jalali,
        "description": doc.get("description"),
        "generated_at": now,
        "is_fa": is_fa,
        "assets": {
            "images": {
                "logo": business_logo or "",
            }
        },
    }

    # تلاش برای رندر با قالب سفارشی
    resolved_html = None
    try:
        from app.services.report_template_service import ReportTemplateService
        explicit_template_id = None
        try:
            if template_id is not None:
                explicit_template_id = int(template_id)
            # همچنین می‌توان از query parameter استفاده کرد
            elif request.query_params.get("template_id"):
                explicit_template_id = int(request.query_params.get("template_id"))
        except (ValueError, TypeError):
            explicit_template_id = None
        
        resolved_html = ReportTemplateService.try_render_resolved(
            db=db,
            business_id=business_id,
            module_key="documents",
            subtype="detail",
            context=template_context,
            explicit_template_id=explicit_template_id,
        )
    except Exception as e:
        # اگر خطای قالب باشد، لاگ می‌کنیم اما به قالب پیش‌فرض می‌رویم
        import logging
        logger = logging.getLogger(__name__)
        logger.warning(f"Custom template rendering failed, using default: {e}", exc_info=True)
        resolved_html = None

    # پیش‌فرض: قالب فایل + پارامترها
    try:
        qp = request.query_params
        paper_size = qp.get("paper_size")
        orientation = qp.get("orientation")
        disposition = qp.get("disposition") or "attachment"
    except Exception:
        paper_size = None
        orientation = None
        disposition = "attachment"
    html_content = resolved_html or render_template(
        "pdf/documents/detail.html",
        {
            **template_context,
            "title_text": doc.get("document_type_name") or ("سند" if is_fa else "Document"),
            "paper_size": paper_size,
            "orientation": orientation,
            "footer_text": "",
        },
    )

    # تولید PDF با پیکربندی فونت
    def get_font_config():
        """پیکربندی فونت برای PDF فارسی"""
        return FontConfiguration()
    
    try:
        pdf_bytes = HTML(string=html_content).write_pdf(font_config=get_font_config())
    except Exception as e:
        import logging
        logger = logging.getLogger(__name__)
        logger.error(f"PDF generation failed: {e}", exc_info=True)
        raise ApiError("PDF_GENERATION_ERROR", "خطا در تولید فایل PDF", http_status=500)

    def _slugify(text: str) -> str:
        return re.sub(r"[^A-Za-z0-9_-]+", "_", (text or "")).strip("_") or "document"
    filename = f"document_{_slugify(doc.get('code'))}_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf"

    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f"{disposition}; filename={filename}",
            "Content-Length": str(len(pdf_bytes)),
            "Access-Control-Expose-Headers": "Content-Disposition",
        },
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

