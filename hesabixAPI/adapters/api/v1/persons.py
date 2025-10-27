from fastapi import APIRouter, Depends, HTTPException, Query, Request, Body, Form
from fastapi import UploadFile, File
from sqlalchemy.orm import Session
from sqlalchemy import and_
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
from app.core.i18n import negotiate_locale
from app.services.person_service import (
    create_person, get_person_by_id, get_persons_by_business,
    update_person, delete_person, get_person_summary
)
from adapters.db.models.person import Person
from adapters.db.models.business import Business
from adapters.db.models.fiscal_year import FiscalYear

router = APIRouter(prefix="/persons", tags=["persons"])


@router.post("/businesses/{business_id}/persons/bulk-delete",
    summary="حذف گروهی اشخاص",
    description="حذف چندین شخص بر اساس شناسه‌ها یا کدها",
)
async def bulk_delete_persons_endpoint(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    auth_context: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_management_dep),
):
    """حذف گروهی اشخاص برای یک کسب‌وکار مشخص

    ورودی:
      - ids: لیست شناسه‌های اشخاص
      - codes: لیست کدهای اشخاص در همان کسب‌وکار
    """
    from sqlalchemy import and_ as _and
    from adapters.db.models.person import Person

    ids = body.get("ids")
    codes = body.get("codes")
    deleted = 0
    skipped = 0

    if not ids and not codes:
        return success_response({"deleted": 0, "skipped": 0}, request)

    # Normalize inputs
    if isinstance(ids, list):
        try:
            ids = [int(x) for x in ids if isinstance(x, (int, str)) and str(x).isdigit()]
        except Exception:
            ids = []
    else:
        ids = []

    if isinstance(codes, list):
        try:
            codes = [int(str(x).strip()) for x in codes if str(x).strip().isdigit()]
        except Exception:
            codes = []
    else:
        codes = []

    # Delete by IDs first
    if ids:
        for pid in ids:
            try:
                person = db.query(Person).filter(_and(Person.id == pid, Person.business_id == business_id)).first()
                if person is None:
                    skipped += 1
                    continue
                db.delete(person)
                deleted += 1
            except Exception:
                skipped += 1
        db.commit()

    # Delete by codes
    if codes:
        try:
            items = db.query(Person).filter(_and(Person.business_id == business_id, Person.code.in_(codes))).all()
            for obj in items:
                try:
                    db.delete(obj)
                    deleted += 1
                except Exception:
                    skipped += 1
            db.commit()
        except Exception:
            # In case of query issues, treat all as skipped
            skipped += len(codes)

    return success_response({"deleted": deleted, "skipped": skipped}, request)


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
    request: Request,
    business_id: int,
    person_data: PersonCreateRequest,
    db: Session = Depends(get_db),
    auth_context: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_management_dep),
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
    request: Request,
    business_id: int,
    query_info: QueryInfo,
    db: Session = Depends(get_db),
    auth_context: AuthContext = Depends(get_current_user),
):
    """دریافت لیست اشخاص کسب و کار"""
    # دریافت سال مالی از header
    fiscal_year_id = None
    fy_header = request.headers.get('X-Fiscal-Year-ID')
    if fy_header:
        try:
            fiscal_year_id = int(fy_header)
        except (ValueError, TypeError):
            pass
    
    # اگر سال مالی مشخص نشده، از سال مالی جاری business استفاده می‌کنیم
    if not fiscal_year_id:
        fiscal_year = db.query(FiscalYear).filter(
            and_(
                FiscalYear.business_id == business_id,
                FiscalYear.is_last == True
            )
        ).first()
        if fiscal_year:
            fiscal_year_id = fiscal_year.id
    
    query_dict = {
        "take": query_info.take,
        "skip": query_info.skip,
        "sort_by": query_info.sort_by,
        "sort_desc": query_info.sort_desc,
        "search": query_info.search,
        "search_fields": query_info.search_fields,
        "filters": query_info.filters,
    }
    result = get_persons_by_business(db, business_id, query_dict, fiscal_year_id)
    
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
    import re
    from openpyxl import Workbook
    from openpyxl.styles import Font, Alignment, PatternFill, Border, Side
    from fastapi.responses import Response

    # دریافت سال مالی از header
    fiscal_year_id = None
    fy_header = request.headers.get('X-Fiscal-Year-ID')
    if fy_header:
        try:
            fiscal_year_id = int(fy_header)
        except (ValueError, TypeError):
            pass
    
    # اگر سال مالی مشخص نشده، از سال مالی جاری business استفاده می‌کنیم
    if not fiscal_year_id:
        fiscal_year = db.query(FiscalYear).filter(
            and_(
                FiscalYear.business_id == business_id,
                FiscalYear.is_last == True
            )
        ).first()
        if fiscal_year:
            fiscal_year_id = fiscal_year.id
    
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

    result = get_persons_by_business(db, business_id, query_dict, fiscal_year_id)

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

    # Locale and RTL/LTR handling
    locale = negotiate_locale(request.headers.get("Accept-Language"))
    if locale == 'fa':
        try:
            ws.sheet_view.rightToLeft = True
        except Exception:
            pass

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
            cell = ws.cell(row=row_idx, column=col_idx, value=value)
            cell.border = border
            if locale == 'fa':
                cell.alignment = Alignment(horizontal="right")

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
    base = "persons"
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
    import re
    from fastapi.responses import Response
    from weasyprint import HTML, CSS
    from weasyprint.text.fonts import FontConfiguration

    # دریافت سال مالی از header
    fiscal_year_id = None
    fy_header = request.headers.get('X-Fiscal-Year-ID')
    if fy_header:
        try:
            fiscal_year_id = int(fy_header)
        except (ValueError, TypeError):
            pass
    
    # اگر سال مالی مشخص نشده، از سال مالی جاری business استفاده می‌کنیم
    if not fiscal_year_id:
        fiscal_year = db.query(FiscalYear).filter(
            and_(
                FiscalYear.business_id == business_id,
                FiscalYear.is_last == True
            )
        ).first()
        if fiscal_year:
            fiscal_year_id = fiscal_year.id
    
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

    result = get_persons_by_business(db, business_id, query_dict, fiscal_year_id)
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

    # Styled HTML with dynamic direction/locale
    locale = negotiate_locale(request.headers.get("Accept-Language"))
    is_fa = (locale == 'fa')
    html_lang = 'fa' if is_fa else 'en'
    html_dir = 'rtl' if is_fa else 'ltr'

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
    
    title_text = "گزارش لیست اشخاص" if is_fa else "Persons List Report"
    label_biz = "نام کسب‌وکار" if is_fa else "Business Name"
    label_date = "تاریخ گزارش" if is_fa else "Report Date"
    footer_text = "تولید شده توسط Hesabix" if is_fa else "Generated by Hesabix"
    page_label_left = "صفحه " if is_fa else "Page "
    page_label_of = " از " if is_fa else " of "

    table_html = f"""
    <html lang=\"{html_lang}\" dir=\"{html_dir}\"> 
      <head>
        <meta charset='utf-8'>
        <style>
          @page {{
            size: A4 landscape;
            margin: 12mm;
            @bottom-{ 'left' if is_fa else 'right' } {{
              content: "{page_label_left}" counter(page) "{page_label_of}" counter(pages);
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
            text-align: {'left' if is_fa else 'right'};
          }}
        </style>
      </head>
      <body>
        <div class=\"header\">
          <div>
            <div class=\"title\">{title_text}</div>
            <div class=\"meta\">{label_biz}: {escape(business_name)}</div>
          </div>
          <div class=\"meta\">{label_date}: {escape(now)}</div>
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
        <div class=\"footer\">{footer_text}</div>
      </body>
    </html>
    """

    font_config = FontConfiguration()
    pdf_bytes = HTML(string=table_html).write_pdf(font_config=font_config)

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
    base = "persons"
    if biz_name:
        base += f"_{slugify(biz_name)}"
    if selected_only:
        base += "_selected"
    filename = f"{base}_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf"
    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f"attachment; filename={filename}",
            "Content-Length": str(len(pdf_bytes)),
            "Access-Control-Expose-Headers": "Content-Disposition",
        },
    )


