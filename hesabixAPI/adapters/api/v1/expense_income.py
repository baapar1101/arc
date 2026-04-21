"""
API endpoints برای هزینه و درآمد (Expense & Income)
"""

from typing import Any, Dict
from fastapi import APIRouter, Depends, Request, Body
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from adapters.db.models.document import Document
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_management_dep, require_business_access, require_business_permission_dep, require_business_permission_by_entity_dep
from app.core.responses import success_response, format_datetime_fields
from adapters.api.v1.schemas import QueryInfo
from app.core.cache import get_cache
from app.services.expense_income_service import (
    create_expense_income,
    list_expense_income,
    get_expense_income,
    update_expense_income,
    delete_expense_income,
    delete_multiple_expense_income,
)
from app.services.pdf.template_renderer import render_template


router = APIRouter(tags=["expense-income"])


@router.post(
    "/businesses/{business_id}/expense-income/create",
    summary="ایجاد سند هزینه یا درآمد",
    description="ایجاد سند هزینه/درآمد با چند سطر حساب و چند طرف‌حساب",
)
@require_business_access("business_id")
async def create_expense_income_endpoint(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_dep("expenses_income", "add")),
):
    created = create_expense_income(db, business_id, ctx.get_user_id(), body)
    return success_response(
        data=format_datetime_fields(created, request),
        request=request,
        message="EXPENSE_INCOME_CREATED",
    )


@router.post(
    "/businesses/{business_id}/expense-income",
    summary="لیست اسناد هزینه/درآمد",
    description="دریافت لیست اسناد هزینه/درآمد با جستجو و صفحه‌بندی",
)
@require_business_access("business_id")
async def list_expense_income_endpoint(
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
        "sort": [s.model_dump() for s in query_info.sort] if query_info.sort else None,
        "search": query_info.search,
    }
    if getattr(query_info, "search_fields", None):
        query_dict["search_fields"] = list(query_info.search_fields)
    if getattr(query_info, "filters", None):
        query_dict["filters"] = [f.model_dump() for f in query_info.filters]

    body_json: Dict[str, Any] = {}
    try:
        raw = await request.json()
        if isinstance(raw, dict):
            body_json = raw
    except Exception:
        body_json = {}

    merge_keys = (
        "document_type",
        "from_date",
        "to_date",
        "sort",
        "sort_by",
        "sort_desc",
        "take",
        "skip",
        "search",
        "fiscal_year_id",
        "project_id",
        "account_id",
        "search_fields",
        "filters",
    )
    for key in merge_keys:
        if key in body_json:
            query_dict[key] = body_json[key]

    if query_dict.get("fiscal_year_id") is None:
        try:
            fy_header = request.headers.get("X-Fiscal-Year-ID")
            if fy_header:
                query_dict["fiscal_year_id"] = int(fy_header)
        except Exception:
            pass

    # کش نتایج لیست هزینه/درآمد
    cache = get_cache()
    cache_key = None
    fiscal_year_id = query_dict.get("fiscal_year_id")

    if cache.enabled:
        import json, hashlib
        key_payload = {
            "business_id": business_id,
            "query": query_dict,
        }
        key_str = json.dumps(key_payload, sort_keys=True, ensure_ascii=False)
        key_hash = hashlib.sha256(key_str.encode("utf-8")).hexdigest()[:16]
        cache_key = f"expense_income_list:{key_hash}"
        cached = cache.get(cache_key)
        if cached is not None:
            return success_response(data=cached, request=request, message="EXPENSE_INCOME_LIST_FETCHED")

    result = list_expense_income(db, business_id, query_dict)
    result["items"] = [format_datetime_fields(item, request) for item in result.get("items", [])]

    # ذخیره در cache با tag-based caching
    if cache.enabled and cache_key:
        cache.set_with_expense_income_tag(
            key=cache_key,
            value=result,
            business_id=business_id,
            fiscal_year_id=fiscal_year_id,
            ttl=60
        )

    return success_response(data=result, request=request, message="EXPENSE_INCOME_LIST_FETCHED")


