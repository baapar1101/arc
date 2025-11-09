"""
API endpoints برای دریافت و پرداخت (Receipt & Payment)
"""

from typing import Any, Dict, List
from fastapi import APIRouter, Depends, Request, Body
from fastapi.responses import Response
from sqlalchemy.orm import Session
import io
import json
import datetime
import re

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, format_datetime_fields, ApiError
from app.core.permissions import require_business_management_dep, require_business_access
from adapters.api.v1.schemas import QueryInfo
from app.services.receipt_payment_service import (
    create_receipt_payment,
    get_receipt_payment,
    list_receipts_payments,
    delete_receipt_payment,
    update_receipt_payment,
)
from adapters.db.models.business import Business


router = APIRouter(tags=["receipts-payments"])


@router.post(
    "/businesses/{business_id}/receipts-payments",
    summary="لیست اسناد دریافت و پرداخت",
    description="دریافت لیست اسناد دریافت و پرداخت با فیلتر و جستجو",
)
@require_business_access("business_id")
async def list_receipts_payments_endpoint(
    request: Request,
    business_id: int,
    query_info: QueryInfo = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """
    لیست اسناد دریافت و پرداخت
    
    پارامترهای اضافی در body:
    - document_type: "receipt" یا "payment" (اختیاری)
    - from_date: تاریخ شروع (اختیاری)
    - to_date: تاریخ پایان (اختیاری)
    """
    query_dict: Dict[str, Any] = {
        "take": query_info.take,
        "skip": query_info.skip,
        "sort_by": query_info.sort_by,
        "sort_desc": query_info.sort_desc,
        "search": query_info.search,
    }
    
    # دریافت پارامترهای اضافی از body
    try:
        body_json = await request.json()
        if isinstance(body_json, dict):
            for key in ["document_type", "from_date", "to_date"]:
                if key in body_json:
                    query_dict[key] = body_json[key]
                    print(f"API - پارامتر {key}: {body_json[key]}")
    except Exception:
        pass
    
    # دریافت fiscal_year_id از هدر برای اولویت دادن به انتخاب کاربر
    try:
        fy_header = request.headers.get("X-Fiscal-Year-ID")
        if fy_header:
            query_dict["fiscal_year_id"] = int(fy_header)
    except Exception:
        pass

    result = list_receipts_payments(db, business_id, query_dict)
    result["items"] = [format_datetime_fields(item, request) for item in result.get("items", [])]
    
    return success_response(
        data=result,
        request=request,
        message="RECEIPTS_PAYMENTS_LIST_FETCHED"
    )


@router.post(
    "/businesses/{business_id}/receipts-payments/create",
    summary="ایجاد سند دریافت یا پرداخت",
    description="ایجاد سند دریافت یا پرداخت جدید",
)
@require_business_access("business_id")
async def create_receipt_payment_endpoint(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_management_dep),
):
    """
    ایجاد سند دریافت یا پرداخت
    
    Body باید شامل موارد زیر باشد:
    {
        "document_type": "receipt" | "payment",
        "document_date": "2025-01-15T10:30:00",
        "currency_id": 1,
        "description": "توضیحات کلی سند (اختیاری)",
        "person_lines": [
            {
                "person_id": 123,
                "person_name": "علی احمدی",
                "amount": 1000000,
                "description": "توضیحات (اختیاری)"
            }
        ],
        "account_lines": [
            {
                "account_id": 456,
                "amount": 1000000,
                "transaction_type": "bank" | "cash_register" | "petty_cash" | "check",
                "transaction_date": "2025-01-15T10:30:00",
                "commission": 5000,  // اختیاری
                "description": "توضیحات (اختیاری)",
                // اطلاعات اضافی بر اساس نوع تراکنش:
                "bank_id": "123",  // برای نوع bank
                "bank_name": "بانک ملی",
                "cash_register_id": "456",  // برای نوع cash_register
                "cash_register_name": "صندوق اصلی",
                "petty_cash_id": "789",  // برای نوع petty_cash
                "petty_cash_name": "تنخواهگردان فروش",
                "check_id": "101",  // برای نوع check
                "check_number": "123456"
            }
        ],
        "extra_info": {}  // اختیاری
    }
    """
    created = create_receipt_payment(db, business_id, ctx.get_user_id(), body)
    
    return success_response(
        data=format_datetime_fields(created, request),
        request=request,
        message="RECEIPT_PAYMENT_CREATED"
    )


