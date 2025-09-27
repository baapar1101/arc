from fastapi import APIRouter, Depends, HTTPException, Query, Request, Body
from sqlalchemy.orm import Session
from typing import Dict, Any, List, Optional

from adapters.db.session import get_db
from adapters.api.v1.schema_models.person import (
    PersonCreateRequest, PersonUpdateRequest, PersonResponse,
    PersonListResponse, PersonSummaryResponse, PersonBankAccountCreateRequest
)
from adapters.api.v1.schemas import QueryInfo, SuccessResponse
from app.core.responses import success_response, format_datetime_fields
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_management_dep
from app.services.person_service import (
    create_person, get_person_by_id, get_persons_by_business,
    update_person, delete_person, get_person_summary
)
from adapters.db.models.person import Person
from adapters.db.models.business import Business

router = APIRouter(prefix="/persons", tags=["persons"])


@router.post("/businesses/{business_id}/persons/create", 
    summary="ایجاد شخص جدید", 
    description="ایجاد شخص جدید برای کسب و کار مشخص",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "شخص با موفقیت ایجاد شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "message": "شخص با موفقیت ایجاد شد",
                        "data": {
                            "id": 1,
                            "business_id": 1,
                            "alias_name": "علی احمدی",
                            "person_type": "مشتری",
                            "created_at": "2024-01-01T00:00:00Z"
                        }
                    }
                }
            }
        },
        400: {
            "description": "خطا در اعتبارسنجی داده‌ها"
        },
        401: {
            "description": "عدم احراز هویت"
        },
        403: {
            "description": "عدم دسترسی به کسب و کار"
        }
    }
)
async def create_person_endpoint(
    business_id: int,
    person_data: PersonCreateRequest,
    db: Session = Depends(get_db),
    auth_context: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_management_dep),
    request: Request = None,
):
    """ایجاد شخص جدید برای کسب و کار"""
    result = create_person(db, business_id, person_data)
    return success_response(
        data=format_datetime_fields(result['data'], request),
        request=request,
        message=result['message'],
    )


@router.post("/businesses/{business_id}/persons",
    summary="لیست اشخاص کسب و کار",
    description="دریافت لیست اشخاص یک کسب و کار با امکان جستجو و فیلتر",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "لیست اشخاص با موفقیت دریافت شد",
            "content": {
                "application/json": {
                    "example": {
                        "success": True,
                        "message": "لیست اشخاص با موفقیت دریافت شد",
                        "data": {
                            "items": [],
                            "pagination": {
                                "total": 0,
                                "page": 1,
                                "per_page": 20,
                                "total_pages": 0,
                                "has_next": False,
                                "has_prev": False
                            },
                            "query_info": {}
                        }
                    }
                }
            }
        }
    }
)
async def get_persons_endpoint(
    business_id: int,
    query_info: QueryInfo,
    db: Session = Depends(get_db),
    auth_context: AuthContext = Depends(get_current_user),
    request: Request = None,
):
    """دریافت لیست اشخاص کسب و کار"""
    query_dict = {
        "take": query_info.take,
        "skip": query_info.skip,
        "sort_by": query_info.sort_by,
        "sort_desc": query_info.sort_desc,
        "search": query_info.search,
        "search_fields": query_info.search_fields,
        "filters": query_info.filters,
    }
    result = get_persons_by_business(db, business_id, query_dict)
    
    # فرمت کردن تاریخ‌ها
    result['items'] = [
        format_datetime_fields(item, request) for item in result['items']
    ]
    
    return success_response(
        data=result,
        request=request,
        message="لیست اشخاص با موفقیت دریافت شد",
    )


