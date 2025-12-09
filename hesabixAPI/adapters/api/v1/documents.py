"""
API endpoints برای مدیریت اسناد حسابداری (General Accounting Documents)
"""

from typing import Any, Dict, List
from fastapi import APIRouter, Depends, Request, Body, Query
from fastapi.responses import Response
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from adapters.db.models.document import Document
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access, require_business_management_dep, require_business_permission_dep, require_business_permission_by_entity_dep
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
from app.services.journal_ledger_service import get_journal_ledger_report
from app.core.i18n import negotiate_locale
from app.services.pdf.template_renderer import render_template
from adapters.api.v1.schema_models.document import (
    CreateManualDocumentRequest,
    UpdateManualDocumentRequest,
)


router = APIRouter(tags=["حسابداری"])


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
    
    # بررسی دسترسی برای هر document
    # اگر business_id ندارند یا دسترسی ندارند، خطا برمی‌گردانیم
    from adapters.db.models.document import Document as DocumentModel
    from adapters.db.repositories.business_permission_repo import BusinessPermissionRepository
    permission_repo = BusinessPermissionRepository(db)
    
    for doc_id in document_ids:
        try:
            doc = db.get(DocumentModel, doc_id)
            if doc:
                business_id = doc.business_id
                if not ctx.can_access_business(business_id):
                    raise ApiError("FORBIDDEN", f"No access to document {doc_id}", http_status=403)
                
                # بررسی دسترسی جزئی برای business_id مشخص
                if ctx.is_superadmin() or ctx.is_business_owner(business_id):
                    continue  # SuperAdmin و مالک تمام دسترسی‌ها را دارند
                
                permission_obj = permission_repo.get_by_user_and_business(ctx.get_user_id(), business_id)
                if not permission_obj or not permission_obj.business_permissions:
                    raise ApiError("FORBIDDEN", f"Missing permission: accounting_documents.delete for document {doc_id}", http_status=403)
                
                permissions = ctx._normalize_permissions_value(permission_obj.business_permissions)
                if "accounting_documents" not in permissions:
                    raise ApiError("FORBIDDEN", f"Missing permission: accounting_documents.delete for document {doc_id}", http_status=403)
                
                section_perms = permissions.get("accounting_documents", {})
                if not section_perms.get("delete", False):
                    raise ApiError("FORBIDDEN", f"Missing permission: accounting_documents.delete for document {doc_id}", http_status=403)
        except ApiError:
            raise
        except Exception:
            continue
    
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
    _: None = Depends(require_business_permission_dep("accounting_documents", "add")),
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
    _: None = Depends(require_business_permission_by_entity_dep("accounting_documents", "edit", Document, "document_id")),
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
    items = [format_datetime_fields(item, request) for item in items]
    
    # Get calendar type
    calendar_type = "gregorian"
    if hasattr(request.state, 'calendar_type'):
        calendar_type = request.state.calendar_type
    
    # Helper function to format date based on calendar type
    def format_date_for_export(item_dict: dict, date_key: str) -> str:
        """Format date based on calendar type (date only, no time)"""
        from app.core.calendar import CalendarConverter
        
        # First check if there's a _formatted field (from format_datetime_fields)
        formatted_key = f"{date_key}_formatted"
        if formatted_key in item_dict:
            formatted_value = item_dict.get(formatted_key)
            if isinstance(formatted_value, dict):
                date_only = formatted_value.get("date_only")
                if date_only:
                    return str(date_only)
                formatted = formatted_value.get("formatted", "")
                if formatted:
                    # Extract date part only (remove time)
                    date_part = str(formatted).split(' ')[0].split('T')[0]
                    return date_part
        
        # Get the main field value
        value = item_dict.get(date_key)
        if value is None:
            return ""
        
        # If it's a dict (from _formatted field), use date_only
        if isinstance(value, dict):
            date_only = value.get("date_only")
            if date_only:
                return str(date_only)
            formatted = value.get("formatted", "")
            if formatted:
                date_part = str(formatted).split(' ')[0].split('T')[0]
                return date_part
        
        # If it's a datetime object, format it based on calendar type
        if isinstance(value, datetime.datetime):
            try:
                formatted = CalendarConverter.format_datetime(value, calendar_type)
                return formatted.get("date_only", "") or formatted.get("formatted", "").split(' ')[0]
            except Exception:
                pass
        
        # If it's a date object, format it based on calendar type
        if isinstance(value, datetime.date):
            try:
                dt_value = datetime.datetime.combine(value, datetime.datetime.min.time())
                formatted = CalendarConverter.format_datetime(dt_value, calendar_type)
                return formatted.get("date_only", "") or formatted.get("formatted", "").split(' ')[0]
            except Exception:
                pass
        
        # If it's a string, check if it's already formatted (contains / separator for Jalali)
        if isinstance(value, str):
            # Check if it looks like a Jalali date (contains / and has YYYY/MM/DD format)
            if '/' in value and (len(value.split('/')) == 3):
                # Might be already formatted, but check if it's ISO format (YYYY-MM-DD) or Jalali (YYYY/MM/DD)
                if '-' in value:
                    # ISO format (YYYY-MM-DD), parse and format
                    try:
                        if 'T' in value:
                            dt_value = datetime.datetime.fromisoformat(value.replace('Z', '+00:00'))
                        else:
                            date_value = datetime.date.fromisoformat(value)
                            dt_value = datetime.datetime.combine(date_value, datetime.datetime.min.time())
                        formatted = CalendarConverter.format_datetime(dt_value, calendar_type)
                        return formatted.get("date_only", "") or formatted.get("formatted", "").split(' ')[0]
                    except Exception:
                        pass
                else:
                    # Might be Jalali format (YYYY/MM/DD), return as is but remove time if exists
                    if ' ' in value:
                        return value.split(' ')[0]
                    return value
            else:
                # Try to parse as ISO format
                try:
                    if 'T' in value:
                        dt_value = datetime.datetime.fromisoformat(value.replace('Z', '+00:00'))
                    else:
                        date_value = datetime.date.fromisoformat(value)
                        dt_value = datetime.datetime.combine(date_value, datetime.datetime.min.time())
                    formatted = CalendarConverter.format_datetime(dt_value, calendar_type)
                    return formatted.get("date_only", "") or formatted.get("formatted", "").split(' ')[0]
                except Exception:
                    # If parsing fails, return as is (might already be formatted)
                    if ' ' in value or 'T' in value:
                        date_part = value.split(' ')[0].split('T')[0]
                        return date_part
                    return value
        
        # Fallback
        return str(value) if value else ""
    
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
                value = format_date_for_export(item, 'last_purchase_date')
            
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
    
    # Get calendar type
    calendar_type = "gregorian"
    if hasattr(request.state, 'calendar_type'):
        calendar_type = request.state.calendar_type
    
    # Helper function to format date based on calendar type
    def format_date_for_export(item_dict: dict, date_key: str) -> str:
        """Format date based on calendar type (date only, no time)"""
        from app.core.calendar import CalendarConverter
        
        # First check if there's a _formatted field (from format_datetime_fields)
        formatted_key = f"{date_key}_formatted"
        if formatted_key in item_dict:
            formatted_value = item_dict.get(formatted_key)
            if isinstance(formatted_value, dict):
                date_only = formatted_value.get("date_only")
                if date_only:
                    return str(date_only)
                formatted = formatted_value.get("formatted", "")
                if formatted:
                    # Extract date part only (remove time)
                    date_part = str(formatted).split(' ')[0].split('T')[0]
                    return date_part
        
        # Get the main field value
        value = item_dict.get(date_key)
        if value is None:
            return ""
        
        # If it's a dict (from _formatted field), use date_only
        if isinstance(value, dict):
            date_only = value.get("date_only")
            if date_only:
                return str(date_only)
            formatted = value.get("formatted", "")
            if formatted:
                date_part = str(formatted).split(' ')[0].split('T')[0]
                return date_part
        
        # If it's a datetime object, format it based on calendar type
        if isinstance(value, datetime.datetime):
            try:
                formatted = CalendarConverter.format_datetime(value, calendar_type)
                return formatted.get("date_only", "") or formatted.get("formatted", "").split(' ')[0]
            except Exception:
                pass
        
        # If it's a date object, format it based on calendar type
        if isinstance(value, datetime.date):
            try:
                dt_value = datetime.datetime.combine(value, datetime.datetime.min.time())
                formatted = CalendarConverter.format_datetime(dt_value, calendar_type)
                return formatted.get("date_only", "") or formatted.get("formatted", "").split(' ')[0]
            except Exception:
                pass
        
        # If it's a string, check if it's already formatted (contains / separator for Jalali)
        if isinstance(value, str):
            # Check if it looks like a Jalali date (contains / and has YYYY/MM/DD format)
            if '/' in value and (len(value.split('/')) == 3):
                # Might be already formatted, but check if it's ISO format (YYYY-MM-DD) or Jalali (YYYY/MM/DD)
                if '-' in value:
                    # ISO format (YYYY-MM-DD), parse and format
                    try:
                        if 'T' in value:
                            dt_value = datetime.datetime.fromisoformat(value.replace('Z', '+00:00'))
                        else:
                            date_value = datetime.date.fromisoformat(value)
                            dt_value = datetime.datetime.combine(date_value, datetime.datetime.min.time())
                        formatted = CalendarConverter.format_datetime(dt_value, calendar_type)
                        return formatted.get("date_only", "") or formatted.get("formatted", "").split(' ')[0]
                    except Exception:
                        pass
                else:
                    # Might be Jalali format (YYYY/MM/DD), return as is but remove time if exists
                    if ' ' in value:
                        return value.split(' ')[0]
                    return value
            else:
                # Try to parse as ISO format
                try:
                    if 'T' in value:
                        dt_value = datetime.datetime.fromisoformat(value.replace('Z', '+00:00'))
                    else:
                        date_value = datetime.date.fromisoformat(value)
                        dt_value = datetime.datetime.combine(date_value, datetime.datetime.min.time())
                    formatted = CalendarConverter.format_datetime(dt_value, calendar_type)
                    return formatted.get("date_only", "") or formatted.get("formatted", "").split(' ')[0]
                except Exception:
                    # If parsing fails, return as is (might already be formatted)
                    if ' ' in value or 'T' in value:
                        date_part = value.split(' ')[0].split('T')[0]
                        return date_part
                    return value
        
        # Fallback
        return str(value) if value else ""
    
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
                value = format_date_for_export(item, 'date')
            
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
    project_id = body.get('project_id')  # 🆕 فیلتر پروژه
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
    
    # 🆕 تبدیل نوع project_id
    if project_id is not None:
        try:
            project_id = int(project_id)
        except (ValueError, TypeError):
            project_id = None
    
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
        project_id=project_id,  # 🆕 پاس دادن به سرویس
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
    project_id = body.get('project_id')  # 🆕 فیلتر پروژه
    
    if currency_id is not None:
        try:
            currency_id = int(currency_id)
        except (ValueError, TypeError):
            currency_id = None
    
    # 🆕 تبدیل نوع project_id
    if project_id is not None:
        try:
            project_id = int(project_id)
        except (ValueError, TypeError):
            project_id = None
    
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
        project_id=project_id,  # 🆕 پاس دادن به سرویس
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
    project_id = body.get('project_id')  # 🆕 فیلتر پروژه
    
    if currency_id is not None:
        try:
            currency_id = int(currency_id)
        except (ValueError, TypeError):
            currency_id = None
    
    # 🆕 تبدیل نوع project_id
    if project_id is not None:
        try:
            project_id = int(project_id)
        except (ValueError, TypeError):
            project_id = None
    
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
        project_id=project_id,  # 🆕 پاس دادن به سرویس
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


