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

    headers = ["کد", "تاریخ", "مبلغ کل", "ایجادکننده"]
    keys = ["code", "document_date", "total_amount", "created_by_name"]

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
            val = item.get(key, "")
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

    headers = ["کد", "تاریخ", "مبلغ کل", "ایجادکننده"]
    keys = ["code", "document_date", "total_amount", "created_by_name"]

    header_html = ''.join(f'<th>{escape(h)}</th>' for h in headers)
    rows_html = []
    for it in items:
        row_cells = []
        for k in keys:
            v = it.get(k, "")
            row_cells.append(f'<td>{escape(str(v))}</td>')
        rows_html.append(f'<tr>{"".join(row_cells)}</tr>')

    now = datetime.datetime.now().strftime('%Y/%m/%d %H:%M')
    html = f"""
    <!DOCTYPE html>
    <html dir='rtl'>
      <head>
        <meta charset='utf-8'>
        <title>لیست انتقال‌ها</title>
        <style>
          @page {{ margin: 1cm; size: A4; }}
          body {{ font-family: Tahoma, Arial; font-size: 12px; color: #333; }}
          .header {{ display: flex; justify-content: space-between; margin-bottom: 16px; border-bottom: 2px solid #366092; padding-bottom: 8px; }}
          .title {{ font-weight: bold; color: #366092; font-size: 18px; }}
          table {{ width: 100%; border-collapse: collapse; }}
          th, td {{ border: 1px solid #ddd; padding: 6px; text-align: right; }}
          thead th {{ background-color: #f0f0f0; }}
        </style>
      </head>
      <body>
        <div class='header'>
          <div class='title'>لیست انتقال‌ها</div>
          <div>تاریخ تولید: {escape(now)}</div>
        </div>
        <table>
          <thead><tr>{header_html}</tr></thead>
          <tbody>
            {''.join(rows_html)}
          </tbody>
        </table>
      </body>
    </html>
    """
    font_config = FontConfiguration()
    pdf_bytes = HTML(string=html).write_pdf(font_config=font_config)
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


