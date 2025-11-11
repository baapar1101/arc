from typing import Dict, Any, List, Optional
from fastapi import APIRouter, Depends, Request, Body
from fastapi.responses import Response
from sqlalchemy.orm import Session
from sqlalchemy import and_, or_
import io
import json
import datetime
import re

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access
from app.core.responses import success_response, format_datetime_fields
from adapters.api.v1.schemas import QueryInfo
from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.account import Account
from adapters.db.models.currency import Currency
from adapters.db.models.fiscal_year import FiscalYear
from adapters.db.models.business import Business
from app.services.invoice_service import (
    create_invoice,
    update_invoice,
    invoice_document_to_dict,
    SUPPORTED_INVOICE_TYPES,
)
from app.services.pdf.template_renderer import render_template


router = APIRouter(prefix="/invoices", tags=["invoices"])  # Stubs only


@router.post("/business/{business_id}")
@require_business_access("business_id")
def create_invoice_endpoint(
    request: Request,
    business_id: int,
    payload: Dict[str, Any] = Body(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    result = create_invoice(
        db=db,
        business_id=business_id,
        user_id=ctx.get_user_id(),
        data=payload,
    )
    return success_response(data=result, request=request, message="INVOICE_CREATED")


@router.put("/business/{business_id}/{invoice_id}")
@require_business_access("business_id")
def update_invoice_endpoint(
    request: Request,
    business_id: int,
    invoice_id: int,
    payload: Dict[str, Any] = Body(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    # Optional safety: ensure ownership
    doc = db.query(Document).filter(Document.id == invoice_id).first()
    if not doc or doc.business_id != business_id or doc.document_type not in SUPPORTED_INVOICE_TYPES:
        # Lazy import to avoid circular
        from app.core.responses import ApiError
        raise ApiError("DOCUMENT_NOT_FOUND", "Invoice document not found", http_status=404)
    result = update_invoice(
        db=db,
        document_id=invoice_id,
        user_id=ctx.get_user_id(),
        data=payload,
    )
    return success_response(data=result, request=request, message="INVOICE_UPDATED")


@router.get("/business/{business_id}/{invoice_id}")
@require_business_access("business_id")
def get_invoice_endpoint(
    request: Request,
    business_id: int,
    invoice_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    doc = db.query(Document).filter(Document.id == invoice_id).first()
    if not doc or doc.business_id != business_id or doc.document_type not in SUPPORTED_INVOICE_TYPES:
        from app.core.responses import ApiError
        raise ApiError("DOCUMENT_NOT_FOUND", "Invoice document not found", http_status=404)
    result = invoice_document_to_dict(db, doc)
    return success_response(data={"item": result}, request=request, message="INVOICE")

@router.get(
    "/business/{business_id}/{invoice_id}/pdf",
    summary="PDF یک فاکتور",
    description="دریافت فایل PDF یک فاکتور با پشتیبانی از قالب سفارشی (invoices/detail)",
)
@require_business_access("business_id")
async def export_single_invoice_pdf(
    business_id: int,
    invoice_id: int,
    request: Request,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    template_id: int | None = None,
):
    """
    خروجی PDF تک‌سند فاکتور با پشتیبانی از قالب سفارشی:
    - اگر template_id داده شود و منتشرشده باشد، همان استفاده می‌شود.
    - در غیر این صورت اگر قالب پیش‌فرض منتشرشده برای invoices/detail موجود باشد، استفاده می‌شود.
    - در نبود قالب، خروجی HTML پیش‌فرض تولید می‌شود.
    """
    from weasyprint import HTML
    from weasyprint.text.fonts import FontConfiguration
    from app.core.i18n import negotiate_locale
    from html import escape
    import datetime

    # دریافت سند و اعتبارسنجی
    doc = db.query(Document).filter(Document.id == invoice_id).first()
    if not doc or doc.business_id != business_id or doc.document_type not in SUPPORTED_INVOICE_TYPES:
        from app.core.responses import ApiError
        raise ApiError("DOCUMENT_NOT_FOUND", "Invoice document not found", http_status=404)

    # جزئیات کامل فاکتور
    item = invoice_document_to_dict(db, doc)

    # اطلاعات کسب‌وکار (اختیاری)
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

    # کانتکست قالب
    template_context = {
        "business_id": business_id,
        "business_name": business_name,
        "invoice": item,
        "lines": item.get("lines", []),
        "generated_at": datetime.datetime.now().strftime("%Y/%m/%d %H:%M"),
        "is_fa": is_fa,
    }

    # تلاش برای رندر با قالب سفارشی
    resolved_html = None
    try:
        from app.services.report_template_service import ReportTemplateService
        explicit_template_id = None
        try:
            if template_id is not None:
                explicit_template_id = int(template_id)
        except Exception:
            explicit_template_id = None
        resolved_html = ReportTemplateService.try_render_resolved(
            db=db,
            business_id=business_id,
            module_key="invoices",
            subtype="detail",
            context=template_context,
            explicit_template_id=explicit_template_id,
        )
    except Exception:
        resolved_html = None

    # HTML پیش‌فرض در نبود قالب: استفاده از قالب فایل
    # پارامترهای صفحه از کوئری (اختیاری)
    try:
        qp = request.query_params
        paper_size = qp.get("paper_size")
        orientation = qp.get("orientation")
        disposition = qp.get("disposition") or "attachment"
    except Exception:
        paper_size = None
        orientation = None
        disposition = "attachment"
    default_ctx = {
        **template_context,
        "title_text": item.get("title") or ("فاکتور" if is_fa else "Invoice"),
        "paper_size": paper_size,
        "orientation": orientation,
        "footer_text": "",
    }
    html_content = resolved_html or render_template("pdf/invoices/detail.html", default_ctx)

    font_config = FontConfiguration()
    pdf_bytes = HTML(string=html_content).write_pdf(font_config=font_config)

    # نام فایل
    def _slugify(text: str) -> str:
        return re.sub(r"[^A-Za-z0-9_-]+", "_", (text or "")).strip("_") or "invoice"
    filename = f"invoice_{_slugify(item.get('code'))}_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf"

    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f"{disposition}; filename={filename}",
            "Content-Length": str(len(pdf_bytes)),
            "Access-Control-Expose-Headers": "Content-Disposition",
        },
    )

@router.post("/business/{business_id}/search")
@require_business_access("business_id")
async def search_invoices_endpoint(
    request: Request,
    business_id: int,
    query_info: QueryInfo = Body(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    """لیست فاکتورها با فیلتر، جست‌وجو، مرتب‌سازی و صفحه‌بندی استاندارد"""

    # Base query
    q = db.query(Document).filter(
        and_(
            Document.business_id == business_id,
            Document.document_type.in_(list(SUPPORTED_INVOICE_TYPES)),
        )
    )

    # Merge flat body extras similar to other list endpoints
    body: Dict[str, Any] = {}
    try:
        body_json = await request.json()
        if isinstance(body_json, dict):
            body = body_json
    except Exception:
        body = {}

    # Simple search on code/description
    search: Optional[str] = getattr(query_info, 'search', None)
    if isinstance(search, str) and search.strip():
        s = f"%{search.strip()}%"
        q = q.filter(or_(Document.code.ilike(s), Document.description.ilike(s)))

    # Extra filters
    doc_type = body.get("document_type")
    if isinstance(doc_type, str) and doc_type in SUPPORTED_INVOICE_TYPES:
        q = q.filter(Document.document_type == doc_type)

    is_proforma = body.get("is_proforma")
    if isinstance(is_proforma, bool):
        q = q.filter(Document.is_proforma == is_proforma)

    currency_id = body.get("currency_id")
    try:
        if currency_id is not None:
            q = q.filter(Document.currency_id == int(currency_id))
    except Exception:
        pass

    # Fiscal year from header or body
    fiscal_year_id = None
    try:
        fy_header = request.headers.get("X-Fiscal-Year-ID")
        if fy_header:
            fiscal_year_id = int(fy_header)
    except Exception:
        fiscal_year_id = None
    if fiscal_year_id is None:
        try:
            if body.get("fiscal_year_id") is not None:
                fiscal_year_id = int(body.get("fiscal_year_id"))
        except Exception:
            fiscal_year_id = None
    if fiscal_year_id is not None:
        q = q.filter(Document.fiscal_year_id == fiscal_year_id)

    # Date range from filters or flat body
    # 1) From QueryInfo.filters operators
    try:
        filters = getattr(query_info, 'filters', None)
    except Exception:
        filters = None
    if filters and isinstance(filters, (list, tuple)):
        for flt in filters:
            try:
                prop = getattr(flt, 'property', None) if not isinstance(flt, dict) else flt.get('property')
                op = getattr(flt, 'operator', None) if not isinstance(flt, dict) else flt.get('operator')
                val = getattr(flt, 'value', None) if not isinstance(flt, dict) else flt.get('value')
                if prop == 'document_date' and isinstance(val, str) and val:
                    from app.services.transfer_service import _parse_iso_date as _p
                    dt = _p(val)
                    col = getattr(Document, prop)
                    if op == ">=":
                        q = q.filter(col >= dt)
                    elif op == "<=":
                        q = q.filter(col <= dt)
            except Exception:
                pass

    # 2) From flat body keys
    if isinstance(body.get("from_date"), str):
        try:
            from app.services.transfer_service import _parse_iso_date as _p
            q = q.filter(Document.document_date >= _p(body.get("from_date")))
        except Exception:
            pass
    if isinstance(body.get("to_date"), str):
        try:
            from app.services.transfer_service import _parse_iso_date as _p
            q = q.filter(Document.document_date <= _p(body.get("to_date")))
        except Exception:
            pass

    # Sorting
    sort_desc = bool(getattr(query_info, 'sort_desc', True))
    sort_by = getattr(query_info, 'sort_by', None) or 'document_date'
    sort_col = Document.document_date
    if isinstance(sort_by, str):
        if sort_by == 'code' and hasattr(Document, 'code'):
            sort_col = Document.code
        elif sort_by == 'created_at' and hasattr(Document, 'created_at'):
            sort_col = Document.created_at
        elif sort_by == 'registered_at' and hasattr(Document, 'registered_at'):
            sort_col = Document.registered_at
        else:
            sort_col = Document.document_date
    q = q.order_by(sort_col.desc() if sort_desc else sort_col.asc())

    # Pagination
    take = int(getattr(query_info, 'take', 20) or 20)
    skip = int(getattr(query_info, 'skip', 0) or 0)

    total = q.count()
    items: List[Document] = q.offset(skip).limit(take).all()

    # Helpers for display fields
    def _type_name(tp: str) -> str:
        mapping = {
            'invoice_sales': 'فروش',
            'invoice_sales_return': 'برگشت از فروش',
            'invoice_purchase': 'خرید',
            'invoice_purchase_return': 'برگشت از خرید',
            'invoice_direct_consumption': 'مصرف مستقیم',
            'invoice_production': 'تولید',
            'invoice_waste': 'ضایعات',
        }
        return mapping.get(str(tp), str(tp))

    data_items: List[Dict[str, Any]] = []
    for d in items:
        item = invoice_document_to_dict(db, d)
        # total_amount from extra_info.totals.net if available
        total_amount = None
        try:
            totals = (item.get('extra_info') or {}).get('totals') or {}
            if isinstance(totals, dict) and 'net' in totals:
                total_amount = totals.get('net')
        except Exception:
            total_amount = None
        # Fallback compute from product lines
        if total_amount is None:
            try:
                net_sum = 0.0
                for pl in item.get('product_lines', []) or []:
                    info = pl.get('extra_info') or {}
                    qty = float(pl.get('quantity') or 0)
                    unit_price = float(info.get('unit_price') or 0)
                    line_discount = float(info.get('line_discount') or 0)
                    tax_amount = float(info.get('tax_amount') or 0)
                    line_total = info.get('line_total')
                    if line_total is None:
                        line_total = (qty * unit_price) - line_discount + tax_amount
                    net_sum += float(line_total)
                total_amount = float(net_sum)
            except Exception:
                total_amount = None

        item['document_type_name'] = _type_name(item.get('document_type'))
        if total_amount is not None:
            item['total_amount'] = total_amount
        data_items.append(format_datetime_fields(item, request))

    # Build pagination info
    page = (skip // take) + 1 if take > 0 else 1
    total_pages = (total + take - 1) // take if take > 0 else 1

    return success_response(
        data={
            "items": data_items,
            "total": total,
            "take": take,
            "skip": skip,
            # Optional standard pagination shape (supported by UI model)
            "pagination": {
                "page": page,
                "per_page": take,
                "total": total,
                "total_pages": total_pages,
            },
            # Flat shape too, for compatibility
            "page": page,
            "limit": take,
            "total_pages": total_pages,
        },
        request=request,
        message="INVOICE_LIST",
    )



@router.post(
    "/business/{business_id}/export/excel",
    summary="خروجی Excel لیست فاکتورها",
    description="خروجی Excel لیست فاکتورها با قابلیت فیلتر، انتخاب سطرها و رعایت ترتیب/نمایش ستون‌ها",
)
@require_business_access("business_id")
async def export_invoices_excel(
    business_id: int,
    request: Request,
    body: Dict[str, Any] = Body(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    from openpyxl import Workbook
    from openpyxl.styles import Font, PatternFill, Alignment, Border, Side

    # Build base query similar to search endpoint
    take_value = min(int(body.get("take", 1000)), 10000)
    skip_value = int(body.get("skip", 0))

    q = db.query(Document).filter(
        and_(
            Document.business_id == business_id,
            Document.document_type.in_(list(SUPPORTED_INVOICE_TYPES)),
        )
    )

    # Search
    search = body.get("search")
    if isinstance(search, str) and search.strip():
        s = f"%{search.strip()}%"
        q = q.filter(or_(Document.code.ilike(s), Document.description.ilike(s)))

    # Filters
    doc_type = body.get("document_type")
    if isinstance(doc_type, str) and doc_type in SUPPORTED_INVOICE_TYPES:
        q = q.filter(Document.document_type == doc_type)

    is_proforma = body.get("is_proforma")
    if isinstance(is_proforma, bool):
        q = q.filter(Document.is_proforma == is_proforma)

    currency_id = body.get("currency_id")
    try:
        if currency_id is not None:
            q = q.filter(Document.currency_id == int(currency_id))
    except Exception:
        pass

    # Fiscal year
    try:
        fy_header = request.headers.get("X-Fiscal-Year-ID")
        if fy_header:
            q = q.filter(Document.fiscal_year_id == int(fy_header))
        elif body.get("fiscal_year_id") is not None:
            q = q.filter(Document.fiscal_year_id == int(body.get("fiscal_year_id")))
    except Exception:
        pass

    # Date range
    from app.services.transfer_service import _parse_iso_date as _p
    if isinstance(body.get("from_date"), str):
        try:
            q = q.filter(Document.document_date >= _p(body.get("from_date")))
        except Exception:
            pass
    if isinstance(body.get("to_date"), str):
        try:
            q = q.filter(Document.document_date <= _p(body.get("to_date")))
        except Exception:
            pass

    # Sorting
    sort_desc = bool(body.get("sort_desc", True))
    sort_by = body.get("sort_by") or "document_date"
    sort_col = Document.document_date
    if sort_by == 'code' and hasattr(Document, 'code'):
        sort_col = Document.code
    elif sort_by == 'created_at' and hasattr(Document, 'created_at'):
        sort_col = Document.created_at
    elif sort_by == 'registered_at' and hasattr(Document, 'registered_at'):
        sort_col = Document.registered_at
    q = q.order_by(sort_col.desc() if sort_desc else sort_col.asc())

    total = q.count()
    docs: List[Document] = q.offset(skip_value).limit(take_value).all()

    # Build items like list endpoint
    def _type_name(tp: str) -> str:
        mapping = {
            'invoice_sales': 'فروش',
            'invoice_sales_return': 'برگشت از فروش',
            'invoice_purchase': 'خرید',
            'invoice_purchase_return': 'برگشت از خرید',
            'invoice_direct_consumption': 'مصرف مستقیم',
            'invoice_production': 'تولید',
            'invoice_waste': 'ضایعات',
        }
        return mapping.get(str(tp), str(tp))

    items: List[Dict[str, Any]] = []
    for d in docs:
        item = invoice_document_to_dict(db, d)
        # total_amount
        total_amount = None
        try:
            totals = (item.get('extra_info') or {}).get('totals') or {}
            if isinstance(totals, dict) and 'net' in totals:
                total_amount = totals.get('net')
        except Exception:
            total_amount = None
        if total_amount is None:
            try:
                net_sum = 0.0
                for pl in item.get('product_lines', []) or []:
                    info = pl.get('extra_info') or {}
                    qty = float(pl.get('quantity') or 0)
                    unit_price = float(info.get('unit_price') or 0)
                    line_discount = float(info.get('line_discount') or 0)
                    tax_amount = float(info.get('tax_amount') or 0)
                    line_total = info.get('line_total')
                    if line_total is None:
                        line_total = (qty * unit_price) - line_discount + tax_amount
                    net_sum += float(line_total)
                total_amount = float(net_sum)
            except Exception:
                total_amount = None

        item['document_type_name'] = _type_name(item.get('document_type'))
        if total_amount is not None:
            item['total_amount'] = total_amount
        items.append(format_datetime_fields(item, request))

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

    # Prepare columns
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
        default_columns = [
            ('code', 'کد سند'),
            ('document_type_name', 'نوع فاکتور'),
            ('document_date', 'تاریخ سند'),
            ('total_amount', 'مبلغ کل'),
            ('currency_code', 'ارز'),
            ('created_by_name', 'ایجادکننده'),
            ('is_proforma', 'وضعیت'),
            ('registered_at', 'تاریخ ثبت'),
        ]
        for key, label in default_columns:
            if items and key in items[0]:
                keys.append(key)
                headers.append(label)

    # Create workbook
    wb = Workbook()
    ws = wb.active
    ws.title = "Invoices"

    header_font = Font(bold=True, color="FFFFFF")
    header_fill = PatternFill(start_color="366092", end_color="366092", fill_type="solid")
    header_alignment = Alignment(horizontal="center", vertical="center")
    border = Border(left=Side(style='thin'), right=Side(style='thin'), top=Side(style='thin'), bottom=Side(style='thin'))

    # Header row
    for col_idx, header in enumerate(headers, 1):
        cell = ws.cell(row=1, column=col_idx, value=header)
        cell.font = header_font
        cell.fill = header_fill
        cell.alignment = header_alignment
        cell.border = border

    # Data rows
    for row_idx, item in enumerate(items, 2):
        for col_idx, key in enumerate(keys, 1):
            value = item.get(key, "")
            if isinstance(value, list):
                value = ", ".join(str(v) for v in value)
            elif isinstance(value, dict):
                value = str(value)
            ws.cell(row=row_idx, column=col_idx, value=value).border = border

    # Auto-width
    for column in ws.columns:
        max_length = 0
        column_letter = column[0].column_letter
        for cell in column:
            try:
                if len(str(cell.value)) > max_length:
                    max_length = len(str(cell.value))
            except Exception:
                pass
        ws.column_dimensions[column_letter].width = min(max_length + 2, 50)

    # Save to bytes
    buffer = io.BytesIO()
    wb.save(buffer)
    buffer.seek(0)

    # Filename
    biz_name = ""
    try:
        b = db.query(Business).filter(Business.id == business_id).first()
        if b is not None:
            biz_name = b.name or ""
    except Exception:
        biz_name = ""

    def slugify(text: str) -> str:
        return re.sub(r"[^A-Za-z0-9_-]+", "_", text).strip("_")

    base = "invoices"
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
    "/business/{business_id}/export/pdf",
    summary="خروجی PDF لیست فاکتورها",
    description="خروجی PDF لیست فاکتورها با قابلیت فیلتر، انتخاب سطرها و رعایت ترتیب/نمایش ستون‌ها",
)
@require_business_access("business_id")
async def export_invoices_pdf(
    business_id: int,
    request: Request,
    body: Dict[str, Any] = Body(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    from weasyprint import HTML
    from weasyprint.text.fonts import FontConfiguration
    from app.core.i18n import negotiate_locale
    from html import escape

    # Build same list as excel
    take_value = min(int(body.get("take", 1000)), 10000)
    skip_value = int(body.get("skip", 0))

    q = db.query(Document).filter(
        and_(
            Document.business_id == business_id,
            Document.document_type.in_(list(SUPPORTED_INVOICE_TYPES)),
        )
    )

    search = body.get("search")
    if isinstance(search, str) and search.strip():
        s = f"%{search.strip()}%"
        q = q.filter(or_(Document.code.ilike(s), Document.description.ilike(s)))

    doc_type = body.get("document_type")
    if isinstance(doc_type, str) and doc_type in SUPPORTED_INVOICE_TYPES:
        q = q.filter(Document.document_type == doc_type)

    is_proforma = body.get("is_proforma")
    if isinstance(is_proforma, bool):
        q = q.filter(Document.is_proforma == is_proforma)

    currency_id = body.get("currency_id")
    try:
        if currency_id is not None:
            q = q.filter(Document.currency_id == int(currency_id))
    except Exception:
        pass

    try:
        fy_header = request.headers.get("X-Fiscal-Year-ID")
        if fy_header:
            q = q.filter(Document.fiscal_year_id == int(fy_header))
        elif body.get("fiscal_year_id") is not None:
            q = q.filter(Document.fiscal_year_id == int(body.get("fiscal_year_id")))
    except Exception:
        pass

    from app.services.transfer_service import _parse_iso_date as _p
    if isinstance(body.get("from_date"), str):
        try:
            q = q.filter(Document.document_date >= _p(body.get("from_date")))
        except Exception:
            pass
    if isinstance(body.get("to_date"), str):
        try:
            q = q.filter(Document.document_date <= _p(body.get("to_date")))
        except Exception:
            pass

    sort_desc = bool(body.get("sort_desc", True))
    sort_by = body.get("sort_by") or "document_date"
    sort_col = Document.document_date
    if sort_by == 'code' and hasattr(Document, 'code'):
        sort_col = Document.code
    elif sort_by == 'created_at' and hasattr(Document, 'created_at'):
        sort_col = Document.created_at
    elif sort_by == 'registered_at' and hasattr(Document, 'registered_at'):
        sort_col = Document.registered_at
    q = q.order_by(sort_col.desc() if sort_desc else sort_col.asc())

    docs: List[Document] = q.offset(skip_value).limit(take_value).all()

    def _type_name(tp: str) -> str:
        mapping = {
            'invoice_sales': 'فروش',
            'invoice_sales_return': 'برگشت از فروش',
            'invoice_purchase': 'خرید',
            'invoice_purchase_return': 'برگشت از خرید',
            'invoice_direct_consumption': 'مصرف مستقیم',
            'invoice_production': 'تولید',
            'invoice_waste': 'ضایعات',
        }
        return mapping.get(str(tp), str(tp))

    items: List[Dict[str, Any]] = []
    for d in docs:
        item = invoice_document_to_dict(db, d)
        total_amount = None
        try:
            totals = (item.get('extra_info') or {}).get('totals') or {}
            if isinstance(totals, dict) and 'net' in totals:
                total_amount = totals.get('net')
        except Exception:
            total_amount = None
        if total_amount is None:
            try:
                net_sum = 0.0
                for pl in item.get('product_lines', []) or []:
                    info = pl.get('extra_info') or {}
                    qty = float(pl.get('quantity') or 0)
                    unit_price = float(info.get('unit_price') or 0)
                    line_discount = float(info.get('line_discount') or 0)
                    tax_amount = float(info.get('tax_amount') or 0)
                    line_total = info.get('line_total')
                    if line_total is None:
                        line_total = (qty * unit_price) - line_discount + tax_amount
                    net_sum += float(line_total)
                total_amount = float(net_sum)
            except Exception:
                total_amount = None
        item['document_type_name'] = _type_name(item.get('document_type'))
        if total_amount is not None:
            item['total_amount'] = total_amount
        items.append(format_datetime_fields(item, request))

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

    # Prepare columns
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
        default_columns = [
            ('code', 'کد سند'),
            ('document_type_name', 'نوع فاکتور'),
            ('document_date', 'تاریخ سند'),
            ('total_amount', 'مبلغ کل'),
            ('currency_code', 'ارز'),
            ('created_by_name', 'ایجادکننده'),
            ('is_proforma', 'وضعیت'),
            ('registered_at', 'تاریخ ثبت'),
        ]
        for key, label in default_columns:
            if items and key in items[0]:
                keys.append(key)
                headers.append(label)

    # Business name & locale
    business_name = ""
    try:
        b = db.query(Business).filter(Business.id == business_id).first()
        if b is not None:
            business_name = b.name or ""
    except Exception:
        business_name = ""

    locale = negotiate_locale(request.headers.get("Accept-Language"))
    is_fa = locale == 'fa'
    now = datetime.datetime.now().strftime('%Y/%m/%d %H:%M')
    title_text = "لیست فاکتورها" if is_fa else "Invoices List"
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
                value = str(value)
            row_cells.append(f'<td>{escape(str(value))}</td>')
        rows_html.append(f'<tr>{"".join(row_cells)}</tr>')

    # کانتکست مشترک برای قالب‌های سفارشی
    template_context: Dict[str, Any] = {
        "title_text": title_text,
        "business_name": business_name,
        "generated_at": now,
        "is_fa": is_fa,
        "headers": headers,
        "keys": keys,
        "items": items,
        # خروجی‌های HTML آماده برای استفاده سریع در قالب
        "table_headers_html": headers_html,
        "table_rows_html": "".join(rows_html),
    }

    # تلاش برای رندر با قالب سفارشی (explicit یا پیش‌فرض)
    try:
        from app.services.report_template_service import ReportTemplateService
        explicit_template_id = None
        try:
            if "template_id" in body and body.get("template_id") is not None:
                explicit_template_id = int(body.get("template_id"))
        except Exception:
            explicit_template_id = None
        resolved_html = ReportTemplateService.try_render_resolved(
            db=db,
            business_id=business_id,
            module_key="invoices",
            subtype="list",
            context=template_context,
            explicit_template_id=explicit_template_id,
        )
    except Exception:
        resolved_html = None

    # HTML پیش‌فرض در نبود قالب: استفاده از فایل قالب
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
        "pdf/invoices/list.html",
        {
            **template_context,
            "title_text": title_text,
            "paper_size": paper_size,
            "orientation": orientation,
            "footer_text": footer_text,
        },
    )

    font_config = FontConfiguration()
    pdf_bytes = HTML(string=html_content).write_pdf(font_config=font_config)

    def slugify(text: str) -> str:
        return re.sub(r"[^A-Za-z0-9_-]+", "_", text).strip("_")

    base = "invoices"
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

