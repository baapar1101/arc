from __future__ import annotations

from typing import Any, Dict
from fastapi import APIRouter, Depends, Request, Body
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access
from app.core.responses import success_response, ApiError, format_datetime_fields
from adapters.api.v1.schemas import QueryInfo
from adapters.db.models.document import Document
from sqlalchemy import and_

from app.services.inventory_transfer_service import create_inventory_transfer, DOCUMENT_TYPE_INVENTORY_TRANSFER


router = APIRouter(prefix="/inventory-transfers", tags=["inventory_transfers"])


@router.post("/business/{business_id}")
@require_business_access("business_id")
def create_inventory_transfer_endpoint(
    request: Request,
    business_id: int,
    payload: Dict[str, Any] = Body(...),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    if not ctx.has_business_permission("inventory", "write"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.write", http_status=403)
    result = create_inventory_transfer(db, business_id, ctx.user_id, payload)
    return success_response(data=format_datetime_fields(result["data"], request), request=request, message=result.get("message"))


@router.post("/business/{business_id}/query")
@require_business_access("business_id")
def query_inventory_transfers_endpoint(
    request: Request,
    business_id: int,
    payload: QueryInfo,
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    if not ctx.can_read_section("inventory"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.read", http_status=403)
    take = max(1, payload.take)
    skip = max(0, payload.skip)
    q = db.query(Document).filter(
        and_(
            Document.business_id == business_id,
            Document.document_type == DOCUMENT_TYPE_INVENTORY_TRANSFER,
        )
    )
    total = q.count()
    rows = q.order_by(Document.document_date.desc(), Document.id.desc()).offset(skip).limit(take).all()
    items = [{
        "id": d.id,
        "code": d.code,
        "document_date": d.document_date,
        "currency_id": d.currency_id,
        "description": d.description,
    } for d in rows]
    return success_response(data={
        "items": format_datetime_fields(items, request),
        "pagination": {
            "total": total,
            "page": (skip // take) + 1,
            "per_page": take,
            "total_pages": (total + take - 1) // take,
            "has_next": skip + take < total,
            "has_prev": skip > 0,
        },
        "query_info": payload.model_dump(),
    }, request=request)


@router.post("/business/{business_id}/export/excel",
    summary="خروجی Excel لیست انتقال موجودی",
    description="خروجی اکسل از لیست اسناد انتقال موجودی بین انبارها",
)
@require_business_access("business_id")
def export_inventory_transfers_excel(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(default={}),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if not ctx.can_read_section("inventory"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.read", http_status=403)

    from fastapi.responses import Response
    from openpyxl import Workbook
    from io import BytesIO
    import datetime

    take = min(int(body.get("take", 1000)), 10000)
    skip = int(body.get("skip", 0))
    q = db.query(Document).filter(and_(Document.business_id == business_id, Document.document_type == DOCUMENT_TYPE_INVENTORY_TRANSFER))
    rows = q.order_by(Document.document_date.desc(), Document.id.desc()).offset(skip).limit(take).all()

    wb = Workbook()
    ws = wb.active
    ws.title = "InventoryTransfers"
    ws.append(["code", "document_date", "description"]) 
    for d in rows:
        ws.append([d.code, d.document_date.isoformat(), d.description])

    buf = BytesIO()
    wb.save(buf)
    content = buf.getvalue()
    filename = f"inventory_transfers_{business_id}_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.xlsx"

    return Response(
        content=content,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={
            "Content-Disposition": f"attachment; filename={filename}",
            "Content-Length": str(len(content)),
            "Access-Control-Expose-Headers": "Content-Disposition",
        },
    )


@router.post("/business/{business_id}/export/pdf",
    summary="خروجی PDF لیست انتقال موجودی",
    description="خروجی PDF از لیست اسناد انتقال موجودی بین انبارها",
)
@require_business_access("business_id")
def export_inventory_transfers_pdf(
    request: Request,
    business_id: int,
    body: Dict[str, Any] = Body(default={}),
    ctx: AuthContext = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if not ctx.can_read_section("inventory"):
        raise ApiError("FORBIDDEN", "Missing business permission: inventory.read", http_status=403)

    from fastapi.responses import Response
    from weasyprint import HTML, CSS
    from weasyprint.text.fonts import FontConfiguration
    from html import escape
    import datetime

    take = min(int(body.get("take", 1000)), 10000)
    skip = int(body.get("skip", 0))
    q = db.query(Document).filter(and_(Document.business_id == business_id, Document.document_type == DOCUMENT_TYPE_INVENTORY_TRANSFER))
    rows = q.order_by(Document.document_date.desc(), Document.id.desc()).offset(skip).limit(take).all()

    def cell(v: Any) -> str:
        return escape(v.isoformat()) if hasattr(v, 'isoformat') else escape(str(v) if v is not None else "")

    rows_html = "".join([
        f"<tr>"
        f"<td>{cell(d.code)}</td>"
        f"<td>{cell(d.document_date)}</td>"
        f"<td>{cell(d.description)}</td>"
        f"</tr>" for d in rows
    ])

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
        <h3>لیست انتقال موجودی بین انبارها</h3>
        <table>
          <thead>
            <tr>
              <th>کد سند</th>
              <th>تاریخ سند</th>
              <th>شرح</th>
            </tr>
          </thead>
          <tbody>
            {rows_html}
          </tbody>
        </table>
      </body>
    </html>
    """

    font_config = FontConfiguration()
    pdf_bytes = HTML(string=html).write_pdf(stylesheets=[CSS(string="@page { size: A4 portrait; margin: 12mm; }")], font_config=font_config)
    filename = f"inventory_transfers_{business_id}_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}.pdf"
    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f"attachment; filename={filename}",
            "Content-Length": str(len(pdf_bytes)),
            "Access-Control-Expose-Headers": "Content-Disposition",
        },
    )


