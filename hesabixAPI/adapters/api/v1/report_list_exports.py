"""پیکربندی و هندلر export گزارش‌های لیستی در documents."""
from __future__ import annotations

from typing import Any, Callable, Dict, List, Optional

from fastapi import Body, Depends, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.datetime_utils import export_filename_timestamp, format_generated_at_for_pdf, resolve_calendar_type_for_request
from app.core.i18n import negotiate_locale
from app.core.permissions import require_business_access, require_business_permission_dep
from app.core.responses import ApiError, format_datetime_fields
from app.services.invoice_service import (
    get_daily_sales_report,
    get_materials_consumption_report,
    get_monthly_sales_report,
    get_production_report,
    get_top_customers_report,
    get_top_suppliers_report,
)
from app.services.list_report_export_service import ListReportColumn, list_excel_response, list_pdf_response
from app.services.pdf.template_renderer import load_farsi_font_data_uris


def _parse_common_filters(body: Dict[str, Any], request: Request) -> Dict[str, Any]:
    fiscal_year_id = body.get("fiscal_year_id")
    if fiscal_year_id is not None:
        try:
            fiscal_year_id = int(fiscal_year_id)
        except (ValueError, TypeError):
            fiscal_year_id = None
    fy_header = request.headers.get("X-Fiscal-Year-ID")
    if not fiscal_year_id and fy_header:
        try:
            fiscal_year_id = int(fy_header)
        except (ValueError, TypeError):
            pass

    currency_id = body.get("currency_id")
    if currency_id is not None:
        try:
            currency_id = int(currency_id)
        except (ValueError, TypeError):
            currency_id = None

    limit = body.get("limit")
    if limit is not None:
        try:
            limit = int(limit)
        except (ValueError, TypeError):
            limit = None

    product_id = body.get("product_id")
    warehouse_id = body.get("warehouse_id")
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

    return {
        "fiscal_year_id": fiscal_year_id,
        "currency_id": currency_id,
        "date_from": body.get("date_from"),
        "date_to": body.get("date_to"),
        "limit": limit,
        "product_id": product_id,
        "warehouse_id": warehouse_id,
    }


DAILY_SALES_COLUMNS = [
    ListReportColumn("date", "تاریخ", "Date", "date"),
    ListReportColumn("invoice_count", "تعداد فاکتور", "Invoices", "number"),
    ListReportColumn("total_gross", "جمع کل", "Gross", "number"),
    ListReportColumn("total_discount", "جمع تخفیف", "Discount", "number"),
    ListReportColumn("total_tax", "جمع مالیات", "Tax", "number"),
    ListReportColumn("total_net", "جمع خالص", "Net", "number"),
]

MONTHLY_SALES_COLUMNS = [
    ListReportColumn("month_key", "ماه", "Month", "text"),
    ListReportColumn("invoice_count", "تعداد فاکتور", "Invoices", "number"),
    ListReportColumn("total_gross", "جمع کل", "Gross", "number"),
    ListReportColumn("total_discount", "جمع تخفیف", "Discount", "number"),
    ListReportColumn("total_tax", "جمع مالیات", "Tax", "number"),
    ListReportColumn("total_net", "جمع خالص", "Net", "number"),
]

TOP_CUSTOMERS_COLUMNS = [
    ListReportColumn("person_code", "کد مشتری", "Customer Code", "text"),
    ListReportColumn("person_name", "نام مشتری", "Customer Name", "text"),
    ListReportColumn("invoice_count", "تعداد فاکتور", "Invoices", "number"),
    ListReportColumn("total_sales", "جمع فروش", "Total Sales", "number"),
    ListReportColumn("last_sale_date", "آخرین فروش", "Last Sale", "date"),
]

TOP_SUPPLIERS_COLUMNS = [
    ListReportColumn("person_code", "کد تامین‌کننده", "Supplier Code", "text"),
    ListReportColumn("person_name", "نام تامین‌کننده", "Supplier Name", "text"),
    ListReportColumn("invoice_count", "تعداد فاکتور", "Invoices", "number"),
    ListReportColumn("total_purchases", "جمع خرید", "Total Purchases", "number"),
    ListReportColumn("last_purchase_date", "آخرین خرید", "Last Purchase", "date"),
]