@router.get(
    "/expense-income/{document_id}",
    summary="جزئیات سند هزینه/درآمد",
    description="دریافت جزئیات یک سند هزینه یا درآمد",
)
async def get_expense_income_endpoint(
    request: Request,
    document_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """دریافت جزئیات سند"""
    result = get_expense_income(db, document_id)
    
    if not result:
        from app.core.responses import ApiError
        raise ApiError(
            "DOCUMENT_NOT_FOUND",
            "Expense/Income document not found",
            http_status=404
        )
    
    # بررسی دسترسی
    business_id = result.get("business_id")
    if business_id and not ctx.can_access_business(business_id):
        from app.core.responses import ApiError
        raise ApiError("FORBIDDEN", "Access denied", http_status=403)
    
    return success_response(
        data=format_datetime_fields(result, request),
        request=request,
        message="EXPENSE_INCOME_DETAILS"
    )


@router.put(
    "/expense-income/{document_id}",
    summary="ویرایش سند هزینه/درآمد",
    description="ویرایش یک سند هزینه یا درآمد",
)
async def update_expense_income_endpoint(
    request: Request,
    document_id: int,
    body: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_by_entity_dep("expenses_income", "edit", Document, "document_id")),
):
    """ویرایش سند هزینه/درآمد"""
    updated = update_expense_income(db, document_id, ctx.get_user_id(), body)
    
    return success_response(
        data=format_datetime_fields(updated, request),
        request=request,
        message="EXPENSE_INCOME_UPDATED"
    )


@router.delete(
    "/expense-income/{document_id}",
    summary="حذف سند هزینه/درآمد",
    description="حذف یک سند هزینه یا درآمد",
)
async def delete_expense_income_endpoint(
    request: Request,
    document_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
    _: None = Depends(require_business_permission_by_entity_dep("expenses_income", "delete", Document, "document_id")),
):
    """حذف سند هزینه/درآمد"""
    success = delete_expense_income(db, document_id)
    
    if not success:
        from app.core.responses import ApiError
        raise ApiError("DELETE_FAILED", "Failed to delete document", http_status=500)
    
    return success_response(
        data={"deleted": True},
        request=request,
        message="EXPENSE_INCOME_DELETED"
    )