@router.get(
    "/receipts-payments/{document_id}",
    summary="جزئیات سند دریافت/پرداخت",
    description="دریافت جزئیات یک سند دریافت یا پرداخت",
)
async def get_receipt_payment_endpoint(
    request: Request,
    document_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """دریافت جزئیات سند"""
    result = get_receipt_payment(db, document_id)
    
    if not result:
        raise ApiError(
            "DOCUMENT_NOT_FOUND",
            "Receipt/Payment document not found",
            http_status=404
        )
    
    # بررسی دسترسی
    business_id = result.get("business_id")
    if business_id and not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "Access denied", http_status=403)
    
    return success_response(
        data=format_datetime_fields(result, request),
        request=request,
        message="RECEIPT_PAYMENT_DETAILS"
    )


@router.delete(
    "/receipts-payments/{document_id}",
    summary="حذف سند دریافت/پرداخت",
    description="حذف یک سند دریافت یا پرداخت",
)
async def delete_receipt_payment_endpoint(
    request: Request,
    document_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_management_dep),
):
    """حذف سند"""
    # دریافت سند برای بررسی دسترسی
    result = get_receipt_payment(db, document_id)
    
    if result:
        business_id = result.get("business_id")
        if business_id and not ctx.can_access_business(business_id):
            raise ApiError("FORBIDDEN", "Access denied", http_status=403)
    
    ok = delete_receipt_payment(db, document_id)
    
    if not ok:
        raise ApiError(
            "DOCUMENT_NOT_FOUND",
            "Receipt/Payment document not found",
            http_status=404
        )
    
    return success_response(
        data=None,
        request=request,
        message="RECEIPT_PAYMENT_DELETED"
    )


@router.put(
    "/receipts-payments/{document_id}",
    summary="ویرایش سند دریافت/پرداخت",
    description="به‌روزرسانی یک سند دریافت یا پرداخت",
)
async def update_receipt_payment_endpoint(
    request: Request,
    document_id: int,
    body: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_management_dep),
):
    """ویرایش سند"""
    # دریافت سند برای بررسی دسترسی
    result = get_receipt_payment(db, document_id)
    if not result:
        raise ApiError("DOCUMENT_NOT_FOUND", "Receipt/Payment document not found", http_status=404)

    business_id = result.get("business_id")
    if business_id and not ctx.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "Access denied", http_status=403)

    updated = update_receipt_payment(db, document_id, ctx.get_user_id(), body)
    return success_response(
        data=format_datetime_fields(updated, request),
        request=request,
        message="RECEIPT_PAYMENT_UPDATED",
    )