@router.post("/businesses/{business_id}/persons/export/excel",
    summary="خروجی Excel لیست اشخاص",
    description="خروجی Excel لیست اشخاص با قابلیت فیلتر، انتخاب سطرها و رعایت ترتیب/نمایش ستون‌ها",
)
async def export_persons_excel(
    business_id: int,
    request: Request,
    body: Dict[str, Any] = Body(...),
    auth_context: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    import io
    import json
    import datetime
    from openpyxl import Workbook
    from openpyxl.styles import Font, Alignment, PatternFill, Border, Side
    from fastapi.responses import Response

    # Build query dict similar to list endpoint from flat body
    query_dict = {
        "take": int(body.get("take", 20)),
        "skip": int(body.get("skip", 0)),
        "sort_by": body.get("sort_by"),
        "sort_desc": bool(body.get("sort_desc", False)),
        "search": body.get("search"),
        "search_fields": body.get("search_fields"),
        "filters": body.get("filters"),
    }

    result = get_persons_by_business(db, business_id, query_dict)

    items = result.get('items', [])
    # Format date/time fields using existing helper
    items = [format_datetime_fields(item, request) for item in items]

    # Apply selected indices filter if requested
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

    # Prepare headers based on export_columns (order + visibility)
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
        # Fallback to item keys if no columns provided
        if items:
            keys = list(items[0].keys())
            headers = keys

    # Create workbook
    wb = Workbook()
    ws = wb.active
    ws.title = "Persons"

    header_font = Font(bold=True, color="FFFFFF")
    header_fill = PatternFill(start_color="366092", end_color="366092", fill_type="solid")
    header_alignment = Alignment(horizontal="center", vertical="center")
    border = Border(left=Side(style='thin'), right=Side(style='thin'), top=Side(style='thin'), bottom=Side(style='thin'))

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
            if isinstance(value, list):
                value = ", ".join(str(v) for v in value)
            ws.cell(row=row_idx, column=col_idx, value=value).border = border

    # Auto-width columns
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

    filename = f"persons_export_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.xlsx"
    content = buffer.getvalue()
    return Response(
        content=content,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={
            "Content-Disposition": f"attachment; filename={filename}",
            "Content-Length": str(len(content)),
        },
    )


@router.post("/businesses/{business_id}/persons/export/pdf",
    summary="خروجی PDF لیست اشخاص",
    description="خروجی PDF لیست اشخاص با قابلیت فیلتر، انتخاب سطرها و رعایت ترتیب/نمایش ستون‌ها",
)
async def export_persons_pdf(
    business_id: int,
    request: Request,
    body: Dict[str, Any] = Body(...),
    auth_context: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    import json
    import datetime
    from fastapi.responses import Response
    from weasyprint import HTML, CSS
    from weasyprint.text.fonts import FontConfiguration

    # Build query dict from flat body
    query_dict = {
        "take": int(body.get("take", 20)),
        "skip": int(body.get("skip", 0)),
        "sort_by": body.get("sort_by"),
        "sort_desc": bool(body.get("sort_desc", False)),
        "search": body.get("search"),
        "search_fields": body.get("search_fields"),
        "filters": body.get("filters"),
    }

    result = get_persons_by_business(db, business_id, query_dict)
    items = result.get('items', [])
    items = [format_datetime_fields(item, request) for item in items]

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
        if items:
            keys = list(items[0].keys())
            headers = keys

    # Load business info for header
    business_name = ""
    try:
        biz = db.query(Business).filter(Business.id == business_id).first()
        if biz is not None:
            business_name = biz.name
    except Exception:
        business_name = ""

    # Styled HTML (A4 landscape, RTL)
    def escape(s: Any) -> str:
        try:
            return str(s).replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
        except Exception:
            return str(s)

    rows_html = []
    for item in items:
        tds = []
        for key in keys:
            value = item.get(key)
            if value is None:
                value = ""
            elif isinstance(value, list):
                value = ", ".join(str(v) for v in value)
            tds.append(f"<td>{escape(value)}</td>")
        rows_html.append(f"<tr>{''.join(tds)}</tr>")

    headers_html = ''.join(f"<th>{escape(h)}</th>" for h in headers)
    # Format report datetime based on X-Calendar-Type header
    calendar_header = request.headers.get("X-Calendar-Type", "jalali").lower()
    try:
        from app.core.calendar import CalendarConverter
        formatted_now = CalendarConverter.format_datetime(datetime.datetime.now(),
            "jalali" if calendar_header in ["jalali", "persian", "shamsi"] else "gregorian")
        now = formatted_now.get('formatted', formatted_now.get('date_time', ''))
    except Exception:
        now = datetime.datetime.now().strftime('%Y/%m/%d %H:%M')
    table_html = f"""
    <html lang=\"fa\" dir=\"rtl\">
      <head>
        <meta charset='utf-8'>
        <style>
          @page {{
            size: A4 landscape;
            margin: 12mm;
            @bottom-right {{
              content: "صفحه " counter(page) " از " counter(pages);
              font-size: 10px;
              color: #666;
            }}
          }}
          body {{
            font-family: sans-serif;
            font-size: 11px;
            color: #222;
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
          }}
          .meta {{
            font-size: 11px;
            color: #555;
          }}
          .table-wrapper {{
            width: 100%;
          }}
          table.report-table {{
            width: 100%;
            border-collapse: collapse;
            table-layout: fixed;
          }}
          thead th {{
            background: #f0f3f7;
            border: 1px solid #c7cdd6;
            padding: 6px 4px;
            text-align: center;
            font-weight: 700;
            white-space: nowrap;
          }}
          tbody td {{
            border: 1px solid #d7dde6;
            padding: 5px 4px;
            vertical-align: top;
            overflow-wrap: anywhere;
            word-break: break-word;
            white-space: normal;
          }}
          .footer {{
            position: running(footer);
            font-size: 10px;
            color: #666;
            margin-top: 8px;
            text-align: left;
          }}
        </style>
      </head>
      <body>
        <div class=\"header\">
          <div>
            <div class=\"title\">گزارش لیست اشخاص</div>
            <div class=\"meta\">نام کسب‌وکار: {escape(business_name)}</div>
          </div>
          <div class=\"meta\">تاریخ گزارش: {escape(now)}</div>
        </div>
        <div class=\"table-wrapper\">
          <table class=\"report-table\">
            <thead>
              <tr>{headers_html}</tr>
            </thead>
            <tbody>
              {''.join(rows_html)}
            </tbody>
          </table>
        </div>
        <div class=\"footer\">تولید شده توسط Hesabix</div>
      </body>
    </html>
    """

    font_config = FontConfiguration()
    pdf_bytes = HTML(string=table_html).write_pdf(font_config=font_config)

    filename = f"persons_export_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf"
    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f"attachment; filename={filename}",
            "Content-Length": str(len(pdf_bytes)),
        },
    )