@router.post("/businesses/{business_id}/persons/import/template",
    summary="دانلود تمپلیت ایمپورت اشخاص",
    description="فایل Excel تمپلیت برای ایمپورت اشخاص را برمی‌گرداند",
)
async def download_persons_import_template(
    business_id: int,
    request: Request,
    auth_context: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    import io
    import datetime
    from fastapi.responses import Response
    from openpyxl import Workbook
    from openpyxl.styles import Font, Alignment

    wb = Workbook()
    ws = wb.active
    ws.title = "Template"

    headers = [
        'code','alias_name','first_name','last_name','person_type','person_types','company_name','payment_id',
        'national_id','registration_number','economic_id','country','province','city','address','postal_code',
        'phone','mobile','fax','email','website','share_count','commission_sale_percent','commission_sales_return_percent',
        'commission_sales_amount','commission_sales_return_amount'
    ]
    for col, header in enumerate(headers, 1):
        cell = ws.cell(row=1, column=col, value=header)
        cell.font = Font(bold=True)
        cell.alignment = Alignment(horizontal="center")

    # Sample row
    sample = [
        '', 'نمونه نام مستعار', 'علی', 'احمدی', 'مشتری', 'مشتری, فروشنده', 'نمونه شرکت', 'PID123',
        '0012345678', '12345', 'ECO-1', 'ایران', 'تهران', 'تهران', 'خیابان مثال ۱', '1234567890',
        '02112345678', '09120000000', '', 'test@example.com', 'example.com', '', '5', '0', '0', '0'
    ]
    for col, val in enumerate(sample, 1):
        ws.cell(row=2, column=col, value=val)

    # Auto width
    for column in ws.columns:
        try:
            letter = column[0].column_letter
            max_len = max(len(str(c.value)) if c.value is not None else 0 for c in column)
            ws.column_dimensions[letter].width = min(max_len + 2, 50)
        except Exception:
            pass

    buf = io.BytesIO()
    wb.save(buf)
    buf.seek(0)

    filename = f"persons_import_template_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.xlsx"
    return Response(
        content=buf.getvalue(),
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={
            "Content-Disposition": f"attachment; filename={filename}",
            "Access-Control-Expose-Headers": "Content-Disposition",
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
    request: Request,
    person_id: int,
    db: Session = Depends(get_db),
    auth_context: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_management_dep),
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
    request: Request,
    person_id: int,
    person_data: PersonUpdateRequest,
    db: Session = Depends(get_db),
    auth_context: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_management_dep),
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
    request: Request,
    person_id: int,
    db: Session = Depends(get_db),
    auth_context: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_management_dep),
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
    request: Request,
    business_id: int,
    db: Session = Depends(get_db),
    auth_context: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_management_dep),
):
    """دریافت خلاصه اشخاص کسب و کار"""
    result = get_person_summary(db, business_id)
    
    return success_response(
        data=result,
        request=request,
        message="خلاصه اشخاص با موفقیت دریافت شد",
    )