@router.post(
    "/businesses/{business_id}/receipts-payments/export/excel",
    summary="خروجی Excel لیست اسناد دریافت و پرداخت",
    description="خروجی Excel لیست اسناد دریافت و پرداخت با قابلیت فیلتر، انتخاب سطرها و رعایت ترتیب/نمایش ستون‌ها",
)
@require_business_access("business_id")
async def export_receipts_payments_excel(
    business_id: int,
    request: Request,
    body: Dict[str, Any] = Body(...),
    auth_context: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """خروجی Excel لیست اسناد دریافت و پرداخت"""
    from openpyxl import Workbook
    from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
    from app.core.i18n import negotiate_locale
    
    # Build query dict from flat body
    # For export, we limit to reasonable number to prevent memory issues
    max_export_records = 10000
    take_value = min(int(body.get("take", 1000)), max_export_records)
    
    query_dict = {
        "take": take_value,
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

    result = list_receipts_payments(db, business_id, query_dict)
    items = result.get('items', [])
    items = [format_datetime_fields(item, request) for item in items]
    
    # Check if we hit the limit
    if len(items) >= max_export_records:
        # Add a warning row to indicate data was truncated
        warning_item = {
            "code": "⚠️ هشدار",
            "document_type": "حداکثر ۱۰,۰۰۰ رکورد قابل export است",
            "document_date": "",
            "total_amount": "",
            "person_lines_count": "",
            "account_lines_count": "",
            "created_by_name": "",
            "registered_at": "",
        }
        items.append(warning_item)

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
        # Default columns for receipts/payments
        default_columns = [
            ('code', 'کد سند'),
            ('document_type_name', 'نوع سند'),
            ('document_date', 'تاریخ سند'),
            ('total_amount', 'مبلغ کل'),
            ('person_names', 'اشخاص'),
            ('account_lines_count', 'تعداد حساب‌ها'),
            ('created_by_name', 'ایجادکننده'),
            ('registered_at', 'تاریخ ثبت'),
        ]
        for key, label in default_columns:
            if items and key in items[0]:
                keys.append(key)
                headers.append(label)

    # Create workbook
    wb = Workbook()
    ws = wb.active
    ws.title = "Receipts & Payments"

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
            elif isinstance(value, dict):
                value = str(value)
            cell = ws.cell(row=row_idx, column=col_idx, value=value)
            cell.border = border
            
            # RTL alignment for Persian text
            if locale == 'fa' and isinstance(value, str) and any('\u0600' <= c <= '\u06FF' for c in value):
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
    
    base = "receipts_payments"
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


@router.get(
    "/receipts-payments/{document_id}/pdf",
    summary="خروجی PDF تک سند دریافت/پرداخت",
    description="خروجی PDF یک سند دریافت یا پرداخت",
)
async def export_single_receipt_payment_pdf(
    document_id: int,
    request: Request,
    auth_context: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
    template_id: int | None = None,
):
    """خروجی PDF تک سند دریافت/پرداخت"""
    from weasyprint import HTML, CSS
    from weasyprint.text.fonts import FontConfiguration
    from app.core.i18n import negotiate_locale
    from html import escape
    
    # دریافت سند
    result = get_receipt_payment(db, document_id)
    if not result:
        raise ApiError(
            "DOCUMENT_NOT_FOUND",
            "Receipt/Payment document not found",
            http_status=404
        )
    
    # بررسی دسترسی
    business_id = result.get("business_id")
    if business_id and not auth_context.can_access_business(business_id):
        raise ApiError("FORBIDDEN", "Access denied", http_status=403)
    
    # دریافت اطلاعات کسب‌وکار
    business_name = ""
    try:
        b = db.query(Business).filter(Business.id == business_id).first()
        if b is not None:
            business_name = b.name or ""
    except Exception:
        business_name = ""

    # Locale handling
    locale = negotiate_locale(request.headers.get("Accept-Language"))
    is_fa = locale == 'fa'
    
    # آماده‌سازی داده‌ها
    doc_type_name = result.get("document_type_name", "")
    doc_code = result.get("code", "")
    doc_date = result.get("document_date", "")
    total_amount = result.get("total_amount", 0)
    description = result.get("description", "")
    person_lines = result.get("person_lines", [])
    account_lines = result.get("account_lines", [])
    
    # تاریخ تولید
    now = datetime.datetime.now().strftime('%Y/%m/%d %H:%M')
    title_text = f"سند {doc_type_name}" if is_fa else f"{doc_type_name} Document"
    label_biz = "کسب و کار" if is_fa else "Business"
    label_date = "تاریخ تولید" if is_fa else "Generated Date"
    footer_text = f"تولید شده در {now}" if is_fa else f"Generated at {now}"

    # تلاش برای رندر با قالب سفارشی (receipts_payments/detail)
    resolved_html = None
    try:
        from app.services.report_template_service import ReportTemplateService
        explicit_template_id = None
        try:
            if template_id is not None:
                explicit_template_id = int(template_id)
        except Exception:
            explicit_template_id = None
        template_context = {
            "business_id": business_id,
            "business_name": business_name,
            "document": result,
            "person_lines": person_lines,
            "account_lines": account_lines,
            "code": doc_code,
            "document_date": doc_date,
            "total_amount": total_amount,
            "description": description,
            "title_text": title_text,
            "generated_at": now,
            "is_fa": is_fa,
        }
        resolved_html = ReportTemplateService.try_render_resolved(
            db=db,
            business_id=business_id,
            module_key="receipts_payments",
            subtype="detail",
            context=template_context,
            explicit_template_id=explicit_template_id,
        )
    except Exception:
        resolved_html = None

    # ایجاد HTML پیش‌فرض در نبود قالب
    html_content = resolved_html or f"""
    <!DOCTYPE html>
    <html dir="{'rtl' if is_fa else 'ltr'}">
      <head>
        <meta charset="utf-8">
        <title>{title_text}</title>
        <style>
          @page {{
            margin: 1cm;
            size: A4;
          }}
          body {{
            font-family: {'Tahoma, Arial' if is_fa else 'Arial, sans-serif'};
            font-size: 12px;
            line-height: 1.4;
            color: #333;
            direction: {'rtl' if is_fa else 'ltr'};
          }}
          .header {{
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 2px solid #366092;
          }}
          .title {{
            font-size: 18px;
            font-weight: bold;
            color: #366092;
          }}
          .meta {{
            font-size: 11px;
            color: #666;
          }}
          .document-info {{
            margin: 20px 0;
            padding: 15px;
            border: 1px solid #ddd;
            border-radius: 5px;
            background-color: #f9f9f9;
          }}
          .info-row {{
            display: flex;
            margin-bottom: 8px;
          }}
          .info-label {{
            font-weight: bold;
            width: 150px;
            flex-shrink: 0;
          }}
          .info-value {{
            flex: 1;
          }}
          .section {{
            margin: 20px 0;
          }}
          .section-title {{
            font-size: 14px;
            font-weight: bold;
            margin-bottom: 10px;
            padding: 8px;
            background-color: #366092;
            color: white;
            border-radius: 3px;
          }}
          .lines-table {{
            width: 100%;
            border-collapse: collapse;
            margin: 10px 0;
            font-size: 11px;
          }}
          .lines-table th {{
            background-color: #f0f0f0;
            border: 1px solid #ddd;
            padding: 8px;
            text-align: {'right' if is_fa else 'left'};
            font-weight: bold;
          }}
          .lines-table td {{
            border: 1px solid #ddd;
            padding: 6px;
            text-align: {'right' if is_fa else 'left'};
          }}
          .lines-table tr:nth-child(even) {{
            background-color: #f9f9f9;
          }}
          .amount {{
            text-align: {'left' if is_fa else 'right'};
            font-weight: bold;
          }}
          .commission-row {{
            background-color: #ffe6e6 !important;
            font-style: italic;
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
        <div class="header">
          <div>
            <div class="title">{title_text}</div>
            <div class="meta">{label_biz}: {escape(business_name)}</div>
          </div>
          <div class="meta">{label_date}: {escape(now)}</div>
        </div>
        
        <div class="document-info">
          <div class="info-row">
            <div class="info-label">کد سند:</div>
            <div class="info-value">{escape(doc_code)}</div>
          </div>
          <div class="info-row">
            <div class="info-label">نوع سند:</div>
            <div class="info-value">{escape(doc_type_name)}</div>
          </div>
          <div class="info-row">
            <div class="info-label">تاریخ سند:</div>
            <div class="info-value">{escape(doc_date)}</div>
          </div>
          <div class="info-row">
            <div class="info-label">مبلغ کل:</div>
            <div class="info-value">{escape(str(total_amount))} ریال</div>
          </div>
          {f'<div class="info-row"><div class="info-label">توضیحات:</div><div class="info-value">{escape(description or "")}</div></div>' if description else ''}
        </div>
        
        <div class="section">
          <div class="section-title">خطوط اشخاص</div>
          <table class="lines-table">
            <thead>
              <tr>
                <th>نام شخص</th>
                <th>مبلغ</th>
                <th>توضیحات</th>
              </tr>
            </thead>
            <tbody>
              {''.join([f'<tr><td>{escape(line.get("person_name") or "نامشخص")}</td><td class="amount">{escape(str(line.get("amount", 0)))} ریال</td><td>{escape(line.get("description") or "")}</td></tr>' for line in person_lines])}
            </tbody>
          </table>
        </div>
        
        <div class="section">
          <div class="section-title">خطوط حساب‌ها</div>
          <table class="lines-table">
            <thead>
              <tr>
                <th>نام حساب</th>
                <th>کد حساب</th>
                <th>نوع تراکنش</th>
                <th>مبلغ</th>
                <th>توضیحات</th>
              </tr>
            </thead>
            <tbody>
              {''.join([f'<tr class="{"commission-row" if line.get("extra_info", {}).get("is_commission_line") else ""}"><td>{escape(line.get("account_name") or "")}</td><td>{escape(line.get("account_code") or "")}</td><td>{escape(line.get("transaction_type") or "")}</td><td class="amount">{escape(str(line.get("amount", 0)))} ریال</td><td>{escape(line.get("description") or "")}</td></tr>' for line in account_lines])}
            </tbody>
          </table>
        </div>
        
        <div class="footer">{footer_text}</div>
      </body>
    </html>
    """

    font_config = FontConfiguration()
    pdf_bytes = HTML(string=html_content).write_pdf(font_config=font_config)

    # Build filename
    def slugify(text: str) -> str:
        return re.sub(r"[^A-Za-z0-9_-]+", "_", text).strip("_")
    
    filename = f"receipt_payment_{slugify(doc_code)}_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf"
    
    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f"attachment; filename={filename}",
            "Content-Length": str(len(pdf_bytes)),
            "Access-Control-Expose-Headers": "Content-Disposition",
        },
    )