@router.get("/persons/{person_id}",
    summary="جزئیات شخص",
    description="دریافت جزئیات یک شخص",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "جزئیات شخص با موفقیت دریافت شد"
        },
        404: {
            "description": "شخص یافت نشد"
        }
    }
)
async def get_person_endpoint(
    person_id: int,
    db: Session = Depends(get_db),
    auth_context: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_management_dep),
    request: Request = None,
):
    """دریافت جزئیات شخص"""
    # ابتدا باید business_id را از person دریافت کنیم
    person = db.query(Person).filter(Person.id == person_id).first()
    if not person:
        raise HTTPException(status_code=404, detail="شخص یافت نشد")
    
    result = get_person_by_id(db, person_id, person.business_id)
    if not result:
        raise HTTPException(status_code=404, detail="شخص یافت نشد")
    
    return success_response(
        data=format_datetime_fields(result, request),
        request=request,
        message="جزئیات شخص با موفقیت دریافت شد",
    )


@router.put("/persons/{person_id}",
    summary="ویرایش شخص",
    description="ویرایش اطلاعات یک شخص",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "شخص با موفقیت ویرایش شد"
        },
        404: {
            "description": "شخص یافت نشد"
        }
    }
)
async def update_person_endpoint(
    person_id: int,
    person_data: PersonUpdateRequest,
    db: Session = Depends(get_db),
    auth_context: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_management_dep),
    request: Request = None,
):
    """ویرایش شخص"""
    # ابتدا باید business_id را از person دریافت کنیم
    person = db.query(Person).filter(Person.id == person_id).first()
    if not person:
        raise HTTPException(status_code=404, detail="شخص یافت نشد")
    
    result = update_person(db, person_id, person.business_id, person_data)
    if not result:
        raise HTTPException(status_code=404, detail="شخص یافت نشد")
    
    return success_response(
        data=format_datetime_fields(result['data'], request),
        request=request,
        message=result['message'],
    )


@router.delete("/persons/{person_id}",
    summary="حذف شخص",
    description="حذف یک شخص",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "شخص با موفقیت حذف شد"
        },
        404: {
            "description": "شخص یافت نشد"
        }
    }
)
async def delete_person_endpoint(
    person_id: int,
    db: Session = Depends(get_db),
    auth_context: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_management_dep),
    request: Request = None,
):
    """حذف شخص"""
    # ابتدا باید business_id را از person دریافت کنیم
    person = db.query(Person).filter(Person.id == person_id).first()
    if not person:
        raise HTTPException(status_code=404, detail="شخص یافت نشد")
    
    success = delete_person(db, person_id, person.business_id)
    if not success:
        raise HTTPException(status_code=404, detail="شخص یافت نشد")
    
    return success_response(message="شخص با موفقیت حذف شد", request=request)


@router.get("/businesses/{business_id}/persons/summary",
    summary="خلاصه اشخاص کسب و کار",
    description="دریافت خلاصه آماری اشخاص یک کسب و کار",
    response_model=SuccessResponse,
    responses={
        200: {
            "description": "خلاصه اشخاص با موفقیت دریافت شد"
        }
    }
)
async def get_persons_summary_endpoint(
    business_id: int,
    db: Session = Depends(get_db),
    auth_context: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_management_dep),
    request: Request = None,
):
    """دریافت خلاصه اشخاص کسب و کار"""
    result = get_person_summary(db, business_id)
    
    return success_response(
        data=result,
        request=request,
        message="خلاصه اشخاص با موفقیت دریافت شد",
    )