@router.post(
    "/expense-income/bulk-delete",
    summary="حذف گروهی اسناد هزینه/درآمد",
    description="حذف چندین سند هزینه یا درآمد",
)
async def delete_multiple_expense_income_endpoint(
    request: Request,
    body: Dict[str, Any] = Body(...),
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """حذف گروهی اسناد"""
    document_ids = body.get("document_ids", [])
    if not document_ids:
        from app.core.responses import ApiError
        raise ApiError("INVALID_REQUEST", "document_ids is required", http_status=400)
    
    # بررسی دسترسی برای هر document
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
                    raise ApiError("FORBIDDEN", f"Missing permission: expenses_income.delete for document {doc_id}", http_status=403)
                
                permissions = ctx._normalize_permissions_value(permission_obj.business_permissions)
                if "expenses_income" not in permissions:
                    raise ApiError("FORBIDDEN", f"Missing permission: expenses_income.delete for document {doc_id}", http_status=403)
                
                section_perms = permissions.get("expenses_income", {})
                if not section_perms.get("delete", False):
                    raise ApiError("FORBIDDEN", f"Missing permission: expenses_income.delete for document {doc_id}", http_status=403)
        except ApiError:
            raise
        except Exception:
            continue
    
    success = delete_multiple_expense_income(db, document_ids)
    
    if not success:
        from app.core.responses import ApiError
        raise ApiError("DELETE_FAILED", "Failed to delete documents", http_status=500)
    
    return success_response(
        data={"deleted_count": len(document_ids)},
        request=request,
        message="EXPENSE_INCOME_BULK_DELETED"
    )


@router.post(
    "/businesses/{business_id}/expense-income/export/excel",
    summary="خروجی Excel اسناد هزینه/درآمد",
    description="دریافت فایل Excel لیست اسناد هزینه/درآمد",
)
@require_business_access("business_id")
async def export_expense_income_excel_endpoint(
    request: Request,
    business_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """خروجی Excel"""
    from app.services.expense_income_service import export_expense_income_excel
    from fastapi.responses import Response
    
    # دریافت پارامترهای فیلتر
    query_dict = {}
    try:
        body_json = await request.json()
        if isinstance(body_json, dict):
            for key in [
                "document_type", "from_date", "to_date", "project_id",
                "take", "skip", "sort_by", "sort_desc", "sort",
                "search", "search_fields", "filters",
                "fiscal_year_id", "account_id",
            ]:
                if key in body_json:
                    query_dict[key] = body_json[key]
    except Exception:
        pass
    
    if query_dict.get("fiscal_year_id") is None:
        try:
            fy_header = request.headers.get("X-Fiscal-Year-ID")
            if fy_header:
                query_dict["fiscal_year_id"] = int(fy_header)
        except Exception:
            pass
    
    excel_data = export_expense_income_excel(db, business_id, query_dict)
    
    return Response(
        content=excel_data,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f"attachment; filename=expense_income_{business_id}.xlsx"}
    )


@router.post(
    "/businesses/{business_id}/expense-income/export/pdf",
    summary="خروجی PDF اسناد هزینه/درآمد",
    description="دریافت فایل PDF لیست اسناد هزینه/درآمد",
)
@require_business_access("business_id")
async def export_expense_income_pdf_endpoint(
    request: Request,
    business_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """خروجی PDF (با پشتیبانی قالب سفارشی expense_income/list)"""
    from fastapi.responses import Response
    from weasyprint import HTML
    from weasyprint.text.fonts import FontConfiguration
    from app.core.i18n import negotiate_locale
    from html import escape
    import datetime, json
    # دریافت پارامترهای فیلتر و تنظیمات
    try:
        body = await request.json()
    except Exception:
        body = {}
    # ساخت query برای لیست
    query_dict = {
        "take": int(body.get("take", 1000)),
        "skip": int(body.get("skip", 0)),
        "sort_by": body.get("sort_by"),
        "sort_desc": bool(body.get("sort_desc", False)),
        "sort": body.get("sort") if isinstance(body.get("sort"), list) else None,
        "search": body.get("search"),
        "search_fields": body.get("search_fields"),
        "filters": body.get("filters"),
        "document_type": body.get("document_type"),
        "from_date": body.get("from_date"),
        "to_date": body.get("to_date"),
        "project_id": body.get("project_id"),
        "account_id": body.get("account_id"),
    }
    try:
        if body.get("fiscal_year_id") is not None:
            query_dict["fiscal_year_id"] = int(body.get("fiscal_year_id"))
        else:
            fy_header = request.headers.get("X-Fiscal-Year-ID")
            if fy_header:
                query_dict["fiscal_year_id"] = int(fy_header)
    except Exception:
        pass
    # دریافت داده‌ها
    from app.services.expense_income_service import list_expense_income
    from adapters.db.models.business import Business
    from app.core.responses import format_datetime_fields
    result = list_expense_income(db, business_id, query_dict)
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
            ("total_amount", "مبلغ کل"),
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
        b = db.query(Business).filter(Business.id == business_id).first()
        if b is not None:
            business_name = b.name or ""
    except Exception:
        business_name = ""
    # Locale
    locale = negotiate_locale(request.headers.get("Accept-Language"))
    is_fa = locale == "fa"
    now = datetime.datetime.now().strftime('%Y/%m/%d %H:%M')
    title_text = "لیست اسناد هزینه/درآمد" if is_fa else "Expense/Income List"
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
    # کانتکست برای قالب سفارشی
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
            module_key="expense_income",
            subtype="list",
            context=template_context,
            explicit_template_id=explicit_template_id,
        )
    except Exception:
        resolved_html = None
    # HTML پیش‌فرض با قالب فایل
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
    final_html = resolved_html or render_template(
        "pdf/expense_income/list.html",
        {
            **template_context,
            "title_text": title_text,
            "paper_size": paper_size,
            "orientation": orientation,
            "footer_text": footer_text,
        },
    )
    pdf_bytes = HTML(string=final_html).write_pdf(font_config=FontConfiguration())
    filename = f"expense_income_{business_id}_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf"
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
    "/expense-income/{document_id}/pdf",
    summary="PDF یک سند هزینه/درآمد",
    description="دریافت فایل PDF یک سند هزینه یا درآمد",
)
async def get_expense_income_pdf_endpoint(
    request: Request,
    document_id: int,
    db: Session = Depends(get_db),
    ctx: AuthContext = Depends(get_current_user),
):
    """PDF یک سند (سبک فاکتور: قالب سفارشی یا پیش‌فرض Jinja + WeasyPrint)"""
    from fastapi.responses import Response
    from weasyprint import HTML
    from weasyprint.text.fonts import FontConfiguration
    from app.core.i18n import negotiate_locale
    from html import escape
    import datetime, re

    # دریافت سند و بررسی دسترسی
    item = get_expense_income(db, document_id)
    if not item:
        from app.core.responses import ApiError
        raise ApiError("DOCUMENT_NOT_FOUND", "Document not found", http_status=404)
    business_id = item.get("business_id")
    if business_id and not ctx.can_access_business(business_id):
        from app.core.responses import ApiError
        raise ApiError("FORBIDDEN", "Access denied", http_status=403)

    # اطلاعات کسب‌وکار
    business_name = ""
    business_info: Dict[str, Any] = {}
    try:
        from adapters.db.models.business import Business
        b = db.query(Business).filter(Business.id == business_id).first()
        if b is not None:
            business_name = b.name or ""
            business_info = {
                "name": b.name,
                "economic_code": getattr(b, "economic_code", None),
                "registration_number": getattr(b, "registration_number", None),
                "phone": getattr(b, "phone", None),
                "address": getattr(b, "address", None),
            }
    except Exception:
        business_name = business_name or ""

    # فونت فارسی (YekanBakhFaNum) مشابه فاکتورها
    fa_font_url_regular = None
    fa_font_url_bold = None
    try:
        from pathlib import Path
        project_root = Path(__file__).resolve().parents[4]
        fonts_dir = project_root / "hesabixUI" / "hesabix_ui" / "assets" / "fonts"
        # Preferred: YekanBakhFaNum
        regular_path = fonts_dir / "YekanBakhFaNum-Regular.ttf"
        bold_path = fonts_dir / "YekanBakhFaNum-Bold.ttf"
        # Fallbacks: Vazirmatn
        regular_fallback = fonts_dir / "Vazirmatn-Regular.ttf"
        bold_fallback = fonts_dir / "Vazirmatn-Bold.ttf"
        import base64 as _b64
        if regular_path.is_file():
            _data = regular_path.read_bytes()
            fa_font_url_regular = f"data:font/ttf;base64,{_b64.b64encode(_data).decode('ascii')}"
        elif regular_fallback.is_file():
            _data = regular_fallback.read_bytes()
            fa_font_url_regular = f"data:font/ttf;base64,{_b64.b64encode(_data).decode('ascii')}"
        if bold_path.is_file():
            _data_b = bold_path.read_bytes()
            fa_font_url_bold = f"data:font/ttf;base64,{_b64.b64encode(_data_b).decode('ascii')}"
        elif bold_fallback.is_file():
            _data_b = bold_fallback.read_bytes()
            fa_font_url_bold = f"data:font/ttf;base64,{_b64.b64encode(_data_b).decode('ascii')}"
    except Exception:
        fa_font_url_regular = None
        fa_font_url_bold = None

    # Locale و Calendar
    locale = negotiate_locale(request.headers.get("Accept-Language"))
    is_fa = locale == "fa"
    from app.core.calendar import CalendarConverter, get_calendar_type_from_header
    from datetime import datetime as _dt
    def _parse_dt(val: str | None) -> _dt | None:
        if not val:
            return None
        try:
            # handle possible timezone 'Z'
            v = str(val).replace("Z", "+00:00")
            return _dt.fromisoformat(v)
        except Exception:
            return None
    calendar_type = get_calendar_type_from_header(request.headers.get("X-Calendar-Type"))
    # تاریخ‌های هدر
    doc_dt = _parse_dt(item.get("document_date"))
    doc_date_g = CalendarConverter.to_gregorian(doc_dt)["date_only"] if doc_dt else ""
    doc_date_j = CalendarConverter.to_jalali(doc_dt)["date_only"] if doc_dt else ""

    # محاسبه مبلغ کل درصورت نبود
    def _as_num(x):
        try:
            return float(x)
        except Exception:
            return 0.0
    total_amount = item.get("total_amount")
    if total_amount is None:
        il = item.get("item_lines") or item.get("items") or []
        if il:
            # اگر amount بود جمع می‌زنیم؛ در غیر اینصورت از debit/credit با توجه به نوع سند
            if any("amount" in r for r in il):
                total_amount = sum(_as_num(r.get("amount")) for r in il)
            else:
                if str(item.get("document_type")) == "income":
                    total_amount = sum(_as_num(r.get("credit")) for r in il)
                else:
                    total_amount = sum(_as_num(r.get("debit")) for r in il)
        else:
            cps = item.get("counterparty_lines") or item.get("counterparties") or []
            if cps:
                if any("amount" in r for r in cps):
                    total_amount = sum(_as_num(r.get("amount")) for r in cps)
                else:
                    if str(item.get("document_type")) == "income":
                        total_amount = sum(_as_num(r.get("debit")) for r in cps)
                    else:
                        total_amount = sum(_as_num(r.get("credit")) for r in cps)
    item["total_amount"] = total_amount

    # قالب‌بندی تاریخ تراکنش‌های طرف‌حساب
    raw_cps = item.get("counterparty_lines") or item.get("counterparties") or []
    counterparty_lines_fmt = []
    for cp in raw_cps:
        tx_raw = (cp.get("transaction_date") or (cp.get("extra_info") or {}).get("transaction_date"))
        tx_dt = _parse_dt(tx_raw)
        cp_copy = dict(cp)
        cp_copy["txn_date_g"] = CalendarConverter.to_gregorian(tx_dt)["date_only"] if tx_dt else ""
        cp_copy["txn_date_j"] = CalendarConverter.to_jalali(tx_dt)["date_only"] if tx_dt else ""
        counterparty_lines_fmt.append(cp_copy)

    # زمینه قالب
    template_context = {
        "business_id": business_id,
        "business_name": business_name,
        "business": business_info,
        "document": item,
        "item_lines": item.get("item_lines") or item.get("items") or [],
        "counterparty_lines": raw_cps,
        "counterparty_lines_fmt": counterparty_lines_fmt,
        "is_fa": is_fa,
        "is_jalali": (calendar_type == "jalali"),
        "fa_font_url_regular": fa_font_url_regular,
        "fa_font_url_bold": fa_font_url_bold,
        "generated_at": datetime.datetime.now(),
        "document_date_jalali": doc_date_j,
        "document_date_gregorian": doc_date_g,
    }

    # تلاش برای استفاده از قالب سفارشی
    resolved_html = None
    try:
        from app.services.report_template_service import ReportTemplateService
        explicit_template_id = None
        try:
            # پشتیبانی از ?template_id=...
            if request.query_params.get("template_id") is not None:
                explicit_template_id = int(request.query_params.get("template_id"))
        except Exception:
            explicit_template_id = None
        resolved_html = ReportTemplateService.try_render_resolved(
            db=db,
            business_id=business_id,
            module_key="expense_income",
            subtype="detail",
            context=template_context,
            explicit_template_id=explicit_template_id,
        )
    except Exception:
        resolved_html = None

    # پارامترهای نمایشی
    disposition = request.query_params.get("disposition") or "attachment"
    paper_size = request.query_params.get("paper_size")
    orientation = request.query_params.get("orientation")

    # HTML پیش‌فرض
    html_content = resolved_html or render_template(
        "pdf/expense_income/detail.html",
        {
            **template_context,
            "title_text": ("سند هزینه/درآمد" if is_fa else "Expense/Income"),
            "paper_size": paper_size,
            "orientation": orientation,
        },
    )

    font_config = FontConfiguration()
    pdf_bytes = HTML(string=html_content).write_pdf(font_config=font_config)

    # نام فایل
    def _slugify(text: str) -> str:
        return re.sub(r"[^A-Za-z0-9_-]+", "_", (text or "")).strip("_") or "expense_income"
    filename = f"expense_income_{_slugify(str(item.get('code') or document_id))}_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf"

    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f"{disposition}; filename={filename}",
            "Content-Length": str(len(pdf_bytes)),
            "Access-Control-Expose-Headers": "Content-Disposition",
        },
    )


