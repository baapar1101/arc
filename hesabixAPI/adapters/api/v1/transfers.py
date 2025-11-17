"""
API endpoints برای انتقال وجه (Transfers)
"""

from typing import Any, Dict
from fastapi import APIRouter, Depends, Request, Body
from sqlalchemy.orm import Session
from fastapi.responses import Response
import io, datetime, re

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, format_datetime_fields, ApiError
from app.core.permissions import require_business_management_dep, require_business_access
from adapters.api.v1.schemas import QueryInfo
from app.services.transfer_service import (
    create_transfer,
    get_transfer,
    list_transfers,
    delete_transfer,
    update_transfer,
)
from adapters.db.models.business import Business


router = APIRouter(tags=["transfers"])


@router.post(
    "/businesses/{business_id}/transfers",
    summary="لیست اسناد انتقال",
    description="دریافت لیست اسناد انتقال با فیلتر و جستجو",
)
@require_business_access("business_id")
async def list_transfers_endpoint(
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
    try:
        body_json = await request.json()
        if isinstance(body_json, dict):
            # Forward simple date range params
            for key in ["from_date", "to_date"]:
                if key in body_json:
                    query_dict[key] = body_json[key]
            # Forward advanced filters from DataTable (e.g., document_date range)
            if "filters" in body_json:
                query_dict["filters"] = body_json.get("filters")
    except Exception:
        pass

    try:
        fy_header = request.headers.get("X-Fiscal-Year-ID")
        if fy_header:
            query_dict["fiscal_year_id"] = int(fy_header)
    except Exception:
        pass

    result = list_transfers(db, business_id, query_dict)
    result["items"] = [format_datetime_fields(item, request) for item in result.get("items", [])]
    return success_response(data=result, request=request, message="TRANSFERS_LIST_FETCHED")


@router.post(
    "/businesses/{business_id}/transfers/create",
    summary="ایجاد سند انتقال",
    description="ایجاد سند انتقال جدید",
)
@require_business_access("business_id")
async def create_transfer_endpoint(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_management_dep),
):
    created = create_transfer(db, business_id, ctx.get_user_id(), body)
    return success_response(data=format_datetime_fields(created, request), request=request, message="TRANSFER_CREATED")


@router.get(
    "/transfers/{document_id}",
    summary="جزئیات سند انتقال",
    description="دریافت جزئیات یک سند انتقال",
)
async def get_transfer_endpoint(
    request: Request,
    document_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    result = get_transfer(db, document_id)
    if not result:
        raise ApiError("DOCUMENT_NOT_FOUND", "Transfer document not found", http_status=404)
    business_id = result.get("business_id")
    if business_id and not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "Access denied", http_status=403)
    return success_response(data=format_datetime_fields(result, request), request=request, message="TRANSFER_DETAILS")


@router.delete(
    "/transfers/{document_id}",
    summary="حذف سند انتقال",
    description="حذف یک سند انتقال",
)
async def delete_transfer_endpoint(
    request: Request,
    document_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_management_dep),
):
    result = get_transfer(db, document_id)
    if result:
        business_id = result.get("business_id")
        if business_id and not ctx.can_access_business(business_id):
            raise ApiError("FORBIDDEN", "Access denied", http_status=403)
    ok = delete_transfer(db, document_id)
    if not ok:
        raise ApiError("DOCUMENT_NOT_FOUND", "Transfer document not found", http_status=404)
    return success_response(data=None, request=request, message="TRANSFER_DELETED")


@router.put(
    "/transfers/{document_id}",
    summary="ویرایش سند انتقال",
    description="به‌روزرسانی یک سند انتقال",
)
async def update_transfer_endpoint(
    request: Request,
    document_id: int,
    body: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_management_dep),
):
    result = get_transfer(db, document_id)
    if not result:
        raise ApiError("DOCUMENT_NOT_FOUND", "Transfer document not found", http_status=404)
    business_id = result.get("business_id")
    if business_id and not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "Access denied", http_status=403)
    updated = update_transfer(db, document_id, ctx.get_user_id(), body)
    return success_response(data=format_datetime_fields(updated, request), request=request, message="TRANSFER_UPDATED")


