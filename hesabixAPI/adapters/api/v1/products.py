# Removed __future__ annotations to fix OpenAPI schema generation

from typing import Dict, Any
from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access
from app.core.responses import success_response, ApiError, format_datetime_fields
from adapters.api.v1.schemas import QueryInfo
from adapters.api.v1.schema_models.product import (
    ProductCreateRequest,
    ProductUpdateRequest,
    BulkPriceUpdateRequest,
    BulkPriceUpdatePreviewResponse,
)
from app.services.product_service import (
    create_product,
    list_products,
    get_product,
    update_product,
    delete_product,
)
from app.services.bulk_price_update_service import (
    preview_bulk_price_update,
    apply_bulk_price_update,
)
from adapters.db.models.business import Business
from app.core.i18n import negotiate_locale
from fastapi import UploadFile, File, Form


router = APIRouter(prefix="/products", tags=["products"])


@router.post("/business/{business_id}")
@require_business_access("business_id")
def create_product_endpoint(
    request: Request,
    business_id: int,
    payload: ProductCreateRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    if not ctx.has_business_permission("inventory", "write"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.write", http_status=403)
    result = create_product(db, business_id, payload)
    return success_response(data=format_datetime_fields(result["data"], request), request=request, message=result.get("message"))


@router.post("/business/{business_id}/search")
@require_business_access("business_id")
def search_products_endpoint(
    request: Request,
    business_id: int,
    query_info: QueryInfo,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    if not ctx.can_read_section("inventory"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.read", http_status=403)
    result = list_products(db, business_id, {
        "take": query_info.take,
        "skip": query_info.skip,
        "sort_by": query_info.sort_by,
        "sort_desc": query_info.sort_desc,
        "search": query_info.search,
        "filters": query_info.filters,
    })
    return success_response(data=format_datetime_fields(result, request), request=request)


@router.get("/business/{business_id}/{product_id}")
@require_business_access("business_id")
def get_product_endpoint(
    request: Request,
    business_id: int,
    product_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    if not ctx.can_read_section("inventory"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.read", http_status=403)
    item = get_product(db, product_id, business_id)
    if not item:
        raise ApiError("NOT_FOUND", "Product not found", http_status=404)
    return success_response(data=format_datetime_fields({"item": item}, request), request=request)


@router.put("/business/{business_id}/{product_id}")
@require_business_access("business_id")
def update_product_endpoint(
    request: Request,
    business_id: int,
    product_id: int,
    payload: ProductUpdateRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    if not ctx.has_business_permission("inventory", "write"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.write", http_status=403)
    result = update_product(db, product_id, business_id, payload)
    if not result:
        raise ApiError("NOT_FOUND", "Product not found", http_status=404)
    return success_response(data=format_datetime_fields(result["data"], request), request=request, message=result.get("message"))


@router.delete("/business/{business_id}/{product_id}")
@require_business_access("business_id")
def delete_product_endpoint(
    request: Request,
    business_id: int,
    product_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    if not ctx.has_business_permission("inventory", "delete"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.delete", http_status=403)
    ok = delete_product(db, product_id, business_id)
    return success_response({"deleted": ok}, request)


@router.post("/business/{business_id}/export/excel",
    summary="خروجی Excel لیست محصولات",
    description="خروجی Excel لیست محصولات با قابلیت فیلتر، انتخاب ستون‌ها و ترتیب آن‌ها",
)
@require_business_access("business_id")
async def export_products_excel(
    request: Request,
    business_id: int,
    body: dict,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    import io
    import re
    import datetime
    from fastapi.responses import Response
    from openpyxl import Workbook
    from openpyxl.styles import Font, Alignment, PatternFill, Border, Side

    if not ctx.can_read_section("inventory"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.read", http_status=403)

    query_dict = {
        "take": int(body.get("take", 1000)),
        "skip": int(body.get("skip", 0)),
        "sort_by": body.get("sort_by"),
        "sort_desc": bool(body.get("sort_desc", False)),
        "search": body.get("search"),
        "search_fields": body.get("search_fields"),
        "filters": body.get("filters"),
    }
    result = list_products(db, business_id, query_dict)
    items = result.get("items", []) if isinstance(result, dict) else result.get("items", [])
    items = [format_datetime_fields(item, request) for item in items]

    # Apply selected indices filter if requested
    selected_only = bool(body.get('selected_only', False))
    selected_indices = body.get('selected_indices')
    if selected_only and selected_indices is not None and isinstance(items, list):
        indices = None
        if isinstance(selected_indices, str):
            try:
                import json as _json
                indices = _json.loads(selected_indices)
            except Exception:
                indices = None
        elif isinstance(selected_indices, list):
            indices = selected_indices
        if isinstance(indices, list):
            items = [items[i] for i in indices if isinstance(i, int) and 0 <= i < len(items)]

    export_columns = body.get("export_columns")
    if export_columns and isinstance(export_columns, list):
        headers = [col.get("label") or col.get("key") for col in export_columns]
        keys = [col.get("key") for col in export_columns]
    else:
        default_cols = [
            ("code", "کد"),
            ("name", "نام"),
            ("item_type", "نوع"),
            ("category_id", "دسته"),
            ("base_sales_price", "قیمت فروش"),
            ("base_purchase_price", "قیمت خرید"),
            ("main_unit_id", "واحد اصلی"),
            ("secondary_unit_id", "واحد فرعی"),
            ("track_inventory", "کنترل موجودی"),
            ("created_at_formatted", "ایجاد"),
        ]
        keys = [k for k, _ in default_cols]
        headers = [v for _, v in default_cols]

    wb = Workbook()
    ws = wb.active
    ws.title = "Products"

    # Locale and RTL/LTR handling for Excel
    locale = negotiate_locale(request.headers.get("Accept-Language"))
    if locale == 'fa':
        try:
            ws.sheet_view.rightToLeft = True
        except Exception:
            pass

    # Header style
    header_font = Font(bold=True)
    header_fill = PatternFill(start_color="DDDDDD", end_color="DDDDDD", fill_type="solid")
    thin_border = Border(left=Side(style='thin'), right=Side(style='thin'), top=Side(style='thin'), bottom=Side(style='thin'))

    ws.append(headers)
    for cell in ws[1]:
        cell.font = header_font
        cell.fill = header_fill
        cell.alignment = Alignment(horizontal="center")
        cell.border = thin_border

    for it in items:
        row = []
        for k in keys:
            row.append(it.get(k))
        ws.append(row)
        for cell in ws[ws.max_row]:
            cell.border = thin_border
            # Align data cells based on locale
            if locale == 'fa':
                cell.alignment = Alignment(horizontal="right")

    # Auto width columns
    try:
        for column in ws.columns:
            max_length = 0
            column_letter = column[0].column_letter
            for cell in column:
                try:
                    if cell.value is not None and len(str(cell.value)) > max_length:
                        max_length = len(str(cell.value))
                except Exception:
                    pass
            ws.column_dimensions[column_letter].width = min(max_length + 2, 50)
    except Exception:
        pass

    output = io.BytesIO()
    wb.save(output)
    data = output.getvalue()

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
    base = "products"
    if biz_name:
        base += f"_{slugify(biz_name)}"
    if selected_only:
        base += "_selected"
    filename = f"{base}_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.xlsx"

    return Response(
        content=data,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={
            "Content-Disposition": f"attachment; filename={filename}",
            "Content-Length": str(len(data)),
            "Access-Control-Expose-Headers": "Content-Disposition",
        },
    )


@router.post("/business/{business_id}/import/template",
    summary="دانلود تمپلیت ایمپورت محصولات",
    description="فایل Excel تمپلیت برای ایمپورت کالا/خدمت را برمی‌گرداند",
)
@require_business_access("business_id")
async def download_products_import_template(
    request: Request,
    business_id: int,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    import io
    import datetime
    from fastapi.responses import Response
    from openpyxl import Workbook
    from openpyxl.styles import Font, Alignment

    if not ctx.has_business_permission("inventory", "write"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.write", http_status=403)

    wb = Workbook()
    ws = wb.active
    ws.title = "Template"

    headers = [
        "code","name","item_type","description","category_id",
        "main_unit_id","secondary_unit_id","unit_conversion_factor",
        "base_sales_price","base_purchase_price","track_inventory",
        "reorder_point","min_order_qty","lead_time_days",
        "is_sales_taxable","is_purchase_taxable","sales_tax_rate","purchase_tax_rate",
        "tax_type_id","tax_code","tax_unit_id",
        # attribute_ids can be comma-separated ids
        "attribute_ids",
    ]
    for col, header in enumerate(headers, 1):
        cell = ws.cell(row=1, column=col, value=header)
        cell.font = Font(bold=True)
        cell.alignment = Alignment(horizontal="center")

    sample = [
        "P1001","نمونه کالا","کالا","توضیح اختیاری", "", 
        "", "", "", 
        "150000", "120000", "TRUE",
        "0", "0", "",
        "FALSE", "FALSE", "", "",
        "", "", "",
        "1,2,3",
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

    filename = f"products_import_template_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.xlsx"
    return Response(
        content=buf.getvalue(),
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={
            "Content-Disposition": f"attachment; filename={filename}",
            "Access-Control-Expose-Headers": "Content-Disposition",
        },
    )


@router.post("/business/{business_id}/import/excel",
    summary="ایمپورت محصولات از فایل Excel",
    description="فایل اکسل را دریافت می‌کند و به‌صورت dry-run یا واقعی پردازش می‌کند",
)
@require_business_access("business_id")
async def import_products_excel(
    request: Request,
    business_id: int,
    file: UploadFile = File(...),
    dry_run: str = Form(default="true"),
    match_by: str = Form(default="code"),
    conflict_policy: str = Form(default="upsert"),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    import io
    import json
    import logging
    import re
    import zipfile
    from decimal import Decimal
    from typing import Optional
    from openpyxl import load_workbook

    if not ctx.has_business_permission("inventory", "write"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.write", http_status=403)

    logger = logging.getLogger(__name__)

    def _validate_excel_signature(content: bytes) -> bool:
        try:
            if not content.startswith(b'PK'):
                return False
            with zipfile.ZipFile(io.BytesIO(content), 'r') as zf:
                return any(n.startswith('xl/') for n in zf.namelist())
        except Exception:
            return False

    try:
        is_dry_run = str(dry_run).lower() in ("true","1","yes","on")

        if not file.filename or not file.filename.lower().endswith('.xlsx'):
            raise ApiError("INVALID_FILE", "فرمت فایل معتبر نیست. تنها xlsx پشتیبانی می‌شود", http_status=400)

        content = await file.read()
        if len(content) < 100 or not _validate_excel_signature(content):
            raise ApiError("INVALID_FILE", "فایل Excel معتبر نیست یا خالی است", http_status=400)

        try:
            wb = load_workbook(filename=io.BytesIO(content), data_only=True)
        except zipfile.BadZipFile:
            raise ApiError("INVALID_FILE", "فایل Excel خراب است یا فرمت آن معتبر نیست", http_status=400)

        ws = wb.active
        rows = list(ws.iter_rows(values_only=True))
        if not rows:
            return success_response(data={"summary": {"total": 0}}, request=request, message="EMPTY_FILE")

        headers = [str(h).strip() if h is not None else "" for h in rows[0]]
        data_rows = rows[1:]

        def _parse_bool(v: object) -> Optional[bool]:
            if v is None: return None
            s = str(v).strip().lower()
            if s in ("true","1","yes","on","بله","هست"):
                return True
            if s in ("false","0","no","off","خیر","نیست"):
                return False
            return None

        def _parse_decimal(v: object) -> Optional[Decimal]:
            if v is None or str(v).strip() == "":
                return None
            try:
                return Decimal(str(v).replace(",",""))
            except Exception:
                return None

        def _parse_int(v: object) -> Optional[int]:
            if v is None or str(v).strip() == "":
                return None
            try:
                return int(str(v).split(".")[0])
            except Exception:
                return None

        def _normalize_item_type(v: object) -> Optional[str]:
            if v is None: return None
            s = str(v).strip()
            mapping = {"product": "کالا", "service": "خدمت"}
            low = s.lower()
            if low in mapping: return mapping[low]
            if s in ("کالا","خدمت"): return s
            return None

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

            # normalize & cast
            if 'item_type' in item:
                item['item_type'] = _normalize_item_type(item.get('item_type')) or 'کالا'
            for k in ['base_sales_price','base_purchase_price','sales_tax_rate','purchase_tax_rate','unit_conversion_factor']:
                if k in item:
                    item[k] = _parse_decimal(item.get(k))
            for k in ['reorder_point','min_order_qty','lead_time_days','category_id','main_unit_id','secondary_unit_id','tax_type_id','tax_unit_id']:
                if k in item:
                    item[k] = _parse_int(item.get(k))
            for k in ['track_inventory','is_sales_taxable','is_purchase_taxable']:
                if k in item:
                    item[k] = _parse_bool(item.get(k)) if item.get(k) is not None else None

            # attribute_ids: comma-separated
            if 'attribute_ids' in item and item['attribute_ids']:
                try:
                    parts = [p.strip() for p in str(item['attribute_ids']).split(',') if p and p.strip()]
                    item['attribute_ids'] = [int(p) for p in parts if p.isdigit()]
                except Exception:
                    item['attribute_ids'] = []

            # validations
            name = item.get('name')
            if not name or str(name).strip() == "":
                row_errors.append('name الزامی است')

            # if code is empty, it will be auto-generated in service
            code = item.get('code')
            if code is not None and str(code).strip() == "":
                item['code'] = None

            if row_errors:
                errors.append({"row": idx, "errors": row_errors})
                continue

            valid_items.append(item)

        inserted = 0
        updated = 0
        skipped = 0

        if not is_dry_run and valid_items:
            from sqlalchemy import and_ as _and
            from adapters.db.models.product import Product
            from adapters.api.v1.schema_models.product import ProductCreateRequest, ProductUpdateRequest
            from app.services.product_service import create_product, update_product

            def _find_existing(session: Session, data: dict) -> Optional[Product]:
                if match_by == 'code' and data.get('code'):
                    return session.query(Product).filter(_and(Product.business_id == business_id, Product.code == str(data['code']).strip())).first()
                if match_by == 'name' and data.get('name'):
                    return session.query(Product).filter(_and(Product.business_id == business_id, Product.name == str(data['name']).strip())).first()
                return None

            for data in valid_items:
                existing = _find_existing(db, data)
                if existing is None:
                    try:
                        create_product(db, business_id, ProductCreateRequest(**data))
                        inserted += 1
                    except Exception as e:
                        logger.error(f"Create product failed: {e}")
                        skipped += 1
                else:
                    if conflict_policy == 'insert':
                        skipped += 1
                    elif conflict_policy in ('update','upsert'):
                        try:
                            update_product(db, existing.id, business_id, ProductUpdateRequest(**data))
                            updated += 1
                        except Exception as e:
                            logger.error(f"Update product failed: {e}")
                            skipped += 1

        summary = {
            "total": len(data_rows),
            "valid": len(valid_items),
            "invalid": len(errors),
            "inserted": inserted,
            "updated": updated,
            "skipped": skipped,
            "dry_run": is_dry_run,
        }

        return success_response(
            data={"summary": summary, "errors": errors},
            request=request,
            message="PRODUCTS_IMPORT_RESULT",
        )
    except ApiError:
        raise
    except Exception as e:
        logger.error(f"Import error: {e}", exc_info=True)
        raise ApiError("IMPORT_ERROR", f"خطا در پردازش فایل: {e}", http_status=500)
@router.post("/business/{business_id}/export/pdf",
    summary="خروجی PDF لیست محصولات",
    description="خروجی PDF لیست محصولات با قابلیت فیلتر و انتخاب ستون‌ها",
)
@require_business_access("business_id")
async def export_products_pdf(
    request: Request,
    business_id: int,
    body: dict,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    import json
    import datetime
    import re
    from fastapi.responses import Response
    from weasyprint import HTML, CSS
    from weasyprint.text.fonts import FontConfiguration

    if not ctx.can_read_section("inventory"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.read", http_status=403)

    query_dict = {
        "take": int(body.get("take", 100)),
        "skip": int(body.get("skip", 0)),
        "sort_by": body.get("sort_by"),
        "sort_desc": bool(body.get("sort_desc", False)),
        "search": body.get("search"),
        "search_fields": body.get("search_fields"),
        "filters": body.get("filters"),
    }
    result = list_products(db, business_id, query_dict)
    items = result.get("items", [])
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

    export_columns = body.get("export_columns")
    if export_columns and isinstance(export_columns, list):
        headers = [col.get("label") or col.get("key") for col in export_columns]
        keys = [col.get("key") for col in export_columns]
    else:
        default_cols = [
            ("code", "کد"),
            ("name", "نام"),
            ("item_type", "نوع"),
            ("category_id", "دسته"),
            ("base_sales_price", "قیمت فروش"),
            ("base_purchase_price", "قیمت خرید"),
            ("main_unit_id", "واحد اصلی"),
            ("secondary_unit_id", "واحد فرعی"),
            ("track_inventory", "کنترل موجودی"),
            ("created_at_formatted", "ایجاد"),
        ]
        keys = [k for k, _ in default_cols]
        headers = [v for _, v in default_cols]

    # Locale and direction
    locale = negotiate_locale(request.headers.get("Accept-Language"))
    is_fa = (locale == 'fa')
    html_lang = 'fa' if is_fa else 'en'
    html_dir = 'rtl' if is_fa else 'ltr'

    # Load business info for header
    business_name = ""
    try:
        biz = db.query(Business).filter(Business.id == business_id).first()
        if biz is not None:
            business_name = biz.name or ""
    except Exception:
        business_name = ""

    # Escape helper
    def escape(s: Any) -> str:
        try:
            return str(s).replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
        except Exception:
            return str(s)

    # Build rows
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
        now_str = formatted_now.get('formatted', formatted_now.get('date_time', ''))
    except Exception:
        now_str = datetime.datetime.now().strftime('%Y/%m/%d %H:%M')

    title_text = "گزارش فهرست محصولات" if is_fa else "Products List Report"
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
          <div class=\"meta\">{label_date}: {escape(now_str)}</div>
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
    biz_name = business_name
    def slugify(text: str) -> str:
        return re.sub(r"[^A-Za-z0-9_-]+", "_", text).strip("_")
    base = "products"
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


@router.post("/business/{business_id}/bulk-price-update/preview",
    summary="پیش‌نمایش تغییر قیمت‌های گروهی",
    description="پیش‌نمایش تغییرات قیمت قبل از اعمال",
)
@require_business_access("business_id")
def preview_bulk_price_update_endpoint(
    request: Request,
    business_id: int,
    payload: BulkPriceUpdateRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    if not ctx.has_business_permission("inventory", "write"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.write", http_status=403)
    
    result = preview_bulk_price_update(db, business_id, payload)
    return success_response(data=result.dict(), request=request)


@router.post("/business/{business_id}/bulk-price-update/apply",
    summary="اعمال تغییر قیمت‌های گروهی",
    description="اعمال تغییرات قیمت بر روی کالاهای انتخاب شده",
)
@require_business_access("business_id")
def apply_bulk_price_update_endpoint(
    request: Request,
    business_id: int,
    payload: BulkPriceUpdateRequest,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    if not ctx.has_business_permission("inventory", "write"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.write", http_status=403)
    
    result = apply_bulk_price_update(db, business_id, payload)
    return success_response(data=result, request=request)