@router.post(
    "/businesses/{business_id}/reports/journal-ledger",
    summary="گزارش دفتر روزنامه",
    description="گزارش دفتر روزنامه - تمام تراکنش‌های مالی به ترتیب تاریخ (Journal Ledger)",
)
@require_business_access("business_id")
async def journal_ledger_report_endpoint(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(default={}),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    """گزارش دفتر روزنامه - تمام تراکنش‌های مالی به ترتیب تاریخ"""
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
    document_type = body.get('document_type')
    include_proforma = body.get('include_proforma', False)
    
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
    
    result = get_journal_ledger_report(
        db=db,
        business_id=business_id,
        fiscal_year_id=fiscal_year_id,
        currency_id=currency_id,
        date_from=date_from,
        date_to=date_to,
        document_type=document_type,
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
        message="Journal ledger report retrieved successfully" if locale != 'fa' else "گزارش دفتر روزنامه با موفقیت دریافت شد",
        request=request
    )


@router.post(
    "/businesses/{business_id}/reports/journal-ledger/export/excel",
    summary="خروجی Excel گزارش دفتر روزنامه",
    description="خروجی Excel گزارش دفتر روزنامه با قابلیت فیلتر، انتخاب سطرها و رعایت ترتیب/نمایش ستون‌ها",
)
@require_business_access("business_id")
async def export_journal_ledger_report_excel(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(default={}),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """خروجی Excel گزارش دفتر روزنامه"""
    import io
    import json
    import datetime
    import re
    from openpyxl import Workbook
    from openpyxl.styles import Font, Alignment, PatternFill, Border, Side
    from fastapi.responses import Response
    from adapters.db.models.business import Business
    from app.core.calendar import CalendarConverter, CalendarType
    
    # بررسی دسترسی
    if not ctx.can_read_section("reports"):
        raise ApiError("FORBIDDEN", "Missing business permission: reports.read", http_status=403)
    
    # دریافت calendar_type از request state
    calendar_type: CalendarType = "gregorian"
    if hasattr(request.state, 'calendar_type'):
        calendar_type = request.state.calendar_type
    
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
    document_type = body.get('document_type')
    include_proforma = body.get('include_proforma', False)
    
    if currency_id is not None:
        try:
            currency_id = int(currency_id)
        except (ValueError, TypeError):
            currency_id = None
    
    # برای export، همه رکوردها را بدون pagination می‌گیریم
    max_export_records = 10000
    result = get_journal_ledger_report(
        db=db,
        business_id=business_id,
        fiscal_year_id=fiscal_year_id,
        currency_id=currency_id,
        date_from=date_from,
        date_to=date_to,
        document_type=document_type,
        include_proforma=include_proforma,
        skip=0,
        take=max_export_records,
    )
    
    items = result.get('items', [])
    items = [format_datetime_fields(item, request) for item in items]
    
    # Helper function to format date based on calendar type
    def format_date_for_export(item_dict: dict, date_key: str) -> str:
        """Format date based on calendar type (date only, no time)"""
        # First check if there's a _formatted field (from format_datetime_fields)
        formatted_key = f"{date_key}_formatted"
        if formatted_key in item_dict:
            formatted_value = item_dict.get(formatted_key)
            if isinstance(formatted_value, dict):
                date_only = formatted_value.get("date_only")
                if date_only:
                    return str(date_only)
                formatted = formatted_value.get("formatted", "")
                if formatted:
                    # Extract date part only (remove time)
                    date_part = str(formatted).split(' ')[0].split('T')[0]
                    return date_part
        
        # Get the main field value
        value = item_dict.get(date_key)
        if value is None:
            return ""
        
        # If it's a dict (from _formatted field), use date_only
        if isinstance(value, dict):
            date_only = value.get("date_only")
            if date_only:
                return str(date_only)
            formatted = value.get("formatted", "")
            if formatted:
                date_part = str(formatted).split(' ')[0].split('T')[0]
                return date_part
        
        # If it's a datetime object, format it based on calendar type
        if isinstance(value, datetime.datetime):
            try:
                formatted = CalendarConverter.format_datetime(value, calendar_type)
                return formatted.get("date_only", "") or formatted.get("formatted", "").split(' ')[0]
            except Exception:
                pass
        
        # If it's a date object, format it based on calendar type
        if isinstance(value, datetime.date):
            try:
                dt_value = datetime.datetime.combine(value, datetime.datetime.min.time())
                formatted = CalendarConverter.format_datetime(dt_value, calendar_type)
                return formatted.get("date_only", "") or formatted.get("formatted", "").split(' ')[0]
            except Exception:
                pass
        
        # If it's a string, check if it's already formatted (contains Persian or has / separator for Jalali)
        if isinstance(value, str):
            # Check if it looks like a Jalali date (contains / and Persian numbers or has YYYY/MM/DD format)
            if '/' in value and (len(value.split('/')) == 3):
                # Might be already formatted, but check if it's ISO format (YYYY-MM-DD) or Jalali (YYYY/MM/DD)
                if '-' in value:
                    # ISO format (YYYY-MM-DD), parse and format
                    try:
                        if 'T' in value:
                            dt_value = datetime.datetime.fromisoformat(value.replace('Z', '+00:00'))
                        else:
                            date_value = datetime.date.fromisoformat(value)
                            dt_value = datetime.datetime.combine(date_value, datetime.datetime.min.time())
                        formatted = CalendarConverter.format_datetime(dt_value, calendar_type)
                        return formatted.get("date_only", "") or formatted.get("formatted", "").split(' ')[0]
                    except Exception:
                        pass
                else:
                    # Might be Jalali format (YYYY/MM/DD), return as is but remove time if exists
                    if ' ' in value:
                        return value.split(' ')[0]
                    return value
            else:
                # Try to parse as ISO format
                try:
                    if 'T' in value:
                        dt_value = datetime.datetime.fromisoformat(value.replace('Z', '+00:00'))
                    else:
                        date_value = datetime.date.fromisoformat(value)
                        dt_value = datetime.datetime.combine(date_value, datetime.datetime.min.time())
                    formatted = CalendarConverter.format_datetime(dt_value, calendar_type)
                    return formatted.get("date_only", "") or formatted.get("formatted", "").split(' ')[0]
                except Exception:
                    # If parsing fails, return as is (might already be formatted)
                    if ' ' in value or 'T' in value:
                        date_part = value.split(' ')[0].split('T')[0]
                        return date_part
                    return value
        
        # Fallback
        return str(value) if value else ""
    
    # Helper function to get document type name in Persian
    def get_document_type_name_fa(doc_type: str | None) -> str:
        """تبدیل نوع سند به نام فارسی"""
        if not doc_type:
            return ''
        
        mapping = {
            'invoice_sales': 'فاکتور فروش',
            'invoice_sales_return': 'برگشت از فروش',
            'invoice_purchase': 'فاکتور خرید',
            'invoice_purchase_return': 'برگشت از خرید',
            'invoice_production': 'فاکتور تولید',
            'invoice_direct_consumption': 'مصرف مستقیم',
            'invoice_waste': 'ضایعات',
            'receipt': 'دریافت',
            'payment': 'پرداخت',
            'transfer': 'انتقال',
            'expense': 'هزینه',
            'income': 'درآمد',
            'expense_income': 'درآمد/هزینه',
            'opening_balance': 'تراز افتتاحیه',
            'manual': 'سند دستی',
            'manual_document': 'سند دستی',
            'check_endorse': 'پاسخگویی چک',
            'check_clear': 'وصول چک',
            'check_pay': 'پرداخت چک',
            'check_return': 'برگشت چک',
            'check_bounce': 'برگشت خوردن چک',
            'check_deposit': 'واریز به حساب',
            'check_delete': 'حذف چک',
        }
        return mapping.get(doc_type, doc_type)
    
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
    
    # Check if we hit the limit
    if len(items) >= max_export_records:
        warning_item = {
            'document_date': '',
            'document_code': '⚠️',
            'document_type_name': 'حداکثر ۱۰,۰۰۰ رکورد قابل export است',
            'description': '',
            'general_account_code': '',
            'general_account_name': '',
            'subsidiary_account_code': '',
            'subsidiary_account_name': '',
            'debit_account_code': '',
            'debit_account_name': '',
            'debit_amount': '',
            'credit_account_code': '',
            'credit_account_name': '',
            'credit_amount': '',
            'person_name': '',
        }
        items.append(warning_item)
    
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
            ('document_date', 'تاریخ سند' if is_fa else 'Document Date'),
            ('document_type_name', 'نوع سند' if is_fa else 'Document Type'),
            ('document_code', 'شماره سند' if is_fa else 'Document Code'),
            ('description', 'شرح' if is_fa else 'Description'),
            ('general_account_code', 'کد حساب کل' if is_fa else 'General Account Code'),
            ('general_account_name', 'عنوان حساب کل' if is_fa else 'General Account Name'),
            ('subsidiary_account_code', 'کد حساب معین' if is_fa else 'Subsidiary Account Code'),
            ('subsidiary_account_name', 'عنوان حساب معین' if is_fa else 'Subsidiary Account Name'),
            ('debit_account_code', 'کد حساب بدهکار' if is_fa else 'Debit Account Code'),
            ('debit_account_name', 'نام حساب بدهکار' if is_fa else 'Debit Account Name'),
            ('debit_amount', 'مبلغ بدهکار' if is_fa else 'Debit Amount'),
            ('credit_account_code', 'کد حساب بستانکار' if is_fa else 'Credit Account Code'),
            ('credit_account_name', 'نام حساب بستانکار' if is_fa else 'Credit Account Name'),
            ('credit_amount', 'مبلغ بستانکار' if is_fa else 'Credit Amount'),
            ('person_name', 'طرف حساب' if is_fa else 'Counterpart'),
        ]
        for key, label in default_columns:
            keys.append(key)
            headers.append(label)
    
    # Create workbook
    wb = Workbook()
    ws = wb.active
    ws.title = "دفتر روزنامه" if is_fa else "Journal Ledger"
    
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
            
            # Format dates based on calendar type
            if key == 'document_date' and value:
                value = format_date_for_export(item, 'document_date')
            
            # Format document type name (ensure it's in Persian)
            if key == 'document_type_name':
                # Always use document_type to get the correct translation
                doc_type = item.get('document_type', '')
                if doc_type:
                    value = get_document_type_name_fa(doc_type)
                elif value:
                    # If document_type is not available, check if value is English and translate
                    # Check if value contains Persian characters
                    has_persian = any('\u0600' <= c <= '\u06FF' for c in str(value))
                    if not has_persian:
                        # Value is likely in English, try to translate it
                        value = get_document_type_name_fa(value)
                else:
                    value = ""
            
            # Format numbers
            if key in ['debit_amount', 'credit_amount'] and value:
                try:
                    num_value = float(value) if not isinstance(value, (int, float)) else value
                    value = num_value
                except (ValueError, TypeError):
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
                    if max_length < cell_length:
                        max_length = cell_length
            except Exception:
                pass
        ws.column_dimensions[column_letter].width = min(max_length + 2, 50)
    
    # Add summary row at the end
    summary_row = len(items) + 3
    ws.cell(row=summary_row, column=1, value="جمع" if is_fa else "Total").font = Font(bold=True)
    ws.cell(row=summary_row, column=1).border = border
    
    # Find debit_amount and credit_amount column indices
    debit_col_idx = None
    credit_col_idx = None
    for idx, key in enumerate(keys, 1):
        if key == 'debit_amount':
            debit_col_idx = idx
        elif key == 'credit_amount':
            credit_col_idx = idx
    
    if debit_col_idx:
        total_debit = result.get('summary', {}).get('total_debit', 0)
        ws.cell(row=summary_row, column=debit_col_idx, value=float(total_debit)).font = Font(bold=True)
        ws.cell(row=summary_row, column=debit_col_idx).border = border
        if locale == 'fa':
            ws.cell(row=summary_row, column=debit_col_idx).alignment = Alignment(horizontal="right")
    
    if credit_col_idx:
        total_credit = result.get('summary', {}).get('total_credit', 0)
        ws.cell(row=summary_row, column=credit_col_idx, value=float(total_credit)).font = Font(bold=True)
        ws.cell(row=summary_row, column=credit_col_idx).border = border
        if locale == 'fa':
            ws.cell(row=summary_row, column=credit_col_idx).alignment = Alignment(horizontal="right")
    
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
    
    base = "journal_ledger_report"
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
    "/businesses/{business_id}/reports/journal-ledger/export/pdf",
    summary="خروجی PDF گزارش دفتر روزنامه",
    description="خروجی PDF گزارش دفتر روزنامه با قابلیت فیلتر، انتخاب سطرها و رعایت ترتیب/نمایش ستون‌ها",
)
@require_business_access("business_id")
async def export_journal_ledger_report_pdf(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(default={}),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """خروجی PDF گزارش دفتر روزنامه"""
    from weasyprint import HTML
    from weasyprint.text.fonts import FontConfiguration
    from html import escape
    import datetime
    import re
    import json
    from adapters.db.models.business import Business
    from app.core.calendar import CalendarConverter, CalendarType
    
    # بررسی دسترسی
    if not ctx.can_read_section("reports"):
        raise ApiError("FORBIDDEN", "Missing business permission: reports.read", http_status=403)
    
    # دریافت calendar_type از request state
    calendar_type: CalendarType = "gregorian"
    if hasattr(request.state, 'calendar_type'):
        calendar_type = request.state.calendar_type
    
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
    document_type = body.get('document_type')
    include_proforma = body.get('include_proforma', False)
    
    if currency_id is not None:
        try:
            currency_id = int(currency_id)
        except (ValueError, TypeError):
            currency_id = None
    
    # برای export، همه رکوردها را بدون pagination می‌گیریم
    max_export_records = 10000
    result = get_journal_ledger_report(
        db=db,
        business_id=business_id,
        fiscal_year_id=fiscal_year_id,
        currency_id=currency_id,
        date_from=date_from,
        date_to=date_to,
        document_type=document_type,
        include_proforma=include_proforma,
        skip=0,
        take=max_export_records,
    )
    
    items = result.get('items', [])
    items = [format_datetime_fields(item, request) for item in items]
    
    # Helper function to format date based on calendar type
    def format_date_for_export(item_dict: dict, date_key: str) -> str:
        """Format date based on calendar type (date only, no time)"""
        formatted_key = f"{date_key}_formatted"
        if formatted_key in item_dict:
            formatted_value = item_dict.get(formatted_key)
            if isinstance(formatted_value, dict):
                date_only = formatted_value.get("date_only")
                if date_only:
                    return str(date_only)
                formatted = formatted_value.get("formatted", "")
                if formatted:
                    date_part = str(formatted).split(' ')[0].split('T')[0]
                    return date_part
        
        value = item_dict.get(date_key)
        if value is None:
            return ""
        
        if isinstance(value, dict):
            date_only = value.get("date_only")
            if date_only:
                return str(date_only)
            formatted = value.get("formatted", "")
            if formatted:
                date_part = str(formatted).split(' ')[0].split('T')[0]
                return date_part
        
        if isinstance(value, datetime.datetime):
            try:
                formatted = CalendarConverter.format_datetime(value, calendar_type)
                return formatted.get("date_only", "") or formatted.get("formatted", "").split(' ')[0]
            except Exception:
                pass
        
        if isinstance(value, datetime.date):
            try:
                dt_value = datetime.datetime.combine(value, datetime.datetime.min.time())
                formatted = CalendarConverter.format_datetime(dt_value, calendar_type)
                return formatted.get("date_only", "") or formatted.get("formatted", "").split(' ')[0]
            except Exception:
                pass
        
        if isinstance(value, str):
            if '/' in value and (len(value.split('/')) == 3):
                if '-' in value:
                    try:
                        if 'T' in value:
                            dt_value = datetime.datetime.fromisoformat(value.replace('Z', '+00:00'))
                        else:
                            date_value = datetime.date.fromisoformat(value)
                            dt_value = datetime.datetime.combine(date_value, datetime.datetime.min.time())
                        formatted = CalendarConverter.format_datetime(dt_value, calendar_type)
                        return formatted.get("date_only", "") or formatted.get("formatted", "").split(' ')[0]
                    except Exception:
                        pass
                else:
                    if ' ' in value:
                        return value.split(' ')[0]
                    return value
            else:
                try:
                    if 'T' in value:
                        dt_value = datetime.datetime.fromisoformat(value.replace('Z', '+00:00'))
                    else:
                        date_value = datetime.date.fromisoformat(value)
                        dt_value = datetime.datetime.combine(date_value, datetime.datetime.min.time())
                    formatted = CalendarConverter.format_datetime(dt_value, calendar_type)
                    return formatted.get("date_only", "") or formatted.get("formatted", "").split(' ')[0]
                except Exception:
                    if ' ' in value or 'T' in value:
                        date_part = value.split(' ')[0].split('T')[0]
                        return date_part
                    return value
        
        return str(value) if value else ""
    
    # Helper function to get document type name in Persian
    def get_document_type_name_fa(doc_type: str | None) -> str:
        """تبدیل نوع سند به نام فارسی"""
        if not doc_type:
            return ''
        
        mapping = {
            'invoice_sales': 'فاکتور فروش',
            'invoice_sales_return': 'برگشت از فروش',
            'invoice_purchase': 'فاکتور خرید',
            'invoice_purchase_return': 'برگشت از خرید',
            'invoice_production': 'فاکتور تولید',
            'invoice_direct_consumption': 'مصرف مستقیم',
            'invoice_waste': 'ضایعات',
            'receipt': 'دریافت',
            'payment': 'پرداخت',
            'transfer': 'انتقال',
            'expense': 'هزینه',
            'income': 'درآمد',
            'expense_income': 'درآمد/هزینه',
            'opening_balance': 'تراز افتتاحیه',
            'manual': 'سند دستی',
            'manual_document': 'سند دستی',
            'check_endorse': 'پاسخگویی چک',
            'check_clear': 'وصول چک',
            'check_pay': 'پرداخت چک',
            'check_return': 'برگشت چک',
            'check_bounce': 'برگشت خوردن چک',
            'check_deposit': 'واریز به حساب',
            'check_delete': 'حذف چک',
        }
        return mapping.get(doc_type, doc_type)
    
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
    
    # Check if we hit the limit
    if len(items) >= max_export_records:
        warning_item = {
            'document_date': '',
            'document_code': '⚠️',
            'document_type_name': 'حداکثر ۱۰,۰۰۰ رکورد قابل export است',
            'description': '',
            'general_account_code': '',
            'general_account_name': '',
            'subsidiary_account_code': '',
            'subsidiary_account_name': '',
            'debit_account_code': '',
            'debit_account_name': '',
            'debit_amount': '',
            'credit_account_code': '',
            'credit_account_name': '',
            'credit_amount': '',
            'person_name': '',
        }
        items.append(warning_item)
    
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
            ('document_date', 'تاریخ سند' if is_fa else 'Document Date'),
            ('document_type_name', 'نوع سند' if is_fa else 'Document Type'),
            ('document_code', 'شماره سند' if is_fa else 'Document Code'),
            ('description', 'شرح' if is_fa else 'Description'),
            ('general_account_code', 'کد حساب کل' if is_fa else 'General Account Code'),
            ('general_account_name', 'عنوان حساب کل' if is_fa else 'General Account Name'),
            ('subsidiary_account_code', 'کد حساب معین' if is_fa else 'Subsidiary Account Code'),
            ('subsidiary_account_name', 'عنوان حساب معین' if is_fa else 'Subsidiary Account Name'),
            ('debit_account', 'حساب بدهکار' if is_fa else 'Debit Account'),
            ('debit_amount', 'مبلغ بدهکار' if is_fa else 'Debit Amount'),
            ('credit_account', 'حساب بستانکار' if is_fa else 'Credit Account'),
            ('credit_amount', 'مبلغ بستانکار' if is_fa else 'Credit Amount'),
            ('person_name', 'طرف حساب' if is_fa else 'Counterpart'),
        ]
        for key, label in default_columns:
            keys.append(key)
            headers.append(label)
    
    # Get business name
    business_name = ""
    try:
        b = db.query(Business).filter(Business.id == business_id).first()
        if b is not None:
            business_name = b.name or ""
    except Exception:
        business_name = ""
    
    # Prepare data for HTML
    now = datetime.datetime.now().strftime('%Y/%m/%d %H:%M')
    title_text = "گزارش دفتر روزنامه" if is_fa else "Journal Ledger Report"
    label_biz = "کسب و کار" if is_fa else "Business"
    label_date = "تاریخ تولید" if is_fa else "Generated Date"
    footer_text = f"تولید شده در {now}" if is_fa else f"Generated at {now}"
    
    # Create headers HTML
    headers_html = ''.join(f'<th>{escape(header)}</th>' for header in headers)
    
    # Create rows HTML
    rows_html = []
    for item in items:
        row_cells = []
        for key in keys:
            value = item.get(key, "")
            
            # Format dates based on calendar type
            if key == 'document_date' and value:
                value = format_date_for_export(item, 'document_date')
            
            # Format document type name (ensure it's in Persian)
            if key == 'document_type_name':
                doc_type = item.get('document_type', '')
                if doc_type:
                    value = get_document_type_name_fa(doc_type)
                elif value:
                    has_persian = any('\u0600' <= c <= '\u06FF' for c in str(value))
                    if not has_persian:
                        value = get_document_type_name_fa(value)
                else:
                    value = ""
            
            # Format numbers
            if key in ['debit_amount', 'credit_amount'] and value:
                try:
                    num_value = float(value) if not isinstance(value, (int, float)) else value
                    value = f"{num_value:,.0f}" if is_fa else f"{num_value:,.2f}"
                except (ValueError, TypeError):
                    pass
            
            # Handle debit_account and credit_account (they might be formatted as "code - name")
            if key in ['debit_account', 'credit_account']:
                debit_code = item.get('debit_account_code', '')
                debit_name = item.get('debit_account_name', '')
                credit_code = item.get('credit_account_code', '')
                credit_name = item.get('credit_account_name', '')
                if key == 'debit_account':
                    if debit_code and debit_name:
                        value = f"{debit_code} - {debit_name}"
                    elif debit_code:
                        value = debit_code
                    elif debit_name:
                        value = debit_name
                elif key == 'credit_account':
                    if credit_code and credit_name:
                        value = f"{credit_code} - {credit_name}"
                    elif credit_code:
                        value = credit_code
                    elif credit_name:
                        value = credit_name
            
            if isinstance(value, list):
                value = ", ".join(str(v) for v in value)
            elif isinstance(value, dict):
                value = str(value)
            
            row_cells.append(f'<td>{escape(str(value))}</td>')
        rows_html.append(f'<tr>{"".join(row_cells)}</tr>')
    
    # Add summary row
    summary = result.get('summary', {})
    total_debit = summary.get('total_debit', 0)
    total_credit = summary.get('total_credit', 0)
    
    # Find debit_amount and credit_amount column indices
    debit_col_idx = None
    credit_col_idx = None
    for idx, key in enumerate(keys):
        if key == 'debit_amount':
            debit_col_idx = idx
        elif key == 'credit_amount':
            credit_col_idx = idx
    
    # ساخت summary row (جدا از rows_html تا در آخرین صفحه قرار بگیرد)
    summary_row_cells = ['<td></td>'] * len(keys)
    summary_row_cells[0] = f'<td><strong>{"جمع" if is_fa else "Total"}</strong></td>'
    if debit_col_idx is not None:
        debit_format = f"{total_debit:,.0f}" if is_fa else f"{total_debit:,.2f}"
        summary_row_cells[debit_col_idx] = f'<td><strong>{debit_format}</strong></td>'
    if credit_col_idx is not None:
        credit_format = f"{total_credit:,.0f}" if is_fa else f"{total_credit:,.2f}"
        summary_row_cells[credit_col_idx] = f'<td><strong>{credit_format}</strong></td>'
    summary_row_html = f'<tr class="summary-row">{"".join(summary_row_cells)}</tr>'
    
    # کانتکست برای قالب سفارشی لیست
    template_context: Dict[str, Any] = {
        "title_text": title_text,
        "business_name": business_name,
        "generated_at": now,
        "is_fa": is_fa,
        "headers": headers,
        "keys": keys,
        "items": items,
        "table_headers_html": headers_html,
        "table_rows_html": "".join(rows_html),
        "summary": summary,
    }
    
    # تلاش برای رندر با قالب سفارشی (journal_ledger/list)
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
            module_key="journal_ledger",
            subtype="list",
            context=template_context,
            explicit_template_id=explicit_template_id,
        )
    except Exception:
        resolved_html = None
    
    # HTML پیش‌فرض جدول با قالب فایل
    disposition = "attachment"
    try:
        disposition = str(body.get("disposition") or "attachment")
    except Exception:
        disposition = "attachment"
    paper_size = body.get("paper_size") or "A4"
    orientation = body.get("orientation") or "landscape"  # پیش‌فرض افقی
    
    # تقسیم سطرها به صفحات (حداکثر 25 سطر در هر صفحه برای A4 landscape)
    rows_per_page = 25
    total_rows = len(rows_html)
    pages_data = []
    
    for i in range(0, total_rows, rows_per_page):
        page_rows = rows_html[i:i + rows_per_page]
        pages_data.append(page_rows)
    
    # ساخت HTML برای هر صفحه با header در هر صفحه
    page_label_left = "صفحه " if is_fa else "Page "
    page_label_of = " از " if is_fa else " of "
    
    pages_html = []
    for page_num, page_rows in enumerate(pages_data, 1):
        is_last_page = page_num == len(pages_data)
        # در آخرین صفحه، summary row را اضافه می‌کنیم
        tbody_content = "".join(page_rows)
        if is_last_page:
            tbody_content += summary_row_html
        
        page_html = f"""
        <div class="page-container">
            <div class="header">
                <div>
                    <div class="title">{title_text}</div>
                    {f'<div class="meta"><strong>{label_biz}:</strong> {escape(business_name)}</div>' if business_name else ''}
                </div>
                <div class="meta">{label_date}: {now}</div>
            </div>
            <table class="report-table">
                <thead>
                    <tr>{headers_html}</tr>
                </thead>
                <tbody>
                    {tbody_content}
                </tbody>
            </table>
            {f'<div class="footer">{footer_text}</div>' if is_last_page else ''}
        </div>
        """
        pages_html.append(page_html)
    
    # Use default template if custom template not found
    final_html = resolved_html or f"""
    <!DOCTYPE html>
    <html lang="{'fa' if is_fa else 'en'}" dir="{'rtl' if is_fa else 'ltr'}">
    <head>
        <meta charset="UTF-8">
        <title>{title_text}</title>
        <style>
            @page {{
                size: {paper_size} {orientation};
                margin: 12mm;
                @bottom-{'left' if is_fa else 'right'} {{
                    content: "{page_label_left}" counter(page) "{page_label_of}" counter(pages);
                    font-size: 10px;
                    color: #666;
                }}
            }}
            body {{
                font-family: {'Tahoma, Arial' if is_fa else 'Arial, sans-serif'};
                direction: {'rtl' if is_fa else 'ltr'};
                font-size: 11px;
                color: #222;
                margin: 0;
                padding: 0;
            }}
            .page-container {{
                page-break-after: always;
                min-height: 100%;
            }}
            .page-container:last-child {{
                page-break-after: auto;
            }}
            .header {{
                display: flex;
                justify-content: space-between;
                align-items: center;
                margin-bottom: 10px;
                border-bottom: 2px solid #444;
                padding-bottom: 6px;
            }}
            .title {{
                font-size: 16px;
                font-weight: 700;
                color: #366092;
                margin-bottom: 4px;
            }}
            .meta {{
                font-size: 11px;
                color: #555;
            }}
            table.report-table {{
                width: 100%;
                border-collapse: collapse;
                table-layout: fixed;
                margin-top: 10px;
            }}
            thead {{
                display: table-header-group;
            }}
            thead th {{
                background: #366092;
                color: white;
                border: 1px solid #2a4a6e;
                padding: 8px 6px;
                text-align: {'right' if is_fa else 'left'};
                font-weight: 700;
                white-space: nowrap;
                font-size: 10px;
            }}
            tbody tr {{
                page-break-inside: avoid;
                break-inside: avoid;
            }}
            tbody tr:nth-child(even) {{
                background-color: #f2f2f2;
            }}
            tbody tr.summary-row {{
                background-color: #e8f4f8;
                font-weight: bold;
                page-break-inside: avoid;
            }}
            tbody tr.summary-row td {{
                border-top: 2px solid #366092;
            }}
            tbody td {{
                border: 1px solid #d7dde6;
                padding: 6px 5px;
                text-align: {'right' if is_fa else 'left'};
                vertical-align: top;
                overflow-wrap: anywhere;
                word-break: break-word;
                white-space: normal;
                font-size: 10px;
            }}
            .footer {{
                margin-top: 10px;
                font-size: 10px;
                color: #666;
                text-align: center;
                padding-top: 10px;
                border-top: 1px solid #ddd;
            }}
        </style>
    </head>
    <body>
        {"".join(pages_html)}
    </body>
    </html>
    """
    
    font_config = FontConfiguration()
    pdf_bytes = HTML(string=final_html).write_pdf(font_config=font_config)
    
    # Build meaningful filename
    def slugify(text: str) -> str:
        return re.sub(r"[^A-Za-z0-9_-]+", "_", text).strip("_")
    
    base = "journal_ledger_report"
    if business_name:
        base += f"_{slugify(business_name)}"
    if selected_only:
        base += "_selected"
    filename = f"{base}_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf"
    
    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f"{disposition}; filename={filename}",
            "Content-Length": str(len(pdf_bytes)),
            "Access-Control-Expose-Headers": "Content-Disposition",
        },
    )

