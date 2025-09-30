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
)
from app.services.product_service import (
    create_product,
    list_products,
    get_product,
    update_product,
    delete_product,
)


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

    output = io.BytesIO()
    wb.save(output)
    data = output.getvalue()

    return Response(
        content=data,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={
            "Content-Disposition": "attachment; filename=products.xlsx",
            "Content-Length": str(len(data)),
        },
    )


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
    import io
    import datetime
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

    # Build simple HTML table
    head_html = """
    <style>
      table { width: 100%; border-collapse: collapse; }
      th, td { border: 1px solid #777; padding: 6px; font-size: 12px; }
      th { background: #eee; }
      h1 { font-size: 16px; }
      .meta { font-size: 12px; color: #666; margin-bottom: 10px; }
    </style>
    """
    title = "گزارش فهرست محصولات"
    now = datetime.datetime.utcnow().isoformat()
    header_row = "".join([f"<th>{h}</th>" for h in headers])
    body_rows = "".join([
        "<tr>" + "".join([f"<td>{(it.get(k) if it.get(k) is not None else '')}</td>" for k in keys]) + "</tr>"
        for it in items
    ])
    html = f"""
      <html><head>{head_html}</head><body>
        <h1>{title}</h1>
        <div class=meta>زمان تولید: {now}</div>
        <table>
          <thead><tr>{header_row}</tr></thead>
          <tbody>{body_rows}</tbody>
        </table>
      </body></html>
    """

    font_config = FontConfiguration()
    pdf_bytes = HTML(string=html).write_pdf(stylesheets=[CSS(string="@page { size: A4 landscape; margin: 10mm; }")], font_config=font_config)

    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={
            "Content-Disposition": "attachment; filename=products.pdf",
            "Content-Length": str(len(pdf_bytes)),
        },
    )


