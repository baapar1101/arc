"""خروجی PDF گزارش‌های گردش/لیستی با فیلتر مشترک."""
from __future__ import annotations

from typing import Any, Callable, Dict, List, Optional, Sequence

from fastapi import Request
from sqlalchemy.orm import Session

from app.core.auth_dependency import AuthContext
from app.core.datetime_utils import export_filename_timestamp, format_generated_at_for_pdf, resolve_calendar_type_for_request
from app.core.i18n import negotiate_locale
from app.core.responses import ApiError, format_datetime_fields
from app.services.list_report_export_service import ListReportColumn, list_pdf_response
from app.services.pdf.template_renderer import load_farsi_font_data_uris


def _fiscal_year_id_from_request(body: Dict[str, Any], request: Request, db: Session, business_id: int) -> Optional[int]:
    fiscal_year_id = body.get("fiscal_year_id")
    if fiscal_year_id is not None:
        try:
            return int(fiscal_year_id)
        except (ValueError, TypeError):
            pass
    fy_header = request.headers.get("X-Fiscal-Year-ID")
    if fy_header:
        try:
            return int(fy_header)
        except (ValueError, TypeError):
            pass
    from adapters.db.models.fiscal_year import FiscalYear
    from sqlalchemy import and_

    fiscal_year = (
        db.query(FiscalYear)
        .filter(and_(FiscalYear.business_id == business_id, FiscalYear.is_last == True))  # noqa: E712
        .first()
    )
    return fiscal_year.id if fiscal_year else None


def turnover_pdf_response(
    request: Request,
    business_id: int,
    body: Dict[str, Any],
    ctx: AuthContext,
    db: Session,
    *,
    fetch_fn: Callable[..., Dict[str, Any]],
    columns: Sequence[ListReportColumn],
    filename_prefix: str,
    title_fa: str,
    title_en: str,
    fetch_kwargs: Optional[Dict[str, Any]] = None,
    max_records: int = 10000,
):
    if not ctx.can_read_section("reports"):
        raise ApiError("FORBIDDEN", "Missing business permission: reports.read", http_status=403)

    fiscal_year_id = _fiscal_year_id_from_request(body, request, db, business_id)
    currency_id = body.get("currency_id")
    if currency_id is not None:
        try:
            currency_id = int(currency_id)
        except (ValueError, TypeError):
            currency_id = None

    kwargs = {
        "db": db,
        "business_id": business_id,
        "fiscal_year_id": fiscal_year_id,
        "currency_id": currency_id,
        "date_from": body.get("date_from"),
        "date_to": body.get("date_to"),
        "search": body.get("search"),
        "skip": 0,
        "take": max_records,
    }
    if fetch_kwargs:
        kwargs.update(fetch_kwargs)

    result = fetch_fn(**kwargs)
    items = [format_datetime_fields(item, request) for item in (result.get("items") or [])]
    summary_raw = result.get("summary") or {}
    summary = {str(k): v for k, v in summary_raw.items() if isinstance(v, (int, float, str))}

    locale = negotiate_locale(request.headers.get("Accept-Language"))
    is_fa = locale == "fa"
    generated_at = format_generated_at_for_pdf(business_id, resolve_calendar_type_for_request(request))

    return list_pdf_response(
        items,
        columns,
        db=db,
        business_id=business_id,
        filename_prefix=filename_prefix,
        is_fa=is_fa,
        title=title_fa if is_fa else title_en,
        generated_at=generated_at,
        summary=summary or None,
        export_filename_timestamp=export_filename_timestamp,
        load_farsi_font_data_uris=load_farsi_font_data_uris,
    )


BANK_TURNOVER_COLUMNS = [
    ListReportColumn("document_date", "تاریخ", "Date", "date"),
    ListReportColumn("document_type_name", "نوع سند", "Document Type", "text"),
    ListReportColumn("document_code", "شماره سند", "Document Code", "text"),
    ListReportColumn("bank_account_code", "کد حساب", "Account Code", "text"),
    ListReportColumn("bank_account_name", "نام حساب", "Account Name", "text"),
    ListReportColumn("deposit", "واریز", "Deposit", "number"),
    ListReportColumn("withdrawal", "برداشت", "Withdrawal", "number"),
    ListReportColumn("balance", "مانده", "Balance", "number"),
    ListReportColumn("description", "توضیحات", "Description", "text"),
]

CASH_PETTY_TURNOVER_COLUMNS = [
    ListReportColumn("document_date", "تاریخ", "Date", "date"),
    ListReportColumn("document_type_name", "نوع سند", "Document Type", "text"),
    ListReportColumn("document_code", "شماره سند", "Document Code", "text"),
    ListReportColumn("source_type", "نوع", "Type", "text"),
    ListReportColumn("source_code", "کد", "Code", "text"),
    ListReportColumn("source_name", "نام", "Name", "text"),
    ListReportColumn("deposit", "واریز", "Deposit", "number"),
    ListReportColumn("withdrawal", "برداشت", "Withdrawal", "number"),
    ListReportColumn("balance", "مانده", "Balance", "number"),
    ListReportColumn("description", "توضیحات", "Description", "text"),
]

SALES_BY_PRODUCT_COLUMNS = [
    ListReportColumn("product_code", "کد کالا", "Product Code", "text"),
    ListReportColumn("product_name", "نام کالا", "Product Name", "text"),
    ListReportColumn("unit", "واحد", "Unit", "text"),
    ListReportColumn("category_name", "دسته‌بندی", "Category", "text"),
    ListReportColumn("total_quantity", "تعداد فروش", "Total Quantity", "number"),
    ListReportColumn("total_amount", "مبلغ کل فروش", "Total Amount", "number"),
    ListReportColumn("average_price", "میانگین قیمت", "Average Price", "number"),
    ListReportColumn("last_sale_date", "آخرین تاریخ فروش", "Last Sale Date", "date"),
]