@router.post("/businesses/{business_id}/persons/import/excel",
    summary="ایمپورت اشخاص از فایل Excel",
    description="فایل اکسل را دریافت می‌کند و به‌صورت dry-run یا واقعی پردازش می‌کند",
)
async def import_persons_excel(
    business_id: int,
    request: Request,
    file: UploadFile = File(...),
    dry_run: str = Form(default="true"),
    match_by: str = Form(default="code"),
    conflict_policy: str = Form(default="upsert"),
    auth_context: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    import io
    import json
    import re
    from openpyxl import load_workbook
    from fastapi import HTTPException
    import logging
    import zipfile

    logger = logging.getLogger(__name__)
    
    def validate_excel_file(content: bytes) -> bool:
        """
        Validate if the content is a valid Excel file
        """
        try:
            # Check if it starts with PK signature (zip file)
            if not content.startswith(b'PK'):
                return False
            
            # Try to open as zip file
            with zipfile.ZipFile(io.BytesIO(content), 'r') as zip_file:
                file_list = zip_file.namelist()
                # Check for Excel structure (xl/ folder for .xlsx files)
                excel_structure = any(f.startswith('xl/') for f in file_list)
                if excel_structure:
                    return True
                
                # Check for older Excel format (.xls) - this would be a different structure
                # But since we only support .xlsx, we'll return False for .xls
                return False
        except zipfile.BadZipFile:
            logger.error("File is not a valid zip file")
            return False
        except Exception as e:
            logger.error(f"Error validating Excel file: {str(e)}")
            return False
    
    try:
        # Convert dry_run string to boolean
        dry_run_bool = dry_run.lower() in ('true', '1', 'yes', 'on')
        
        logger.info(f"Import request: business_id={business_id}, dry_run={dry_run_bool}, match_by={match_by}, conflict_policy={conflict_policy}")
        logger.info(f"File info: filename={file.filename}, content_type={file.content_type}")

        if not file.filename or not file.filename.lower().endswith('.xlsx'):
            logger.error(f"Invalid file format: {file.filename}")
            raise HTTPException(status_code=400, detail="فرمت فایل معتبر نیست. تنها xlsx پشتیبانی می‌شود")

        content = await file.read()
        logger.info(f"File content size: {len(content)} bytes")
        
        # Log first few bytes for debugging
        logger.info(f"File header (first 20 bytes): {content[:20].hex()}")
        logger.info(f"File header (first 20 bytes as text): {content[:20]}")
        
        # Check if content is empty or too small
        if len(content) < 100:
            logger.error(f"File too small: {len(content)} bytes")
            raise HTTPException(status_code=400, detail="فایل خیلی کوچک است یا خالی است")
        
        # Validate Excel file format
        if not validate_excel_file(content):
            logger.error("File is not a valid Excel file")
            raise HTTPException(status_code=400, detail="فرمت فایل معتبر نیست. فایل Excel معتبر نیست")
        
        try:
            # Try to load the workbook with additional error handling
            wb = load_workbook(filename=io.BytesIO(content), data_only=True)
            logger.info(f"Successfully loaded workbook with {len(wb.worksheets)} worksheets")
        except zipfile.BadZipFile as e:
            logger.error(f"Bad zip file error: {str(e)}")
            raise HTTPException(status_code=400, detail="فایل Excel خراب است یا فرمت آن معتبر نیست")
        except Exception as e:
            logger.error(f"Error loading workbook: {str(e)}")
            raise HTTPException(status_code=400, detail=f"امکان خواندن فایل وجود ندارد: {str(e)}")

        ws = wb.active
        rows = list(ws.iter_rows(values_only=True))
        if not rows:
            return success_response(data={"summary": {"total": 0}}, request=request, message="فایل خالی است")

        headers = [str(h).strip() if h is not None else "" for h in rows[0]]
        data_rows = rows[1:]

        # helper to map enum strings (fa/en) to internal value
        def normalize_person_type(value: str) -> Optional[str]:
            if not value:
                return None
            value = str(value).strip()
            mapping = {
                'customer': 'مشتری', 'marketer': 'بازاریاب', 'employee': 'کارمند', 'supplier': 'تامین‌کننده',
                'partner': 'همکار', 'seller': 'فروشنده', 'shareholder': 'سهامدار'
            }
            for en, fa in mapping.items():
                if value.lower() == en or value == fa:
                    return fa
            return value  # assume already fa

        errors: list[dict] = []
        valid_items: list[dict] = []

        for idx, row in enumerate(data_rows, start=2):
            item: dict[str, Any] = {}
            row_errors: list[str] = []
            for ci, key in enumerate(headers):
                if not key:
                    continue
                val = row[ci] if ci < len(row) else None
                if isinstance(val, str):
                    val = val.strip()
                item[key] = val
            # normalize types
            if 'person_type' in item and item['person_type']:
                item['person_type'] = normalize_person_type(item['person_type'])
            if 'person_types' in item and item['person_types']:
                # split by comma
                parts = [normalize_person_type(p.strip()) for p in str(item['person_types']).split(',') if str(p).strip()]
                item['person_types'] = parts

            # alias_name required
            if not item.get('alias_name'):
                row_errors.append('alias_name الزامی است')

            # shareholder rule
            if (item.get('person_type') == 'سهامدار') or (isinstance(item.get('person_types'), list) and 'سهامدار' in item.get('person_types', [])):
                sc = item.get('share_count')
                try:
                    sc_val = int(sc) if sc is not None and str(sc).strip() != '' else None
                except Exception:
                    sc_val = None
                if sc_val is None or sc_val <= 0:
                    row_errors.append('برای سهامدار share_count باید > 0 باشد')
                else:
                    item['share_count'] = sc_val

            if row_errors:
                errors.append({"row": idx, "errors": row_errors})
                continue

            valid_items.append(item)

        inserted = 0
        updated = 0
        skipped = 0

        if not dry_run_bool and valid_items:
            # apply import with conflict policy
            from adapters.db.models.person import Person
            from sqlalchemy import and_

            def find_existing(session: Session, data: dict) -> Optional[Person]:
                if match_by == 'national_id' and data.get('national_id'):
                    return session.query(Person).filter(and_(Person.business_id == business_id, Person.national_id == data['national_id'])).first()
                if match_by == 'email' and data.get('email'):
                    return session.query(Person).filter(and_(Person.business_id == business_id, Person.email == data['email'])).first()
                if match_by == 'code' and data.get('code'):
                    try:
                        code_int = int(data['code'])
                        return session.query(Person).filter(and_(Person.business_id == business_id, Person.code == code_int)).first()
                    except Exception:
                        return None
                return None

            for data in valid_items:
                existing = find_existing(db, data)
                match_value = None
                try:
                    match_value = data.get(match_by)
                except Exception:
                    match_value = None
                if existing is None:
                    # create
                    try:
                        create_person(db, business_id, PersonCreateRequest(**data))
                        inserted += 1
                    except Exception as e:
                        logger.error(f"Create person failed for data={data}: {str(e)}")
                        skipped += 1
                else:
                    if conflict_policy == 'insert':
                        logger.info(f"Skipping existing person (match_by={match_by}, value={match_value}) due to conflict_policy=insert")
                        skipped += 1
                    elif conflict_policy in ('update', 'upsert'):
                        try:
                            update_person(db, existing.id, business_id, PersonUpdateRequest(**data))
                            updated += 1
                        except Exception as e:
                            logger.error(f"Update person failed for id={existing.id}, data={data}: {str(e)}")
                            skipped += 1

        summary = {
            "total": len(data_rows),
            "valid": len(valid_items),
            "invalid": len(errors),
            "inserted": inserted,
            "updated": updated,
            "skipped": skipped,
            "dry_run": dry_run_bool,
        }

        return success_response(
            data={
                "summary": summary,
                "errors": errors,
            },
            request=request,
            message="نتیجه ایمپورت اشخاص",
        )
    except Exception as e:
        logger.error(f"Import error: {str(e)}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"خطا در پردازش فایل: {str(e)}")