@router.post(
    "/businesses/{business_id}/receipts-payments/export/pdf",
    summary="خروجی PDF لیست اسناد دریافت و پرداخت",
    description="خروجی PDF لیست اسناد دریافت و پرداخت با قابلیت فیلتر، انتخاب سطرها و رعایت ترتیب/نمایش ستون‌ها",
)
@require_business_access("business_id")
async def export_receipts_payments_pdf(
    business_id: int,
    request: Request,
    body: Dict[str, Any] = Body(...),
    auth_context: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """خروجی PDF لیست اسناد دریافت و پرداخت"""
    from weasyprint import HTML, CSS
    from weasyprint.text.fonts import FontConfiguration
    from app.core.i18n import negotiate_locale
    from html import escape
    
    # Build query dict from flat body
    # For export, we limit to reasonable number to prevent memory issues
    max_export_records = 10000
    take_value = min(int(body.get("take", 1000)), max_export_records)
    
    query_dict = {
        "take": take_value,
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

    result = list_receipts_payments(db, business_id, query_dict)
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

    # Prepare headers and data
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
        # Default columns for receipts/payments
        default_columns = [
            ('code', 'کد سند'),
            ('document_type_name', 'نوع سند'),
            ('document_date', 'تاریخ سند'),
            ('total_amount', 'مبلغ کل'),
            ('person_names', 'اشخاص'),
            ('account_lines_count', 'تعداد حساب‌ها'),
            ('created_by_name', 'ایجادکننده'),
            ('registered_at', 'تاریخ ثبت'),
        ]
        for key, label in default_columns:
            if items and key in items[0]:
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

    # Locale handling
    locale = negotiate_locale(request.headers.get("Accept-Language"))
    is_fa = locale == 'fa'
    
    # Prepare data for HTML
    now = datetime.datetime.now().strftime('%Y/%m/%d %H:%M')
    title_text = "لیست اسناد دریافت و پرداخت" if is_fa else "Receipts & Payments List"
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
            if isinstance(value, list):
                value = ", ".join(str(v) for v in value)
            elif isinstance(value, dict):
                value = str(value)
            row_cells.append(f'<td>{escape(str(value))}</td>')
        rows_html.append(f'<tr>{"".join(row_cells)}</tr>')

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
    }

    # تلاش برای رندر با قالب سفارشی (receipts_payments/list)
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
            module_key="receipts_payments",
            subtype="list",
            context=template_context,
            explicit_template_id=explicit_template_id,
        )
    except Exception:
        resolved_html = None

    # HTML پیش‌فرض جدول
    table_html = f"""
    <!DOCTYPE html>
    <html dir="{'rtl' if is_fa else 'ltr'}">
      <head>
        <meta charset="utf-8">
        <title>{title_text}</title>
        <style>
          @page {{
            margin: 1cm;
            size: A4;
          }}
          body {{
            font-family: {'Tahoma, Arial' if is_fa else 'Arial, sans-serif'};
            font-size: 12px;
            line-height: 1.4;
            color: #333;
            direction: {'rtl' if is_fa else 'ltr'};
          }}
          .header {{
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 2px solid #366092;
          }}
          .title {{
            font-size: 18px;
            font-weight: bold;
            color: #366092;
          }}
          .meta {{
            font-size: 11px;
            color: #666;
          }}
          .table-wrapper {{
            overflow-x: auto;
            margin: 20px 0;
          }}
          .report-table {{
            width: 100%;
            border-collapse: collapse;
            margin: 0;
            font-size: 11px;
          }}
          .report-table thead {{
            background-color: #366092;
            color: white;
          }}
          .report-table th {{
            border: 1px solid #d7dde6;
            padding: 8px 6px;
            text-align: {'right' if is_fa else 'left'};
            font-weight: bold;
            white-space: nowrap;
          }}
          .report-table tbody tr:nth-child(even) {{
            background-color: #f8f9fa;
          }}
          .report-table tbody tr:hover {{
            background-color: #e9ecef;
          }}
          tbody td {{
            border: 1px solid #d7dde6;
            padding: 5px 4px;
            vertical-align: top;
            overflow-wrap: anywhere;
            word-break: break-word;
            white-space: normal;
            text-align: {'right' if is_fa else 'left'};
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
        <div class="header">
          <div>
            <div class="title">{title_text}</div>
            <div class="meta">{label_biz}: {escape(business_name)}</div>
          </div>
          <div class="meta">{label_date}: {escape(now)}</div>
        </div>
        <div class="table-wrapper">
          <table class="report-table">
            <thead>
              <tr>{headers_html}</tr>
            </thead>
            <tbody>
              {''.join(rows_html)}
            </tbody>
          </table>
        </div>
        <div class="footer">{footer_text}</div>
      </body>
    </html>
    """

    final_html = resolved_html or table_html

    font_config = FontConfiguration()
    pdf_bytes = HTML(string=final_html).write_pdf(font_config=font_config)

    # Build meaningful filename
    def slugify(text: str) -> str:
        return re.sub(r"[^A-Za-z0-9_-]+", "_", text).strip("_")
    
    base = "receipts_payments"
    if business_name:
        base += f"_{slugify(business_name)}"
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