MATERIALS_COLUMNS = [
    ListReportColumn("document_date", "تاریخ", "Date", "date"),
    ListReportColumn("document_code", "شماره سند", "Doc No.", "text"),
    ListReportColumn("product_code", "کد کالا", "Product Code", "text"),
    ListReportColumn("product_name", "نام کالا", "Product Name", "text"),
    ListReportColumn("warehouse_name", "انبار", "Warehouse", "text"),
    ListReportColumn("quantity", "مقدار", "Qty", "number"),
    ListReportColumn("unit_price", "قیمت واحد", "Unit Price", "number"),
    ListReportColumn("amount", "مبلغ", "Amount", "number"),
]

PRODUCTION_COLUMNS = [
    ListReportColumn("document_date", "تاریخ", "Date", "date"),
    ListReportColumn("document_code", "شماره سند", "Doc No.", "text"),
    ListReportColumn("product_code", "کد کالا", "Product Code", "text"),
    ListReportColumn("product_name", "نام کالا", "Product Name", "text"),
    ListReportColumn("warehouse_name", "انبار", "Warehouse", "text"),
    ListReportColumn("quantity", "مقدار", "Qty", "number"),
    ListReportColumn("unit_price", "قیمت واحد", "Unit Price", "number"),
    ListReportColumn("amount", "مبلغ", "Amount", "number"),
]


def _fetch_daily_sales(db, business_id, f):
    return get_daily_sales_report(
        db, business_id,
        fiscal_year_id=f["fiscal_year_id"], currency_id=f["currency_id"],
        date_from=f["date_from"], date_to=f["date_to"], skip=0, take=10000,
    )


def _fetch_monthly_sales(db, business_id, f):
    return get_monthly_sales_report(
        db, business_id,
        fiscal_year_id=f["fiscal_year_id"], currency_id=f["currency_id"],
        date_from=f["date_from"], date_to=f["date_to"], skip=0, take=10000,
    )


def _fetch_top_customers(db, business_id, f):
    return get_top_customers_report(
        db, business_id,
        fiscal_year_id=f["fiscal_year_id"], currency_id=f["currency_id"],
        date_from=f["date_from"], date_to=f["date_to"],
        limit=f.get("limit"), skip=0, take=10000,
    )


def _fetch_top_suppliers(db, business_id, f):
    return get_top_suppliers_report(
        db, business_id,
        fiscal_year_id=f["fiscal_year_id"], currency_id=f["currency_id"],
        date_from=f["date_from"], date_to=f["date_to"],
        limit=f.get("limit"), skip=0, take=10000,
    )


def _fetch_materials(db, business_id, f):
    return get_materials_consumption_report(
        db, business_id,
        fiscal_year_id=f["fiscal_year_id"], currency_id=f["currency_id"],
        date_from=f["date_from"], date_to=f["date_to"],
        product_id=f.get("product_id"), warehouse_id=f.get("warehouse_id"),
        skip=0, take=10000,
    )


def _fetch_production(db, business_id, f):
    return get_production_report(
        db, business_id,
        fiscal_year_id=f["fiscal_year_id"], currency_id=f["currency_id"],
        date_from=f["date_from"], date_to=f["date_to"],
        product_id=f.get("product_id"), warehouse_id=f.get("warehouse_id"),
        skip=0, take=10000,
    )


