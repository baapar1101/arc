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
from app.services.invoice_service import get_daily_sales_report, get_monthly_sales_report, get_top_customers_report, get_daily_purchases_report, get_top_suppliers_report, get_materials_consumption_report, get_production_report
from app.services.trial_balance_service import get_trial_balance_report
from app.services.general_ledger_service import get_general_ledger_report
from app.services.pnl_service import get_pnl_period_report, get_pnl_cumulative_report
from app.services.account_review_service import get_accounts_review_report
from app.core.i18n import negotiate_locale
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


@router.post(
    "/businesses/{business_id}/reports/daily-sales",
    summary="گزارش فروش روزانه",
    description="گزارش فروش روزانه با گروه‌بندی بر اساس تاریخ",
)
@require_business_access("business_id")
async def daily_sales_report_endpoint(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(default={}),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    """گزارش فروش روزانه"""
    # بررسی دسترسی
    if not ctx.can_read_section("reports"):
        raise ApiError("FORBIDDEN", "Missing business permission: reports.read", http_status=403)
    
    # دریافت سال مالی از header یا body
    fiscal_year_id = None
    fy_header = request.headers.get('X-Fiscal-Year-ID')
    if fy_header:
        try:
            fiscal_year_id = int(fy_header)
        except (ValueError, TypeError):
            pass
    
    if body.get('fiscal_year_id'):
        try:
            fiscal_year_id = int(body['fiscal_year_id'])
        except (ValueError, TypeError):
            pass
    
    # استخراج پارامترها از body
    date_from = body.get('date_from')
    date_to = body.get('date_to')
    currency_id = body.get('currency_id')
    if currency_id is not None:
        try:
            currency_id = int(currency_id)
        except (ValueError, TypeError):
            currency_id = None
    
    # Pagination
    skip = body.get('skip', 0)
    take = body.get('take', 50)
    try:
        skip = int(skip)
        take = int(take)
        if take > 500:
            take = 500
        if take < 1:
            take = 50
        if skip < 0:
            skip = 0
    except (ValueError, TypeError):
        skip = 0
        take = 50
    
    result = get_daily_sales_report(
        db=db,
        business_id=business_id,
        fiscal_year_id=fiscal_year_id,
        currency_id=currency_id,
        date_from=date_from,
        date_to=date_to,
        skip=skip,
        take=take,
    )
    
    items = result.get('items', [])
    items = [format_datetime_fields(item, request) for item in items]
    
    result['items'] = items
    
    locale = negotiate_locale(request.headers.get("Accept-Language"))
    return success_response(
        data=result,
        message="Daily sales report retrieved successfully" if locale != 'fa' else "گزارش فروش روزانه با موفقیت دریافت شد",
        request=request
    )


@router.post(
    "/businesses/{business_id}/reports/monthly-sales",
    summary="گزارش فروش ماهانه",
    description="گزارش فروش ماهانه با گروه‌بندی بر اساس ماه",
)
@require_business_access("business_id")
async def monthly_sales_report_endpoint(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(default={}),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    """گزارش فروش ماهانه"""
    # بررسی دسترسی
    if not ctx.can_read_section("reports"):
        raise ApiError("FORBIDDEN", "Missing business permission: reports.read", http_status=403)
    
    # دریافت سال مالی از header یا body
    fiscal_year_id = None
    fy_header = request.headers.get('X-Fiscal-Year-ID')
    if fy_header:
        try:
            fiscal_year_id = int(fy_header)
        except (ValueError, TypeError):
            pass
    
    if body.get('fiscal_year_id'):
        try:
            fiscal_year_id = int(body['fiscal_year_id'])
        except (ValueError, TypeError):
            pass
    
    # استخراج پارامترها از body
    date_from = body.get('date_from')
    date_to = body.get('date_to')
    currency_id = body.get('currency_id')
    if currency_id is not None:
        try:
            currency_id = int(currency_id)
        except (ValueError, TypeError):
            currency_id = None
    
    # Pagination
    skip = body.get('skip', 0)
    take = body.get('take', 50)
    try:
        skip = int(skip)
        take = int(take)
        if take > 500:
            take = 500
        if take < 1:
            take = 50
        if skip < 0:
            skip = 0
    except (ValueError, TypeError):
        skip = 0
        take = 50
    
    result = get_monthly_sales_report(
        db=db,
        business_id=business_id,
        fiscal_year_id=fiscal_year_id,
        currency_id=currency_id,
        date_from=date_from,
        date_to=date_to,
        skip=skip,
        take=take,
    )
    
    items = result.get('items', [])
    # برای گزارش ماهانه، format_datetime_fields اعمال نمی‌شود
    # چون month_key یک رشته است و نیازی به فرمت کردن تاریخ نیست
    # فقط فیلد date را برای استفاده در frontend نگه می‌داریم
    formatted_items = []
    for item in items:
        formatted_item = dict(item)
        # اگر فیلد date وجود دارد و یک datetime یا date object است، به ISO string تبدیل کن
        if 'date' in formatted_item and formatted_item['date']:
            try:
                from datetime import date as date_class, datetime as dt_class
                if isinstance(formatted_item['date'], dt_class):
                    formatted_item['date'] = formatted_item['date'].date().isoformat()
                elif isinstance(formatted_item['date'], date_class):
                    formatted_item['date'] = formatted_item['date'].isoformat()
            except Exception:
                pass
        formatted_items.append(formatted_item)
    
    result['items'] = formatted_items
    
    locale = negotiate_locale(request.headers.get("Accept-Language"))
    return success_response(
        data=result,
        message="Monthly sales report retrieved successfully" if locale != 'fa' else "گزارش فروش ماهانه با موفقیت دریافت شد",
        request=request
    )


@router.post(
    "/businesses/{business_id}/reports/top-customers",
    summary="گزارش برترین مشتریان",
    description="گزارش برترین مشتریان بر اساس مبلغ فروش",
)
@require_business_access("business_id")
async def top_customers_report_endpoint(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(default={}),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    """گزارش برترین مشتریان"""
    
    # Extract filters
    fiscal_year_id = body.get('fiscal_year_id')
    currency_id = body.get('currency_id')
    date_from = body.get('date_from')
    date_to = body.get('date_to')
    limit = body.get('limit')
    
    # Convert fiscal_year_id
    if fiscal_year_id is not None:
        try:
            fiscal_year_id = int(fiscal_year_id)
        except (ValueError, TypeError):
            fiscal_year_id = None
    
    # Convert currency_id
    if currency_id is not None:
        try:
            currency_id = int(currency_id)
        except (ValueError, TypeError):
            currency_id = None
    
    # Convert limit
    if limit is not None:
        try:
            limit = int(limit)
            if limit < 1:
                limit = None
        except (ValueError, TypeError):
            limit = None
    
    # Pagination
    skip = body.get('skip', 0)
    take = body.get('take', 50)
    try:
        skip = int(skip)
        take = int(take)
        if take > 500:
            take = 500
        if take < 1:
            take = 50
        if skip < 0:
            skip = 0
    except (ValueError, TypeError):
        skip = 0
        take = 50
    
    result = get_top_customers_report(
        db=db,
        business_id=business_id,
        fiscal_year_id=fiscal_year_id,
        currency_id=currency_id,
        date_from=date_from,
        date_to=date_to,
        limit=limit,
        skip=skip,
        take=take,
    )
    
    items = result.get('items', [])
    # برای گزارش برترین مشتریان، format_datetime_fields روی فیلد last_sale_date اعمال می‌شود
    formatted_items = []
    for item in items:
        formatted_item = dict(item)
        # اگر فیلد last_sale_date وجود دارد، آن را فرمت کن
        if 'last_sale_date' in formatted_item and formatted_item['last_sale_date']:
            try:
                from datetime import date as date_class
                if isinstance(formatted_item['last_sale_date'], str):
                    date_obj = date_class.fromisoformat(formatted_item['last_sale_date'])
                    formatted_dict = format_datetime_fields({'date': date_obj}, request)
                    formatted_item['last_sale_date'] = formatted_dict.get('date', formatted_item['last_sale_date'])
            except Exception:
                pass
        formatted_items.append(formatted_item)
    
    result['items'] = formatted_items
    
    locale = negotiate_locale(request.headers.get("Accept-Language"))
    return success_response(
        data=result,
        message="Top customers report retrieved successfully" if locale != 'fa' else "گزارش برترین مشتریان با موفقیت دریافت شد",
        request=request
    )


@router.post(
    "/businesses/{business_id}/reports/top-suppliers",
    summary="گزارش برترین تامین‌کنندگان",
    description="گزارش برترین تامین‌کنندگان بر اساس مبلغ خرید",
)
@require_business_access("business_id")
async def top_suppliers_report_endpoint(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(default={}),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    """گزارش برترین تامین‌کنندگان"""
    
    # Extract filters
    fiscal_year_id = body.get('fiscal_year_id')
    currency_id = body.get('currency_id')
    date_from = body.get('date_from')
    date_to = body.get('date_to')
    limit = body.get('limit')
    
    # Convert fiscal_year_id
    if fiscal_year_id is not None:
        try:
            fiscal_year_id = int(fiscal_year_id)
        except (ValueError, TypeError):
            fiscal_year_id = None
    
    # Convert currency_id
    if currency_id is not None:
        try:
            currency_id = int(currency_id)
        except (ValueError, TypeError):
            currency_id = None
    
    # Get fiscal year from header if not in body
    fy_header = request.headers.get('X-Fiscal-Year-ID')
    if not fiscal_year_id and fy_header:
        try:
            fiscal_year_id = int(fy_header)
        except (ValueError, TypeError):
            pass
    
    # Pagination
    skip = body.get('skip', 0)
    take = body.get('take', 50)
    try:
        skip = int(skip)
        take = int(take)
        if take > 500:
            take = 500
        if take < 1:
            take = 50
        if skip < 0:
            skip = 0
    except (ValueError, TypeError):
        skip = 0
        take = 50
    
    # Convert limit
    if limit is not None:
        try:
            limit = int(limit)
            if limit < 1:
                limit = None
        except (ValueError, TypeError):
            limit = None
    
    result = get_top_suppliers_report(
        db=db,
        business_id=business_id,
        fiscal_year_id=fiscal_year_id,
        currency_id=currency_id,
        date_from=date_from,
        date_to=date_to,
        limit=limit,
        skip=skip,
        take=take,
    )
    
    items = result.get('items', [])
    # برای گزارش برترین تامین‌کنندگان، format_datetime_fields روی فیلد last_purchase_date اعمال می‌شود
    formatted_items = []
    for item in items:
        formatted_item = dict(item)
        # اگر فیلد last_purchase_date وجود دارد، آن را فرمت کن
        if 'last_purchase_date' in formatted_item and formatted_item['last_purchase_date']:
            try:
                from datetime import date as date_class
                if isinstance(formatted_item['last_purchase_date'], str):
                    date_obj = date_class.fromisoformat(formatted_item['last_purchase_date'])
                    formatted_dict = format_datetime_fields({'date': date_obj}, request)
                    formatted_item['last_purchase_date'] = formatted_dict.get('date', formatted_item['last_purchase_date'])
            except Exception:
                pass
        formatted_items.append(formatted_item)
    
    result['items'] = formatted_items
    
    locale = negotiate_locale(request.headers.get("Accept-Language"))
    return success_response(
        data=result,
        message="Top suppliers report retrieved successfully" if locale != 'fa' else "گزارش برترین تامین‌کنندگان با موفقیت دریافت شد",
        request=request
    )


@router.post(
    "/businesses/{business_id}/reports/top-suppliers/export/excel",
    summary="خروجی Excel گزارش برترین تامین‌کنندگان",
    description="خروجی Excel گزارش برترین تامین‌کنندگان با قابلیت فیلتر، انتخاب سطرها و رعایت ترتیب/نمایش ستون‌ها",
)
@require_business_access("business_id")
async def export_top_suppliers_report_excel(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(default={}),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """خروجی Excel گزارش برترین تامین‌کنندگان"""
    import io
    import json
    import datetime
    import re
    from openpyxl import Workbook
    from openpyxl.styles import Font, Alignment, PatternFill, Border, Side
    from fastapi.responses import Response
    from adapters.db.models.business import Business
    
    # بررسی دسترسی
    if not ctx.can_read_section("reports"):
        raise ApiError("FORBIDDEN", "Missing business permission: reports.read", http_status=403)
    
    # Extract filters
    fiscal_year_id = body.get('fiscal_year_id')
    currency_id = body.get('currency_id')
    date_from = body.get('date_from')
    date_to = body.get('date_to')
    limit = body.get('limit')
    
    # Convert fiscal_year_id
    if fiscal_year_id is not None:
        try:
            fiscal_year_id = int(fiscal_year_id)
        except (ValueError, TypeError):
            fiscal_year_id = None
    
    # Convert currency_id
    if currency_id is not None:
        try:
            currency_id = int(currency_id)
        except (ValueError, TypeError):
            currency_id = None
    
    # Get fiscal year from header if not in body
    fy_header = request.headers.get('X-Fiscal-Year-ID')
    if not fiscal_year_id and fy_header:
        try:
            fiscal_year_id = int(fy_header)
        except (ValueError, TypeError):
            pass
    
    # Convert limit
    if limit is not None:
        try:
            limit = int(limit)
            if limit < 1:
                limit = None
        except (ValueError, TypeError):
            limit = None
    
    # برای export، همه رکوردها را بدون pagination می‌گیریم
    max_export_records = 10000
    result = get_top_suppliers_report(
        db=db,
        business_id=business_id,
        fiscal_year_id=fiscal_year_id,
        currency_id=currency_id,
        date_from=date_from,
        date_to=date_to,
        limit=limit,
        skip=0,
        take=max_export_records,
    )
    
    items = result.get('items', [])
    # برای گزارش برترین تامین‌کنندگان، format_datetime_fields روی فیلد last_purchase_date اعمال می‌شود
    formatted_items = []
    for item in items:
        formatted_item = dict(item)
        # اگر فیلد last_purchase_date وجود دارد، آن را فرمت کن
        if 'last_purchase_date' in formatted_item and formatted_item['last_purchase_date']:
            try:
                from datetime import date as date_class
                if isinstance(formatted_item['last_purchase_date'], str):
                    date_obj = date_class.fromisoformat(formatted_item['last_purchase_date'])
                    formatted_dict = format_datetime_fields({'date': date_obj}, request)
                    formatted_item['last_purchase_date'] = formatted_dict.get('date', formatted_item['last_purchase_date'])
            except Exception:
                pass
        formatted_items.append(formatted_item)
    
    items = formatted_items
    
    # Handle selected rows
    selected_only = bool(body.get('selected_only', False))
    selected_indices = body.get('selected_indices')
    if selected_only and selected_indices is not None:
        indices = None
        if isinstance(selected_indices, str):
            try:
                indices = json.loads(selected_indices)
            except (json.JSONDecodeError, TypeError):
                indices = None
        elif isinstance(selected_indices, list):
            indices = selected_indices
        if isinstance(indices, list):
            items = [items[i] for i in indices if isinstance(i, int) and 0 <= i < len(items)]
    
    # Get locale
    locale = negotiate_locale(request.headers.get("Accept-Language"))
    is_fa = locale == 'fa'
    
    # Prepare headers based on export_columns
    headers: List[str] = []
    keys: List[str] = []
    export_columns = body.get('export_columns')
    if export_columns:
        for col in export_columns:
            key = col.get('key')
            label = col.get('label', key)
            if key:
                keys.append(str(key))
                headers.append(str(label))
    else:
        # Default columns
        default_columns = [
            ('person_code', 'کد تامین‌کننده' if is_fa else 'Supplier Code'),
            ('person_name', 'نام تامین‌کننده' if is_fa else 'Supplier Name'),
            ('invoice_count', 'تعداد فاکتور' if is_fa else 'Invoice Count'),
            ('total_purchases', 'جمع خرید' if is_fa else 'Total Purchases'),
            ('last_purchase_date', 'آخرین تاریخ خرید' if is_fa else 'Last Purchase Date'),
        ]
        for key, label in default_columns:
            keys.append(key)
            headers.append(label)
    
    # Create workbook
    wb = Workbook()
    ws = wb.active
    ws.title = "گزارش برترین تامین‌کنندگان" if is_fa else "Top Suppliers Report"
    
    # RTL handling for Persian
    if locale == 'fa':
        try:
            ws.sheet_view.rightToLeft = True
        except Exception:
            pass
    
    header_font = Font(bold=True, color="FFFFFF")
    header_fill = PatternFill(start_color="366092", end_color="366092", fill_type="solid")
    header_alignment = Alignment(horizontal="center", vertical="center")
    border = Border(
        left=Side(style='thin'),
        right=Side(style='thin'),
        top=Side(style='thin'),
        bottom=Side(style='thin')
    )
    
    # Write header row
    for col_idx, header in enumerate(headers, 1):
        cell = ws.cell(row=1, column=col_idx, value=header)
        cell.font = header_font
        cell.fill = header_fill
        cell.alignment = header_alignment
        cell.border = border
    
    # Write data rows
    for row_idx, item in enumerate(items, 2):
        for col_idx, key in enumerate(keys, 1):
            value = item.get(key, "")
            
            # Format numbers
            if key in ['invoice_count', 'total_purchases'] and value:
                try:
                    num_value = float(value) if not isinstance(value, (int, float)) else value
                    value = num_value
                except (ValueError, TypeError):
                    pass
            
            # Format dates
            if key == 'last_purchase_date' and value:
                # Value is already formatted by format_datetime_fields
                pass
            
            if isinstance(value, list):
                value = ", ".join(str(v) for v in value)
            elif isinstance(value, dict):
                value = str(value)
            
            cell = ws.cell(row=row_idx, column=col_idx, value=value)
            cell.border = border
            
            # RTL alignment for Persian text and numbers
            if locale == 'fa':
                if isinstance(value, (int, float)):
                    cell.alignment = Alignment(horizontal="right")
                elif isinstance(value, str) and any('\u0600' <= c <= '\u06FF' for c in str(value)):
                    cell.alignment = Alignment(horizontal="right")
    
    # Auto-width columns
    for column in ws.columns:
        max_length = 0
        column_letter = column[0].column_letter
        for cell in column:
            try:
                if cell.value is not None:
                    cell_length = len(str(cell.value))
                    if cell_length > max_length:
                        max_length = cell_length
            except Exception:
                pass
        ws.column_dimensions[column_letter].width = min(max_length + 2, 50)
    
    # Save to bytes
    buffer = io.BytesIO()
    wb.save(buffer)
    buffer.seek(0)
    
    # Build meaningful filename
    biz_name = ""
    try:
        b = db.query(Business).filter(Business.id == business_id).first()
        if b is not None:
            biz_name = b.name or ""
    except Exception:
        biz_name = ""
    
    def slugify(text: str) -> str:
        return re.sub(r"[^A-Za-z0-9_-]+", "_", text).strip("_")
    
    base = "top_suppliers_report"
    if biz_name:
        base += f"_{slugify(biz_name)}"
    if selected_only:
        base += "_selected"
    filename = f"{base}_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.xlsx"
    content = buffer.getvalue()
    
    return Response(
        content=content,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={
            "Content-Disposition": f"attachment; filename={filename}",
            "Content-Length": str(len(content)),
            "Access-Control-Expose-Headers": "Content-Disposition",
        },
    )


@router.post(
    "/businesses/{business_id}/reports/daily-purchases",
    summary="گزارش خرید روزانه",
    description="گزارش خرید روزانه با گروه‌بندی بر اساس تاریخ",
)
@require_business_access("business_id")
async def daily_purchases_report_endpoint(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(default={}),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    """گزارش خرید روزانه"""
    # بررسی دسترسی
    if not ctx.can_read_section("reports"):
        raise ApiError("FORBIDDEN", "Missing business permission: reports.read", http_status=403)
    
    # دریافت سال مالی از header یا body
    fiscal_year_id = None
    fy_header = request.headers.get('X-Fiscal-Year-ID')
    if fy_header:
        try:
            fiscal_year_id = int(fy_header)
        except (ValueError, TypeError):
            pass
    
    if body.get('fiscal_year_id'):
        try:
            fiscal_year_id = int(body['fiscal_year_id'])
        except (ValueError, TypeError):
            pass
    
    # استخراج پارامترها از body
    date_from = body.get('date_from')
    date_to = body.get('date_to')
    currency_id = body.get('currency_id')
    if currency_id is not None:
        try:
            currency_id = int(currency_id)
        except (ValueError, TypeError):
            currency_id = None
    
    # Pagination
    skip = body.get('skip', 0)
    take = body.get('take', 50)
    try:
        skip = int(skip)
        take = int(take)
        if take > 500:
            take = 500
        if take < 1:
            take = 50
        if skip < 0:
            skip = 0
    except (ValueError, TypeError):
        skip = 0
        take = 50
    
    result = get_daily_purchases_report(
        db=db,
        business_id=business_id,
        fiscal_year_id=fiscal_year_id,
        currency_id=currency_id,
        date_from=date_from,
        date_to=date_to,
        skip=skip,
        take=take,
    )
    
    items = result.get('items', [])
    items = [format_datetime_fields(item, request) for item in items]
    
    result['items'] = items
    
    locale = negotiate_locale(request.headers.get("Accept-Language"))
    return success_response(
        data=result,
        message="Daily purchases report retrieved successfully" if locale != 'fa' else "گزارش خرید روزانه با موفقیت دریافت شد",
        request=request
    )


@router.post(
    "/businesses/{business_id}/reports/daily-purchases/export/excel",
    summary="خروجی Excel گزارش خرید روزانه",
    description="خروجی Excel گزارش خرید روزانه با قابلیت فیلتر، انتخاب سطرها و رعایت ترتیب/نمایش ستون‌ها",
)
@require_business_access("business_id")
async def export_daily_purchases_report_excel(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(default={}),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """خروجی Excel گزارش خرید روزانه"""
    import io
    import json
    import datetime
    import re
    from openpyxl import Workbook
    from openpyxl.styles import Font, Alignment, PatternFill, Border, Side
    from fastapi.responses import Response
    from adapters.db.models.business import Business
    
    # بررسی دسترسی
    if not ctx.can_read_section("reports"):
        raise ApiError("FORBIDDEN", "Missing business permission: reports.read", http_status=403)
    
    # دریافت سال مالی از header یا body
    fiscal_year_id = None
    fy_header = request.headers.get('X-Fiscal-Year-ID')
    if fy_header:
        try:
            fiscal_year_id = int(fy_header)
        except (ValueError, TypeError):
            pass
    
    if body.get('fiscal_year_id'):
        try:
            fiscal_year_id = int(body['fiscal_year_id'])
        except (ValueError, TypeError):
            pass
    
    if not fiscal_year_id:
        from adapters.db.models.fiscal_year import FiscalYear
        fiscal_year = db.query(FiscalYear).filter(
            and_(
                FiscalYear.business_id == business_id,
                FiscalYear.is_last == True
            )
        ).first()
        if fiscal_year:
            fiscal_year_id = fiscal_year.id
    
    # استخراج پارامترها از body
    date_from = body.get('date_from')
    date_to = body.get('date_to')
    currency_id = body.get('currency_id')
    if currency_id is not None:
        try:
            currency_id = int(currency_id)
        except (ValueError, TypeError):
            currency_id = None
    
    # برای export، همه رکوردها را بدون pagination می‌گیریم
    max_export_records = 10000
    result = get_daily_purchases_report(
        db=db,
        business_id=business_id,
        fiscal_year_id=fiscal_year_id,
        currency_id=currency_id,
        date_from=date_from,
        date_to=date_to,
        skip=0,
        take=max_export_records,
    )
    
    items = result.get('items', [])
    items = [format_datetime_fields(item, request) for item in items]
    
    # Handle selected rows
    selected_only = bool(body.get('selected_only', False))
    selected_indices = body.get('selected_indices')
    if selected_only and selected_indices is not None:
        indices = None
        if isinstance(selected_indices, str):
            try:
                indices = json.loads(selected_indices)
            except (json.JSONDecodeError, TypeError):
                indices = None
        elif isinstance(selected_indices, list):
            indices = selected_indices
        if isinstance(indices, list):
            items = [items[i] for i in indices if isinstance(i, int) and 0 <= i < len(items)]
    
    # Get locale
    locale = negotiate_locale(request.headers.get("Accept-Language"))
    is_fa = locale == 'fa'
    
    # Prepare headers based on export_columns
    headers: List[str] = []
    keys: List[str] = []
    export_columns = body.get('export_columns')
    if export_columns:
        for col in export_columns:
            key = col.get('key')
            label = col.get('label', key)
            if key:
                keys.append(str(key))
                headers.append(str(label))
    else:
        # Default columns
        default_columns = [
            ('date', 'تاریخ' if is_fa else 'Date'),
            ('invoice_count', 'تعداد فاکتور' if is_fa else 'Invoice Count'),
            ('total_gross', 'جمع کل' if is_fa else 'Total Gross'),
            ('total_discount', 'جمع تخفیف' if is_fa else 'Total Discount'),
            ('total_tax', 'جمع مالیات' if is_fa else 'Total Tax'),
            ('total_net', 'جمع خالص' if is_fa else 'Total Net'),
        ]
        for key, label in default_columns:
            keys.append(key)
            headers.append(label)
    
    # Create workbook
    wb = Workbook()
    ws = wb.active
    ws.title = "گزارش خرید روزانه" if is_fa else "Daily Purchases Report"
    
    # RTL handling for Persian
    if locale == 'fa':
        try:
            ws.sheet_view.rightToLeft = True
        except Exception:
            pass
    
    header_font = Font(bold=True, color="FFFFFF")
    header_fill = PatternFill(start_color="366092", end_color="366092", fill_type="solid")
    header_alignment = Alignment(horizontal="center", vertical="center")
    border = Border(
        left=Side(style='thin'),
        right=Side(style='thin'),
        top=Side(style='thin'),
        bottom=Side(style='thin')
    )
    
    # Write header row
    for col_idx, header in enumerate(headers, 1):
        cell = ws.cell(row=1, column=col_idx, value=header)
        cell.font = header_font
        cell.fill = header_fill
        cell.alignment = header_alignment
        cell.border = border
    
    # Write data rows
    for row_idx, item in enumerate(items, 2):
        for col_idx, key in enumerate(keys, 1):
            value = item.get(key, "")
            
            # Format numbers
            if key in ['invoice_count', 'total_gross', 'total_discount', 'total_tax', 'total_net'] and value:
                try:
                    num_value = float(value) if not isinstance(value, (int, float)) else value
                    value = num_value
                except (ValueError, TypeError):
                    pass
            
            # Format dates
            if key == 'date' and value:
                # Value is already formatted by format_datetime_fields
                pass
            
            if isinstance(value, list):
                value = ", ".join(str(v) for v in value)
            elif isinstance(value, dict):
                value = str(value)
            
            cell = ws.cell(row=row_idx, column=col_idx, value=value)
            cell.border = border
            
            # RTL alignment for Persian text and numbers
            if locale == 'fa':
                if isinstance(value, (int, float)):
                    cell.alignment = Alignment(horizontal="right")
                elif isinstance(value, str) and any('\u0600' <= c <= '\u06FF' for c in str(value)):
                    cell.alignment = Alignment(horizontal="right")
    
    # Auto-width columns
    for column in ws.columns:
        max_length = 0
        column_letter = column[0].column_letter
        for cell in column:
            try:
                if cell.value is not None:
                    cell_length = len(str(cell.value))
                    if cell_length > max_length:
                        max_length = cell_length
            except Exception:
                pass
        ws.column_dimensions[column_letter].width = min(max_length + 2, 50)
    
    # Save to bytes
    buffer = io.BytesIO()
    wb.save(buffer)
    buffer.seek(0)
    
    # Build meaningful filename
    biz_name = ""
    try:
        b = db.query(Business).filter(Business.id == business_id).first()
        if b is not None:
            biz_name = b.name or ""
    except Exception:
        biz_name = ""
    
    def slugify(text: str) -> str:
        return re.sub(r"[^A-Za-z0-9_-]+", "_", text).strip("_")
    
    base = "daily_purchases_report"
    if biz_name:
        base += f"_{slugify(biz_name)}"
    if selected_only:
        base += "_selected"
    filename = f"{base}_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.xlsx"
    content = buffer.getvalue()
    
    return Response(
        content=content,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={
            "Content-Disposition": f"attachment; filename={filename}",
            "Content-Length": str(len(content)),
            "Access-Control-Expose-Headers": "Content-Disposition",
        },
    )


@router.post(
    "/businesses/{business_id}/reports/materials-consumption",
    summary="گزارش مصرف مواد",
    description="گزارش مصرف مواد از فاکتورهای تولید",
)
@require_business_access("business_id")
async def materials_consumption_report_endpoint(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(default={}),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    """گزارش مصرف مواد از فاکتورهای تولید"""
    # بررسی دسترسی
    if not ctx.can_read_section("reports"):
        raise ApiError("FORBIDDEN", "Missing business permission: reports.read", http_status=403)
    
    # دریافت سال مالی از header یا body
    fiscal_year_id = None
    fy_header = request.headers.get('X-Fiscal-Year-ID')
    if fy_header:
        try:
            fiscal_year_id = int(fy_header)
        except (ValueError, TypeError):
            pass
    
    if body.get('fiscal_year_id'):
        try:
            fiscal_year_id = int(body['fiscal_year_id'])
        except (ValueError, TypeError):
            pass
    
    # استخراج پارامترها از body
    date_from = body.get('date_from')
    date_to = body.get('date_to')
    currency_id = body.get('currency_id')
    product_id = body.get('product_id')
    warehouse_id = body.get('warehouse_id')
    
    if currency_id is not None:
        try:
            currency_id = int(currency_id)
        except (ValueError, TypeError):
            currency_id = None
    
    if product_id is not None:
        try:
            product_id = int(product_id)
        except (ValueError, TypeError):
            product_id = None
    
    if warehouse_id is not None:
        try:
            warehouse_id = int(warehouse_id)
        except (ValueError, TypeError):
            warehouse_id = None
    
    # Pagination
    skip = body.get('skip', 0)
    take = body.get('take', 50)
    try:
        skip = int(skip)
        take = int(take)
        if take > 500:
            take = 500
        if take < 1:
            take = 50
        if skip < 0:
            skip = 0
    except (ValueError, TypeError):
        skip = 0
        take = 50
    
    result = get_materials_consumption_report(
        db=db,
        business_id=business_id,
        fiscal_year_id=fiscal_year_id,
        currency_id=currency_id,
        date_from=date_from,
        date_to=date_to,
        product_id=product_id,
        warehouse_id=warehouse_id,
        skip=skip,
        take=take,
    )
    
    items = result.get('items', [])
    items = [format_datetime_fields(item, request) for item in items]
    
    result['items'] = items
    
    locale = negotiate_locale(request.headers.get("Accept-Language"))
    return success_response(
        data=result,
        message="Materials consumption report retrieved successfully" if locale != 'fa' else "گزارش مصرف مواد با موفقیت دریافت شد",
        request=request
    )


@router.post(
    "/businesses/{business_id}/reports/production",
    summary="گزارش تولید",
    description="گزارش تولید (کالاهای ساخته شده) از فاکتورهای تولید",
)
@require_business_access("business_id")
async def production_report_endpoint(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(default={}),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    """گزارش تولید (کالاهای ساخته شده) از فاکتورهای تولید"""
    # بررسی دسترسی
    if not ctx.can_read_section("reports"):
        raise ApiError("FORBIDDEN", "Missing business permission: reports.read", http_status=403)
    
    # دریافت سال مالی از header یا body
    fiscal_year_id = None
    fy_header = request.headers.get('X-Fiscal-Year-ID')
    if fy_header:
        try:
            fiscal_year_id = int(fy_header)
        except (ValueError, TypeError):
            pass
    
    if body.get('fiscal_year_id'):
        try:
            fiscal_year_id = int(body['fiscal_year_id'])
        except (ValueError, TypeError):
            pass
    
    # استخراج پارامترها از body
    date_from = body.get('date_from')
    date_to = body.get('date_to')
    currency_id = body.get('currency_id')
    product_id = body.get('product_id')
    warehouse_id = body.get('warehouse_id')
    
    if currency_id is not None:
        try:
            currency_id = int(currency_id)
        except (ValueError, TypeError):
            currency_id = None
    
    if product_id is not None:
        try:
            product_id = int(product_id)
        except (ValueError, TypeError):
            product_id = None
    
    if warehouse_id is not None:
        try:
            warehouse_id = int(warehouse_id)
        except (ValueError, TypeError):
            warehouse_id = None
    
    # Pagination
    skip = body.get('skip', 0)
    take = body.get('take', 50)
    try:
        skip = int(skip)
        take = int(take)
        if take > 500:
            take = 500
        if take < 1:
            take = 50
        if skip < 0:
            skip = 0
    except (ValueError, TypeError):
        skip = 0
        take = 50
    
    result = get_production_report(
        db=db,
        business_id=business_id,
        fiscal_year_id=fiscal_year_id,
        currency_id=currency_id,
        date_from=date_from,
        date_to=date_to,
        product_id=product_id,
        warehouse_id=warehouse_id,
        skip=skip,
        take=take,
    )
    
    items = result.get('items', [])
    items = [format_datetime_fields(item, request) for item in items]
    
    result['items'] = items
    
    locale = negotiate_locale(request.headers.get("Accept-Language"))
    return success_response(
        data=result,
        message="Production report retrieved successfully" if locale != 'fa' else "گزارش تولید با موفقیت دریافت شد",
        request=request
    )


@router.post(
    "/businesses/{business_id}/reports/trial-balance",
    summary="گزارش تراز آزمایشی",
    description="گزارش تراز آزمایشی برای حساب‌های حسابداری",
)
@require_business_access("business_id")
async def trial_balance_report_endpoint(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(default={}),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    """گزارش تراز آزمایشی برای حساب‌های حسابداری"""
    # بررسی دسترسی
    if not ctx.can_read_section("reports"):
        raise ApiError("FORBIDDEN", "Missing business permission: reports.read", http_status=403)
    
    # دریافت سال مالی از header یا body
    fiscal_year_id = None
    fy_header = request.headers.get('X-Fiscal-Year-ID')
    if fy_header:
        try:
            fiscal_year_id = int(fy_header)
        except (ValueError, TypeError):
            pass
    
    if body.get('fiscal_year_id'):
        try:
            fiscal_year_id = int(body['fiscal_year_id'])
        except (ValueError, TypeError):
            pass
    
    # استخراج پارامترها از body
    date_from = body.get('date_from')
    date_to = body.get('date_to')
    currency_id = body.get('currency_id')
    account_type = body.get('account_type')
    account_ids = body.get('account_ids')
    include_zero_balance = body.get('include_zero_balance', False)
    
    if currency_id is not None:
        try:
            currency_id = int(currency_id)
        except (ValueError, TypeError):
            currency_id = None
    
    if account_ids is not None and not isinstance(account_ids, list):
        account_ids = None
    
    if account_ids:
        try:
            account_ids = [int(aid) for aid in account_ids if aid is not None]
        except (ValueError, TypeError):
            account_ids = None
    
    # Pagination
    skip = body.get('skip', 0)
    take = body.get('take', 50)
    try:
        skip = int(skip)
        take = int(take)
        if take > 500:
            take = 500
        if take < 1:
            take = 50
        if skip < 0:
            skip = 0
    except (ValueError, TypeError):
        skip = 0
        take = 50
    
    result = get_trial_balance_report(
        db=db,
        business_id=business_id,
        fiscal_year_id=fiscal_year_id,
        currency_id=currency_id,
        date_from=date_from,
        date_to=date_to,
        account_type=account_type,
        account_ids=account_ids,
        include_zero_balance=include_zero_balance,
        skip=skip,
        take=take,
    )
    
    items = result.get('items', [])
    items = [format_datetime_fields(item, request) for item in items]
    
    result['items'] = items
    
    locale = negotiate_locale(request.headers.get("Accept-Language"))
    return success_response(
        data=result,
        message="Trial balance report retrieved successfully" if locale != 'fa' else "گزارش تراز آزمایشی با موفقیت دریافت شد",
        request=request
    )


@router.post(
    "/businesses/{business_id}/reports/general-ledger",
    summary="گزارش دفتر کل",
    description="گزارش دفتر کل برای حساب‌های حسابداری",
)
@require_business_access("business_id")
async def general_ledger_report_endpoint(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(default={}),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    """گزارش دفتر کل برای حساب‌های حسابداری"""
    # بررسی دسترسی
    if not ctx.can_read_section("reports"):
        raise ApiError("FORBIDDEN", "Missing business permission: reports.read", http_status=403)
    
    # account_ids اجباری است
    account_ids = body.get('account_ids')
    if not account_ids or not isinstance(account_ids, list) or len(account_ids) == 0:
        raise ApiError("ACCOUNT_IDS_REQUIRED", "account_ids الزامی است و باید لیستی از شناسه‌های حساب باشد", http_status=400)
    
    try:
        account_ids = [int(aid) for aid in account_ids if aid is not None]
    except (ValueError, TypeError):
        raise ApiError("INVALID_ACCOUNT_IDS", "account_ids باید لیستی از اعداد صحیح باشد", http_status=400)
    
    # دریافت سال مالی از header یا body
    fiscal_year_id = None
    fy_header = request.headers.get('X-Fiscal-Year-ID')
    if fy_header:
        try:
            fiscal_year_id = int(fy_header)
        except (ValueError, TypeError):
            pass
    
    if body.get('fiscal_year_id'):
        try:
            fiscal_year_id = int(body['fiscal_year_id'])
        except (ValueError, TypeError):
            pass
    
    # استخراج پارامترها از body
    date_from = body.get('date_from')
    date_to = body.get('date_to')
    currency_id = body.get('currency_id')
    person_id = body.get('person_id')
    include_proforma = body.get('include_proforma', False)
    
    if currency_id is not None:
        try:
            currency_id = int(currency_id)
        except (ValueError, TypeError):
            currency_id = None
    
    if person_id is not None:
        try:
            person_id = int(person_id)
        except (ValueError, TypeError):
            person_id = None
    
    # Pagination
    skip = body.get('skip', 0)
    take = body.get('take', 50)
    try:
        skip = int(skip)
        take = int(take)
        if take > 500:
            take = 500
        if take < 1:
            take = 50
        if skip < 0:
            skip = 0
    except (ValueError, TypeError):
        skip = 0
        take = 50
    
    result = get_general_ledger_report(
        db=db,
        business_id=business_id,
        account_ids=account_ids,
        fiscal_year_id=fiscal_year_id,
        currency_id=currency_id,
        date_from=date_from,
        date_to=date_to,
        person_id=person_id,
        include_proforma=include_proforma,
        skip=skip,
        take=take,
    )
    
    items = result.get('items', [])
    items = [format_datetime_fields(item, request) for item in items]
    
    result['items'] = items
    
    locale = negotiate_locale(request.headers.get("Accept-Language"))
    return success_response(
        data=result,
        message="General ledger report retrieved successfully" if locale != 'fa' else "گزارش دفتر کل با موفقیت دریافت شد",
        request=request
    )


@router.post(
    "/businesses/{business_id}/reports/pnl-period",
    summary="گزارش سود و زیان دوره‌ای",
    description="گزارش سود و زیان دوره‌ای (Profit & Loss Period)",
)
@require_business_access("business_id")
async def pnl_period_report_endpoint(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(default={}),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    """گزارش سود و زیان دوره‌ای"""
    # بررسی دسترسی
    if not ctx.can_read_section("reports"):
        raise ApiError("FORBIDDEN", "Missing business permission: reports.read", http_status=403)
    
    # دریافت سال مالی از header یا body
    fiscal_year_id = None
    fy_header = request.headers.get('X-Fiscal-Year-ID')
    if fy_header:
        try:
            fiscal_year_id = int(fy_header)
        except (ValueError, TypeError):
            pass
    
    if body.get('fiscal_year_id'):
        try:
            fiscal_year_id = int(body['fiscal_year_id'])
        except (ValueError, TypeError):
            pass
    
    # استخراج پارامترها از body
    date_from = body.get('date_from')
    date_to = body.get('date_to')
    currency_id = body.get('currency_id')
    
    if currency_id is not None:
        try:
            currency_id = int(currency_id)
        except (ValueError, TypeError):
            currency_id = None
    
    # Pagination
    skip = body.get('skip', 0)
    take = body.get('take', 100)
    try:
        skip = int(skip)
        take = int(take)
        if take > 500:
            take = 500
        if take < 1:
            take = 100
        if skip < 0:
            skip = 0
    except (ValueError, TypeError):
        skip = 0
        take = 100
    
    result = get_pnl_period_report(
        db=db,
        business_id=business_id,
        fiscal_year_id=fiscal_year_id,
        currency_id=currency_id,
        date_from=date_from,
        date_to=date_to,
        skip=skip,
        take=take,
    )
    
    locale = negotiate_locale(request.headers.get("Accept-Language"))
    return success_response(
        data=result,
        message="PnL Period report retrieved successfully" if locale != 'fa' else "گزارش سود و زیان دوره‌ای با موفقیت دریافت شد",
        request=request
    )


@router.post(
    "/businesses/{business_id}/reports/pnl-cumulative",
    summary="گزارش سود و زیان تجمعی",
    description="گزارش سود و زیان تجمعی از ابتدای سال مالی (Profit & Loss Cumulative)",
)
@require_business_access("business_id")
async def pnl_cumulative_report_endpoint(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(default={}),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    """گزارش سود و زیان تجمعی از ابتدای سال مالی"""
    # بررسی دسترسی
    if not ctx.can_read_section("reports"):
        raise ApiError("FORBIDDEN", "Missing business permission: reports.read", http_status=403)
    
    # دریافت سال مالی از header یا body
    fiscal_year_id = None
    fy_header = request.headers.get('X-Fiscal-Year-ID')
    if fy_header:
        try:
            fiscal_year_id = int(fy_header)
        except (ValueError, TypeError):
            pass
    
    if body.get('fiscal_year_id'):
        try:
            fiscal_year_id = int(body['fiscal_year_id'])
        except (ValueError, TypeError):
            pass
    
    # استخراج پارامترها از body
    date_to = body.get('date_to')  # فقط date_to (date_from همیشه ابتدای سال مالی است)
    currency_id = body.get('currency_id')
    
    if currency_id is not None:
        try:
            currency_id = int(currency_id)
        except (ValueError, TypeError):
            currency_id = None
    
    # Pagination
    skip = body.get('skip', 0)
    take = body.get('take', 100)
    try:
        skip = int(skip)
        take = int(take)
        if take > 500:
            take = 500
        if take < 1:
            take = 100
        if skip < 0:
            skip = 0
    except (ValueError, TypeError):
        skip = 0
        take = 100
    
    result = get_pnl_cumulative_report(
        db=db,
        business_id=business_id,
        fiscal_year_id=fiscal_year_id,
        currency_id=currency_id,
        date_to=date_to,
        skip=skip,
        take=take,
    )
    
    locale = negotiate_locale(request.headers.get("Accept-Language"))
    return success_response(
        data=result,
        message="PnL Cumulative report retrieved successfully" if locale != 'fa' else "گزارش سود و زیان تجمعی با موفقیت دریافت شد",
        request=request
    )


@router.post(
    "/businesses/{business_id}/reports/accounts-review",
    summary="گزارش مرور حساب‌ها",
    description="گزارش مرور حساب‌ها با ساختار درختی و مانده‌ها (Account Review Report)",
)
@require_business_access("business_id")
async def accounts_review_report_endpoint(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(default={}),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    """گزارش مرور حساب‌ها با ساختار درختی"""
    # بررسی دسترسی
    if not ctx.can_read_section("reports"):
        raise ApiError("FORBIDDEN", "دسترسی مجاز نیست", http_status=403)
    # بررسی دسترسی - گزارشات معمولاً نیاز به دسترسی خواندن دارند
    # اما اگر این endpoint خاص نیاز به دسترسی خاصی ندارد، می‌توانیم این بررسی را حذف کنیم
    # یا دسترسی را به صورت optional در نظر بگیریم
    # برای اکنون، بررسی می‌کنیم که آیا کاربر دسترسی خواندن گزارشات دارد یا نه
    try:
        if ctx and hasattr(ctx, 'can_read_section'):
            if not ctx.can_read_section("reports"):
                raise ApiError("FORBIDDEN", "دسترسی مجاز نیست", http_status=403)
    except AttributeError:
        # اگر متد can_read_section وجود نداشت، به کاربر اجازه می‌دهیم
        pass
    
    # دریافت سال مالی از header یا body
    fiscal_year_id = None
    fy_header = request.headers.get('X-Fiscal-Year-ID')
    if fy_header:
        try:
            fiscal_year_id = int(fy_header)
        except (ValueError, TypeError):
            pass
    
    if body.get('fiscal_year_id'):
        try:
            fiscal_year_id = int(body['fiscal_year_id'])
        except (ValueError, TypeError):
            pass
    
    # استخراج پارامترها از body
    date_from = body.get('date_from')
    date_to = body.get('date_to')
    currency_id = body.get('currency_id')
    account_type = body.get('account_type')
    include_zero_balance = body.get('include_zero_balance', False)
    account_id = body.get('account_id')  # برای دریافت جزئیات یک حساب خاص
    
    if currency_id is not None:
        try:
            currency_id = int(currency_id)
        except (ValueError, TypeError):
            currency_id = None
    
    if account_id is not None:
        try:
            account_id = int(account_id)
        except (ValueError, TypeError):
            account_id = None
    
    # Pagination (فقط برای جزئیات)
    skip = body.get('skip', 0)
    take = body.get('take', 50)
    try:
        skip = int(skip)
        take = int(take)
        if take > 500:
            take = 500
        if take < 1:
            take = 50
        if skip < 0:
            skip = 0
    except (ValueError, TypeError):
        skip = 0
        take = 50
    
    result = get_accounts_review_report(
        db=db,
        business_id=business_id,
        fiscal_year_id=fiscal_year_id,
        currency_id=currency_id,
        date_from=date_from,
        date_to=date_to,
        account_type=account_type,
        include_zero_balance=include_zero_balance,
        account_id=account_id,
        skip=skip,
        take=take,
    )
    
    # Format datetime fields
    def _format_accounts(accounts: list[Dict[str, Any]]) -> list[Dict[str, Any]]:
        formatted = []
        for acc in accounts:
            formatted_acc = dict(acc)
            if formatted_acc.get('children'):
                formatted_acc['children'] = _format_accounts(formatted_acc['children'])
            formatted.append(formatted_acc)
        return formatted
    
    result['accounts'] = _format_accounts(result.get('accounts', []))
    
    if result.get('account_details'):
        result['account_details'] = [format_datetime_fields(item, request) for item in result['account_details']]
    
    locale = negotiate_locale(request.headers.get("Accept-Language"))
    return success_response(
        data=result,
        message="Accounts review report retrieved successfully" if locale != 'fa' else "گزارش مرور حساب‌ها با موفقیت دریافت شد",
        request=request
    )