@router.post(
    "/businesses/{business_id}/transfers/export/excel",
    summary="خروجی Excel لیست اسناد انتقال",
    description="خروجی Excel لیست اسناد انتقال با فیلتر و جستجو",
)
@require_business_access("business_id")
async def export_transfers_excel(
    business_id: int,
    request: Request,
    body: Dict[str, Any] = Body(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    from openpyxl import Workbook
    from openpyxl.styles import Font, PatternFill, Alignment, Border, Side

    max_export_records = 10000
    take_value = min(int(body.get("take", 1000)), max_export_records)
    query_dict = {
        "take": take_value,
        "skip": int(body.get("skip", 0)),
        "sort_by": body.get("sort_by"),
        "sort_desc": bool(body.get("sort_desc", False)),
        "search": body.get("search"),
        "from_date": body.get("from_date"),
        "to_date": body.get("to_date"),
    }

    result = list_transfers(db, business_id, query_dict)
    items = result.get('items', [])
    items = [format_datetime_fields(item, request) for item in items]

    wb = Workbook()
    ws = wb.active
    ws.title = "Transfers"

    # Get calendar type for date formatting
    calendar_type = "gregorian"
    if hasattr(request.state, 'calendar_type'):
        calendar_type = request.state.calendar_type
    
    # Helper function to format date based on calendar type
    def format_date_for_excel(item, date_key):
        # If already formatted by format_datetime_fields, use it
        formatted_key = f"{date_key}_formatted"
        if formatted_key in item:
            formatted = item[formatted_key]
            if isinstance(formatted, dict):
                return formatted.get("date_only", "")
            return str(formatted) if formatted else ""
        # Fallback to original value
        date_value = item.get(date_key, "")
        if isinstance(date_value, datetime.datetime):
            # Format based on calendar type
            if calendar_type == "jalali":
                from app.core.calendar import CalendarConverter
                jalali = CalendarConverter.to_jalali(date_value)
                return jalali.get("date_only", "") if jalali else ""
            else:
                return date_value.strftime("%Y-%m-%d")
        return str(date_value) if date_value else ""

    headers = [
        "کد سند",
        "تاریخ سند",
        "تاریخ ثبت",
        "نوع مبدا",
        "نام مبدا",
        "نوع مقصد",
        "نام مقصد",
        "مبلغ کل",
        "کارمزد",
        "توضیحات",
        "ایجادکننده"
    ]
    keys = [
        "code",
        "document_date",
        "registered_at",
        "source_type_name",
        "source_name",
        "destination_type_name",
        "destination_name",
        "total_amount",
        "commission",
        "description",
        "created_by_name"
    ]

    header_font = Font(bold=True, color="FFFFFF")
    header_fill = PatternFill(start_color="366092", end_color="366092", fill_type="solid")
    header_alignment = Alignment(horizontal="center", vertical="center")
    border = Border(left=Side(style='thin'), right=Side(style='thin'), top=Side(style='thin'), bottom=Side(style='thin'))

    for col_idx, header in enumerate(headers, 1):
        cell = ws.cell(row=1, column=col_idx, value=header)
        cell.font = header_font
        cell.fill = header_fill
        cell.alignment = header_alignment
        cell.border = border

    for row_idx, item in enumerate(items, 2):
        for col_idx, key in enumerate(keys, 1):
            if key in ["document_date", "registered_at"]:
                # Format dates based on calendar type
                val = format_date_for_excel(item, key)
            else:
                val = item.get(key, "")
                # Handle None values
                if val is None:
                    val = ""
            ws.cell(row=row_idx, column=col_idx, value=val).border = border

    # Auto width
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

    buffer = io.BytesIO()
    wb.save(buffer)
    buffer.seek(0)

    biz_name = ""
    try:
        b = db.query(Business).filter(Business.id == business_id).first()
        if b is not None:
            biz_name = b.name or ""
    except Exception:
        biz_name = ""

    def slugify(text: str) -> str:
        return re.sub(r"[^A-Za-z0-9_-]+", "_", text).strip("_")

    base = "transfers"
    if biz_name:
        base += f"_{slugify(biz_name)}"
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
    "/businesses/{business_id}/transfers/export/pdf",
    summary="خروجی PDF لیست اسناد انتقال",
    description="خروجی PDF لیست اسناد انتقال با فیلتر و جستجو",
)
@require_business_access("business_id")
async def export_transfers_pdf(
    business_id: int,
    request: Request,
    body: Dict[str, Any] = Body(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    from weasyprint import HTML
    from weasyprint.text.fonts import FontConfiguration
    from html import escape
    from app.core.i18n import negotiate_locale
    from app.core.calendar import CalendarConverter, get_calendar_type_from_header
    from pathlib import Path

    max_export_records = 10000
    take_value = min(int(body.get("take", 1000)), max_export_records)
    query_dict = {
        "take": take_value,
        "skip": int(body.get("skip", 0)),
        "sort_by": body.get("sort_by"),
        "sort_desc": bool(body.get("sort_desc", False)),
        "search": body.get("search"),
        "from_date": body.get("from_date"),
        "to_date": body.get("to_date"),
    }
    result = list_transfers(db, business_id, query_dict)
    items = result.get('items', [])
    items = [format_datetime_fields(item, request) for item in items]

    # Locale and calendar
    locale = negotiate_locale(request.headers.get("Accept-Language"))
    is_fa = locale == 'fa'
    
    # Get calendar type for date formatting
    calendar_type = get_calendar_type_from_header(request.headers.get("X-Calendar-Type"))
    if not calendar_type:
        calendar_type = "jalali" if is_fa else "gregorian"
    
    # Format generated date based on calendar
    try:
        _now = datetime.datetime.now()
        _fd = CalendarConverter.format_datetime(_now, calendar_type)
        generated_at = _fd.get("formatted") or _fd.get("date_only") or _now.strftime('%Y/%m/%d %H:%M')
    except Exception:
        generated_at = datetime.datetime.now().strftime('%Y/%m/%d %H:%M')
    
    # Helper function to format date based on calendar type
    def format_date_for_pdf(item, date_key):
        # If already formatted by format_datetime_fields, use it
        formatted_key = f"{date_key}_formatted"
        if formatted_key in item:
            formatted = item[formatted_key]
            if isinstance(formatted, dict):
                return formatted.get("date_only", "")
            return str(formatted) if formatted else ""
        # Fallback to original value
        date_value = item.get(date_key, "")
        if isinstance(date_value, datetime.datetime):
            # Format based on calendar type
            if calendar_type == "jalali":
                jalali = CalendarConverter.to_jalali(date_value)
                return jalali.get("date_only", "") if jalali else ""
            else:
                return date_value.strftime("%Y-%m-%d")
        return str(date_value) if date_value else ""

    # Helper for numeric formatting with thousands separator and trimming .00
    def format_number_for_display(value):
        try:
            if value is None:
                return ""
            v = float(value)
            s = f"{v:,.2f}"
            # Trim trailing .00 or trailing zeros
            if "." in s:
                s = s.rstrip("0").rstrip(".")
            return s
        except Exception:
            return str(value) if value is not None else ""

    # Add row number column
    headers = [
        "ردیف",
        "کد سند",
        "تاریخ سند",
        "تاریخ ثبت",
        "نوع مبدا",
        "نام مبدا",
        "نوع مقصد",
        "نام مقصد",
        "مبلغ کل",
        "کارمزد",
        "توضیحات",
        "ایجادکننده"
    ]
    keys = [
        "row_number",  # Will be generated
        "code",
        "document_date",
        "registered_at",
        "source_type_name",
        "source_name",
        "destination_type_name",
        "destination_name",
        "total_amount",
        "commission",
        "description",
        "created_by_name"
    ]

    header_html = ''.join(f'<th>{escape(h)}</th>' for h in headers)
    rows_html = []
    amount_keys = {"total_amount", "commission"}
    date_keys = {"document_date", "registered_at"}
    
    for idx, it in enumerate(items, 1):
        row_cells = []
        for k in keys:
            if k == "row_number":
                row_cells.append(f'<td style="text-align:center">{idx}</td>')
            elif k in date_keys:
                # Format dates based on calendar type
                v = format_date_for_pdf(it, k)
                row_cells.append(f'<td>{escape(str(v))}</td>')
            elif k in amount_keys:
                # Format amounts
                v = it.get(k, 0)
                disp = format_number_for_display(v)
                row_cells.append(f'<td class="amount">{escape(disp)}</td>')
            else:
                v = it.get(k, "")
                # Handle None values
                if v is None:
                    v = ""
                row_cells.append(f'<td>{escape(str(v))}</td>')
        rows_html.append(f'<tr>{"".join(row_cells)}</tr>')

    # Business name
    business_name = ""
    try:
        from adapters.db.models.business import Business
        b = db.query(Business).filter(Business.id == business_id).first()
        if b is not None:
            business_name = b.name or ""
    except Exception:
        business_name = ""

    title_text = "لیست انتقال‌ها" if is_fa else "Transfers List"
    footer_text = f"تولید شده در {generated_at}" if is_fa else f"Generated at {generated_at}"

    # Template context
    template_context: Dict[str, Any] = {
        "title_text": title_text,
        "business_name": business_name,
        "generated_at": generated_at,
        "is_fa": is_fa,
        "fa_font_url_regular": None,
        "fa_font_url_bold": None,
        "headers": headers,
        "keys": keys,
        "items": items,
        "table_headers_html": header_html,
        "table_rows_html": "".join(rows_html),
        "paper_size": "A4",
        "orientation": "landscape",  # افقی
        "footer_text": footer_text,
    }

    # Embed Farsi fonts (YekanBakhFaNum)
    try:
        if is_fa:
            project_root = Path(__file__).resolve().parents[4]
            fonts_dir = project_root / "hesabixUI" / "hesabix_ui" / "assets" / "fonts"
            regular_path = fonts_dir / "YekanBakhFaNum-Regular.ttf"
            bold_path = fonts_dir / "YekanBakhFaNum-Bold.ttf"
            if regular_path.is_file():
                import base64 as _b64
                _data = regular_path.read_bytes()
                _b64_data = _b64.b64encode(_data).decode("ascii")
                template_context["fa_font_url_regular"] = f"data:font/ttf;base64,{_b64_data}"
            if bold_path.is_file():
                import base64 as _b64b
                _data_b = bold_path.read_bytes()
                _b64_data_b = _b64b.b64encode(_data_b).decode("ascii")
                template_context["fa_font_url_bold"] = f"data:font/ttf;base64,{_b64_data_b}"
    except Exception:
        pass

    # Try to render with custom template
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
            module_key="transfers",
            subtype="list",
            context=template_context,
            explicit_template_id=explicit_template_id,
        )
    except Exception:
        resolved_html = None

    # Default HTML template using base.html
    if not resolved_html:
        try:
            from app.services.pdf.template_renderer import render_template
            resolved_html = render_template(
                "pdf/transfers/list.html",
                **template_context
            )
        except Exception:
            # Fallback simple HTML
            resolved_html = f"""
            <!DOCTYPE html>
            <html dir='rtl' lang='fa'>
              <head>
                <meta charset='utf-8'>
                <title>{title_text}</title>
                <style>
                  @page {{ margin: 1cm; size: A4 landscape; }}
                  body {{ font-family: 'YekanBakhFaNum', Tahoma, Arial; font-size: 12px; color: #333; }}
                  .header {{ display: flex; justify-content: space-between; margin-bottom: 16px; border-bottom: 2px solid #366092; padding-bottom: 8px; }}
                  .title {{ font-weight: bold; color: #366092; font-size: 18px; }}
                  table {{ width: 100%; border-collapse: collapse; }}
                  th, td {{ border: 1px solid #ddd; padding: 6px; text-align: right; }}
                  thead th {{ background-color: #f0f0f0; }}
                  .amount {{ text-align: left; font-weight: bold; }}
                </style>
              </head>
              <body>
                <div class='header'>
                  <div class='title'>{title_text}</div>
                  <div>تاریخ تولید: {escape(generated_at)}</div>
                </div>
                <table>
                  <thead><tr>{header_html}</tr></thead>
                  <tbody>
                    {"".join(rows_html)}
                  </tbody>
                </table>
              </body>
            </html>
            """

    font_config = FontConfiguration()
    pdf_bytes = HTML(string=resolved_html).write_pdf(font_config=font_config)
    filename = f"transfers_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf"
    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f"attachment; filename={filename}",
            "Content-Length": str(len(pdf_bytes)),
            "Access-Control-Expose-Headers": "Content-Disposition",
        },
    )


