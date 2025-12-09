from typing import Any, Dict

from fastapi import APIRouter, Depends, Request, Body
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, format_datetime_fields
from app.core.permissions import require_business_access
from adapters.api.v1.schemas import QueryInfo
from app.services.kardex_service import list_kardex_lines
from app.services.pdf.template_renderer import render_template
from app.core.i18n import negotiate_locale
from adapters.db.models.business import Business


router = APIRouter(prefix="/kardex", tags=["گزارش‌ها", "انبارداری"])


@router.post(
    "/businesses/{business_id}/lines",
    summary="لیست کاردکس (خطوط اسناد)",
    description="دریافت خطوط اسناد مرتبط با انتخاب‌های چندگانه موجودیت‌ها با فیلتر تاریخ",
)
@require_business_access("business_id")
async def list_kardex_lines_endpoint(
    request: Request,
    business_id: int,
    query_info: QueryInfo,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    # Compose query dict from QueryInfo and additional parameters from body
    query_dict: Dict[str, Any] = {
        "take": query_info.take,
        "skip": query_info.skip,
        "sort_by": query_info.sort_by or "document_date",
        "sort_desc": query_info.sort_desc,
        "search": query_info.search,
        "search_fields": query_info.search_fields,
        "filters": query_info.filters,
    }

    # Additional params from body (DataTable additionalParams)
    try:
        body_json = await request.json()
        if isinstance(body_json, dict):
            for key in (
                "from_date",
                "to_date",
                "fiscal_year_id",
                "person_ids",
                "product_ids",
                "bank_account_ids",
                "cash_register_ids",
                "petty_cash_ids",
                "account_ids",
                "check_ids",
                "warehouse_ids",
                "match_mode",
                "result_scope",
            ):
                if key in body_json and body_json.get(key) is not None:
                    query_dict[key] = body_json.get(key)
    except Exception:
        pass

    result = list_kardex_lines(db, business_id, query_dict)

    # Format date fields in response items (document_date)
    try:
        items = result.get("items", [])
        for item in items:
            # Use format_datetime_fields for consistency
            item.update(format_datetime_fields({"document_date": item.get("document_date")}, request))
    except Exception:
        pass

    return success_response(data=result, request=request, message="KARDEX_LINES")


@router.post(
    "/businesses/{business_id}/lines/export/excel",
    summary="خروجی Excel کاردکس",
    description="خروجی اکسل از لیست خطوط کاردکس با فیلترهای اعمال‌شده",
)
@require_business_access("business_id")
async def export_kardex_excel_endpoint(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    from fastapi.responses import Response
    import datetime
    try:
        max_export_records = 10000
        take_value = min(int(body.get("take", 1000)), max_export_records)
    except Exception:
        take_value = 1000

    query_dict: Dict[str, Any] = {
        "take": take_value,
        "skip": int(body.get("skip", 0)),
        "sort_by": body.get("sort_by") or "document_date",
        "sort_desc": bool(body.get("sort_desc", True)),
        "search": body.get("search"),
        "search_fields": body.get("search_fields"),
        "filters": body.get("filters"),
        "from_date": body.get("from_date"),
        "to_date": body.get("to_date"),
        "person_ids": body.get("person_ids"),
        "product_ids": body.get("product_ids"),
        "bank_account_ids": body.get("bank_account_ids"),
        "cash_register_ids": body.get("cash_register_ids"),
        "petty_cash_ids": body.get("petty_cash_ids"),
        "account_ids": body.get("account_ids"),
        "check_ids": body.get("check_ids"),
        "warehouse_ids": body.get("warehouse_ids"),
        "match_mode": body.get("match_mode") or "any",
        "result_scope": body.get("result_scope") or "lines_matching",
        "include_running_balance": bool(body.get("include_running_balance", False)),
    }

    result = list_kardex_lines(db, business_id, query_dict)
    items = result.get("items", [])
    items = [format_datetime_fields(it, request) for it in items]

    # Build simple Excel using openpyxl
    from openpyxl import Workbook
    from io import BytesIO

    wb = Workbook()
    ws = wb.active
    ws.title = "Kardex"
    headers = [
        "document_date", "document_code", "document_type", "warehouse", "movement", "description",
        "debit", "credit", "quantity", "running_amount", "running_quantity",
    ]
    ws.append(headers)
    for it in items:
        ws.append([
            it.get("document_date"),
            it.get("document_code"),
            it.get("document_type"),
            it.get("warehouse_name") or it.get("warehouse_id"),
            it.get("movement"),
            it.get("description"),
            it.get("debit"),
            it.get("credit"),
            it.get("quantity"),
            it.get("running_amount"),
            it.get("running_quantity"),
        ])

    buf = BytesIO()
    wb.save(buf)
    content = buf.getvalue()
    filename = f"kardex_{business_id}_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.xlsx"

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
    "/businesses/{business_id}/lines/export/pdf",
    summary="خروجی PDF کاردکس",
    description="خروجی PDF از لیست خطوط کاردکس با فیلترهای اعمال‌شده",
)
@require_business_access("business_id")
async def export_kardex_pdf_endpoint(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    from fastapi.responses import Response
    import datetime
    from weasyprint import HTML, CSS
    from weasyprint.text.fonts import FontConfiguration
    from html import escape

    try:
        max_export_records = 10000
        take_value = min(int(body.get("take", 1000)), max_export_records)
    except Exception:
        take_value = 1000

    query_dict: Dict[str, Any] = {
        "take": take_value,
        "skip": int(body.get("skip", 0)),
        "sort_by": body.get("sort_by") or "document_date",
        "sort_desc": bool(body.get("sort_desc", True)),
        "search": body.get("search"),
        "search_fields": body.get("search_fields"),
        "filters": body.get("filters"),
        "from_date": body.get("from_date"),
        "to_date": body.get("to_date"),
        "person_ids": body.get("person_ids"),
        "product_ids": body.get("product_ids"),
        "bank_account_ids": body.get("bank_account_ids"),
        "cash_register_ids": body.get("cash_register_ids"),
        "petty_cash_ids": body.get("petty_cash_ids"),
        "account_ids": body.get("account_ids"),
        "check_ids": body.get("check_ids"),
        "warehouse_ids": body.get("warehouse_ids"),
        "match_mode": body.get("match_mode") or "any",
        "result_scope": body.get("result_scope") or "lines_matching",
        "include_running_balance": bool(body.get("include_running_balance", False)),
    }

    result = list_kardex_lines(db, business_id, query_dict)
    items = result.get("items", [])
    items = [format_datetime_fields(it, request) for it in items]

    # Build simple HTML table
    def cell(val: Any) -> str:
        return escape(str(val)) if val is not None else ""

    rows_html = "".join([
        f"<tr>"
        f"<td>{cell(it.get('document_date'))}</td>"
        f"<td>{cell(it.get('document_code'))}</td>"
        f"<td>{cell(it.get('document_type'))}</td>"
        f"<td>{cell(it.get('warehouse_name') or it.get('warehouse_id'))}</td>"
        f"<td>{cell(it.get('movement'))}</td>"
        f"<td>{cell(it.get('description'))}</td>"
        f"<td style='text-align:right'>{cell(it.get('debit'))}</td>"
        f"<td style='text-align:right'>{cell(it.get('credit'))}</td>"
        f"<td style='text-align:right'>{cell(it.get('quantity'))}</td>"
        f"<td style='text-align:right'>{cell(it.get('running_amount'))}</td>"
        f"<td style='text-align:right'>{cell(it.get('running_quantity'))}</td>"
        f"</tr>"
        for it in items
    ])

    # تلاش برای رندر با قالب سفارشی (kardex/list) و سپس قالب پیش‌فرض فایل
    resolved_html = None
    try:
        from app.services.report_template_service import ReportTemplateService
        explicit_template_id = None
        try:
            if body.get("template_id") is not None:
                explicit_template_id = int(body.get("template_id"))
        except Exception:
            explicit_template_id = None
        # اطلاعات کسب‌وکار
        business_name = ""
        try:
            b = db.query(Business).filter(Business.id == business_id).first()
            if b is not None:
                business_name = b.name or ""
        except Exception:
            business_name = ""
        # Locale و جهت
        locale = negotiate_locale(request.headers.get("Accept-Language"))
        is_fa = (locale == "fa")
        # پارامترهای صفحه از کوئری (اختیاری)
        try:
            qp = request.query_params
            paper_size = qp.get("paper_size")
            orientation = qp.get("orientation") or "landscape"
            disposition = qp.get("disposition") or "attachment"
        except Exception:
            paper_size = None
            orientation = "landscape"
            disposition = "attachment"
        # کانتکست مشترک
        template_context = {
            "title_text": "گزارش کاردکس" if is_fa else "Kardex Report",
            "business_name": business_name,
            "generated_at": datetime.datetime.now().strftime("%Y/%m/%d %H:%M"),
            "is_fa": is_fa,
            "locale": locale,
            "paper_size": paper_size,
            "orientation": orientation,
            "show_running": bool(query_dict.get("include_running_balance", False)),
            "items": items,
        }
        resolved_html = ReportTemplateService.try_render_resolved(
            db=db,
            business_id=business_id,
            module_key="kardex",
            subtype="list",
            context=template_context,
            explicit_template_id=explicit_template_id,
        )
    except Exception:
        resolved_html = None

    html = f"""
    <html>
      <head>
        <meta charset='utf-8'/>
        <style>
          body {{ font-family: sans-serif; }}
          table {{ width: 100%; border-collapse: collapse; }}
          th, td {{ border: 1px solid #ddd; padding: 6px; font-size: 12px; }}
          th {{ background: #f5f5f5; text-align: right; }}
        </style>
      </head>
      <body>
        <h3>گزارش کاردکس</h3>
        <table>
          <thead>
            <tr>
              <th>تاریخ سند</th>
              <th>کد سند</th>
              <th>نوع سند</th>
              <th>انبار</th>
              <th>جهت حرکت</th>
              <th>شرح</th>
              <th>بدهکار</th>
              <th>بستانکار</th>
              <th>تعداد</th>
              <th>مانده مبلغ</th>
              <th>مانده تعداد</th>
            </tr>
          </thead>
          <tbody>
            {rows_html}
          </tbody>
        </table>
      </body>
    </html>
    """

    # در صورت نبود قالب سفارشی، از قالب فایل استفاده کن
    if not resolved_html:
        try:
            final_html = render_template("pdf/kardex/list.html", {
                "title_text": "گزارش کاردکس",
                "business_name": "",
                "generated_at": datetime.datetime.now().strftime("%Y/%m/%d %H:%M"),
                "is_fa": True,
                "locale": "fa",
                "paper_size": "A4",
                "orientation": "landscape",
                "show_running": bool(query_dict.get("include_running_balance", False)),
                "items": items,
            })
        except Exception:
            final_html = html
    else:
        final_html = resolved_html
    font_config = FontConfiguration()
    pdf_bytes = HTML(string=final_html).write_pdf(stylesheets=[CSS(string="@page { size: A4 landscape; margin: 12mm; }")], font_config=font_config)

    filename = f"kardex_{business_id}_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf"
    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f"attachment; filename={filename}",
            "Content-Length": str(len(pdf_bytes)),
            "Access-Control-Expose-Headers": "Content-Disposition",
        },
    )