def export_list_report_handler(
    request: Request,
    business_id: int,
    body: Dict[str, Any],
    ctx: AuthContext,
    db: Session,
    *,
    fetch_fn: Callable,
    columns: List[ListReportColumn],
    filename_prefix: str,
    title_fa: str,
    title_en: str,
    fmt: str,
):
    if not ctx.can_read_section("reports"):
        raise ApiError("FORBIDDEN", "Missing business permission: reports.read", http_status=403)

    filters = _parse_common_filters(body, request)
    result = fetch_fn(db, business_id, filters)
    items = [format_datetime_fields(item, request) for item in (result.get("items") or [])]
    summary_raw = result.get("summary") or {}
    summary = {str(k): v for k, v in summary_raw.items() if isinstance(v, (int, float, str))}

    locale = negotiate_locale(request.headers.get("Accept-Language"))
    is_fa = locale == "fa"
    title = title_fa if is_fa else title_en

    if fmt == "excel":
        return list_excel_response(
            items, columns,
            db=db, business_id=business_id, filename_prefix=filename_prefix,
            is_fa=is_fa, title=title, summary=summary or None,
            export_filename_timestamp=export_filename_timestamp,
        )

    generated_at = format_generated_at_for_pdf(business_id, resolve_calendar_type_for_request(request))
    return list_pdf_response(
        items, columns,
        db=db, business_id=business_id, filename_prefix=filename_prefix,
        is_fa=is_fa, title=title, generated_at=generated_at, summary=summary or None,
        export_filename_timestamp=export_filename_timestamp,
        load_farsi_font_data_uris=load_farsi_font_data_uris,
    )


def register_document_list_exports(router) -> None:
    """ثبت endpointهای export گزارش‌های لیستی روی router اسناد."""

    def _excel(fetch_fn, columns, prefix, title_fa, title_en, slug):
        @router.post(
            f"/businesses/{{business_id}}/reports/{slug}/export/excel",
            summary=f"خروجی Excel — {title_fa}",
        )
        @require_business_access("business_id")
        async def _handler(
            request: Request,
            business_id: int,
            body: Dict[str, Any] = Body(default={}),
            ctx: AuthContext = Depends(get_current_user),
            db: Session = Depends(get_db),
            _: None = Depends(require_business_permission_dep("reports", "export")),
        ):
            return export_list_report_handler(
                request, business_id, body, ctx, db,
                fetch_fn=fetch_fn, columns=columns, filename_prefix=prefix,
                title_fa=title_fa, title_en=title_en, fmt="excel",
            )
        return _handler

    def _pdf(fetch_fn, columns, prefix, title_fa, title_en, slug):
        @router.post(
            f"/businesses/{{business_id}}/reports/{slug}/export/pdf",
            summary=f"خروجی PDF — {title_fa}",
        )
        @require_business_access("business_id")
        async def _handler(
            request: Request,
            business_id: int,
            body: Dict[str, Any] = Body(default={}),
            ctx: AuthContext = Depends(get_current_user),
            db: Session = Depends(get_db),
            _: None = Depends(require_business_permission_dep("reports", "export")),
        ):
            return export_list_report_handler(
                request, business_id, body, ctx, db,
                fetch_fn=fetch_fn, columns=columns, filename_prefix=prefix,
                title_fa=title_fa, title_en=title_en, fmt="pdf",
            )
        return _handler

    specs_full = [
        (_fetch_daily_sales, DAILY_SALES_COLUMNS, "daily_sales", "گزارش فروش روزانه", "Daily Sales Report", "daily-sales"),
        (_fetch_monthly_sales, MONTHLY_SALES_COLUMNS, "monthly_sales", "گزارش فروش ماهانه", "Monthly Sales Report", "monthly-sales"),
        (_fetch_top_customers, TOP_CUSTOMERS_COLUMNS, "top_customers", "گزارش برترین مشتریان", "Top Customers Report", "top-customers"),
        (_fetch_materials, MATERIALS_COLUMNS, "materials_consumption", "گزارش مصرف مواد", "Materials Consumption Report", "materials-consumption"),
        (_fetch_production, PRODUCTION_COLUMNS, "production", "گزارش تولید", "Production Report", "production"),
    ]
    specs_pdf_only = [
        (_fetch_top_suppliers, TOP_SUPPLIERS_COLUMNS, "top_suppliers", "گزارش برترین تامین‌کنندگان", "Top Suppliers Report", "top-suppliers"),
    ]
    for fetch_fn, columns, prefix, title_fa, title_en, slug in specs_full:
        _excel(fetch_fn, columns, prefix, title_fa, title_en, slug)
        _pdf(fetch_fn, columns, prefix, title_fa, title_en, slug)
    for fetch_fn, columns, prefix, title_fa, title_en, slug in specs_pdf_only:
        _pdf(fetch_fn, columns, prefix, title_fa, title_en, slug)
