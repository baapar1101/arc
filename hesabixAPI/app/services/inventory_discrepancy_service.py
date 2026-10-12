from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
from typing import Any

from sqlalchemy.orm import Session, selectinload
from sqlalchemy.orm.attributes import flag_modified

from adapters.db.models.document import Document
from adapters.db.models.inventory_discrepancy import (
    InventoryDiscrepancyCase,
    InventoryDiscrepancyLine,
)
from adapters.db.models.invoice_item_line import InvoiceItemLine
from app.core.responses import ApiError


def _decimal(value: Any) -> Decimal:
    return Decimal(str(value or 0))


def _serialize(case: InventoryDiscrepancyCase) -> dict[str, Any]:
    return {
        "id": case.id,
        "business_id": case.business_id,
        "invoice_document_id": case.invoice_document_id,
        "warehouse_document_id": case.warehouse_document_id,
        "resolution_document_id": case.resolution_document_id,
        "status": case.status,
        "source_type": case.source_type,
        "reason_code": case.reason_code,
        "reason_note": case.reason_note,
        "created_by_user_id": case.created_by_user_id,
        "resolved_by_user_id": case.resolved_by_user_id,
        "resolution_type": case.resolution_type,
        "created_at": case.created_at.isoformat() if case.created_at else None,
        "resolved_at": case.resolved_at.isoformat() if case.resolved_at else None,
        "lines": [
            {
                "id": line.id,
                "product_id": line.product_id,
                "warehouse_id": line.warehouse_id,
                "invoice_item_line_id": line.invoice_item_line_id,
                "available_quantity": float(line.available_quantity or 0),
                "requested_quantity": float(line.requested_quantity or 0),
                "shortage_quantity": float(line.shortage_quantity or 0),
                "resolved_quantity": float(line.resolved_quantity or 0),
                "resolution_unit_cost": (
                    float(line.resolution_unit_cost) if line.resolution_unit_cost is not None else None
                ),
            }
            for line in case.lines
        ],
    }


def create_case_for_invoice(
    db: Session,
    *,
    business_id: int,
    document: Document,
    user_id: int,
    warehouse_document_ids: list[int],
) -> InventoryDiscrepancyCase | None:
    override = (document.extra_info or {}).get("_stock_override")
    if not isinstance(override, dict) or override.get("authorized") is not True:
        return None
    shortages = override.get("shortages")
    if not isinstance(shortages, list) or not shortages:
        return None
    token = str(override.get("request_token") or "").strip()
    existing = db.query(InventoryDiscrepancyCase).filter(
        InventoryDiscrepancyCase.business_id == int(business_id),
        InventoryDiscrepancyCase.request_token == token,
    ).first()
    if existing:
        return existing

    wh_id = int(warehouse_document_ids[0]) if warehouse_document_ids else None
    case = InventoryDiscrepancyCase(
        business_id=int(business_id),
        invoice_document_id=int(document.id),
        warehouse_document_id=wh_id,
        status="open",
        source_type="quick_sale",
        request_token=token,
        reason_code=str(override.get("reason_code") or "other"),
        reason_note=override.get("reason_note"),
        created_by_user_id=int(user_id),
    )
    db.add(case)
    db.flush()

    invoice_lines = db.query(InvoiceItemLine).filter(
        InvoiceItemLine.document_id == int(document.id)
    ).all()
    for shortage in shortages:
        pid = int(shortage["product_id"])
        warehouse_id = shortage.get("warehouse_id")
        if warehouse_id is None:
            continue
        invoice_line = next((x for x in invoice_lines if int(x.product_id) == pid), None)
        db.add(
            InventoryDiscrepancyLine(
                case_id=case.id,
                product_id=pid,
                warehouse_id=int(warehouse_id),
                invoice_item_line_id=int(invoice_line.id) if invoice_line else None,
                available_quantity=_decimal(shortage.get("available_quantity")),
                requested_quantity=_decimal(shortage.get("requested_quantity")),
                shortage_quantity=_decimal(shortage.get("shortage_quantity")),
                resolved_quantity=Decimal("0"),
            )
        )
    db.flush()
    extra = dict(document.extra_info or {})
    override = dict(override)
    override["discrepancy_case_id"] = case.id
    extra["_stock_override"] = override
    document.extra_info = extra
    flag_modified(document, "extra_info")
    db.flush()
    return case


def list_cases(db: Session, business_id: int, status: str | None = None) -> dict[str, Any]:
    q = db.query(InventoryDiscrepancyCase).options(
        selectinload(InventoryDiscrepancyCase.lines)
    ).filter(InventoryDiscrepancyCase.business_id == int(business_id))
    if status:
        q = q.filter(InventoryDiscrepancyCase.status == str(status))
    rows = q.order_by(InventoryDiscrepancyCase.created_at.desc()).limit(200).all()
    return {"items": [_serialize(row) for row in rows], "total": len(rows)}


def get_case(db: Session, business_id: int, case_id: int) -> InventoryDiscrepancyCase:
    row = db.query(InventoryDiscrepancyCase).options(
        selectinload(InventoryDiscrepancyCase.lines)
    ).filter(
        InventoryDiscrepancyCase.id == int(case_id),
        InventoryDiscrepancyCase.business_id == int(business_id),
    ).first()
    if not row:
        raise ApiError("INVENTORY_DISCREPANCY_NOT_FOUND", "پرونده مغایرت یافت نشد", http_status=404)
    return row


def create_goods_income_correction(
    db: Session,
    *,
    business_id: int,
    user_id: int,
    document_date: date,
    lines: list[dict[str, Any]],
    description: str,
    user_can_allocate: bool,
    user_can_post: bool,
    user_can_change_unit_cost: bool,
    case_id: int | None = None,
) -> dict[str, Any]:
    """کسری ناشی از موجودی فیزیکی ثبت‌نشده را با تاریخ واقعی کشف اصلاح می‌کند."""
    if not user_can_post:
        raise ApiError(
            "GOODS_INCOME_POST_PERMISSION_REQUIRED",
            "برای اصلاح فوری موجودی، مجوز قطعی‌کردن کالای درآمدشده لازم است",
            http_status=403,
        )
    from app.services.goods_expense_income_service import create_document, post_document

    payload = {
        "doc_kind": "goods_income",
        "document_date": document_date.isoformat(),
        "description": description,
        "auto_post": True,
        "extra_info": {
            "source": "quick_sales_stock_correction",
            "inventory_discrepancy_case_id": case_id,
        },
        "lines": lines,
    }
    result = create_document(
        db,
        business_id,
        user_id,
        payload,
        user_can_allocate=user_can_allocate,
        user_can_post=user_can_post,
        user_can_change_unit_cost=user_can_change_unit_cost,
        commit=False,
    )
    if result.get("status") != "posted":
        result = post_document(db, business_id, user_id, int(result["id"]), commit=False)
    return result


def resolve_case_with_goods_income(
    db: Session,
    *,
    business_id: int,
    case_id: int,
    user_id: int,
    lines: list[dict[str, Any]],
    document_date: date,
    user_can_allocate: bool,
    user_can_post: bool,
    user_can_change_unit_cost: bool,
) -> dict[str, Any]:
    case = get_case(db, business_id, case_id)
    if case.status != "open":
        raise ApiError("INVENTORY_DISCREPANCY_ALREADY_RESOLVED", "این پرونده قبلاً رسیدگی شده است", http_status=409)
    by_line_id = {int(x.get("case_line_id")): x for x in lines if x.get("case_line_id")}
    correction_lines: list[dict[str, Any]] = []
    for case_line in case.lines:
        requested = by_line_id.get(int(case_line.id), {})
        remaining = _decimal(case_line.shortage_quantity) - _decimal(case_line.resolved_quantity)
        qty = _decimal(requested.get("quantity", remaining))
        if qty <= 0 or qty != remaining:
            raise ApiError(
                "INVALID_RESOLUTION_QUANTITY",
                "برای بستن پرونده باید تمام مقدار باقیمانده اصلاح شود",
                http_status=400,
            )
        correction_lines.append(
            {
                "product_id": case_line.product_id,
                "warehouse_id": case_line.warehouse_id,
                "quantity": float(qty),
                **({"unit_cost": requested["unit_cost"]} if requested.get("unit_cost") is not None else {}),
                "description": f"رفع مغایرت فروش سریع، پرونده {case.id}",
                "extra_info": {"inventory_discrepancy_line_id": case_line.id},
            }
        )
    correction = create_goods_income_correction(
        db,
        business_id=business_id,
        user_id=user_id,
        document_date=document_date,
        lines=correction_lines,
        description=f"اصلاح موجودی واقعی بابت پرونده مغایرت فروش سریع {case.id}",
        user_can_allocate=user_can_allocate,
        user_can_post=user_can_post,
        user_can_change_unit_cost=user_can_change_unit_cost,
        case_id=case.id,
    )
    actual_lines = correction.get("lines") or []
    actual_by_product = {int(x["product_id"]): x for x in actual_lines}
    for case_line in case.lines:
        actual = actual_by_product.get(int(case_line.product_id), {})
        qty = _decimal(actual.get("quantity", case_line.shortage_quantity))
        unit_cost = _decimal(actual.get("unit_cost"))
        case_line.resolved_quantity = _decimal(case_line.resolved_quantity) + qty
        case_line.resolution_unit_cost = unit_cost
        if case_line.invoice_item_line_id:
            sale_line = db.query(InvoiceItemLine).filter(
                InvoiceItemLine.id == int(case_line.invoice_item_line_id)
            ).first()
            if sale_line:
                extra = dict(sale_line.extra_info or {})
                allocations = list(extra.get("stock_shortage_resolutions") or [])
                allocations.append(
                    {
                        "case_line_id": case_line.id,
                        "quantity": float(qty),
                        "unit_cost": float(unit_cost),
                        "resolution_document_id": correction["id"],
                        "resolved_at": datetime.utcnow().isoformat(),
                    }
                )
                extra["stock_shortage_resolutions"] = allocations
                sale_line.extra_info = extra
                flag_modified(sale_line, "extra_info")
                sale_qty = _decimal(sale_line.quantity)
                if sale_qty > 0:
                    previous_unit = _decimal(sale_line.ledger_unit_cogs)
                    # اگر موجودی پیش از این فروش منفی بوده، مقدار اصلاح می‌تواند از
                    # تعداد همین فاکتور بیشتر باشد؛ فقط سهم همین ردیف به COGS آن تخصیص می‌یابد.
                    allocated_qty = min(_decimal(case_line.shortage_quantity), sale_qty)
                    normal_qty = sale_qty - allocated_qty
                    new_total = normal_qty * previous_unit + allocated_qty * unit_cost
                    sale_line.ledger_unit_cogs = new_total / sale_qty
                    sale_line.ledger_line_cogs = new_total
                    sale_amount = _decimal(extra.get("line_total"))
                    sale_line.ledger_line_gross_profit = sale_amount - new_total
                    sale_line.ledger_recognized_at = datetime.utcnow()
                    sale_line.ledger_recognition_event = "inventory_discrepancy_resolution"
    case.status = "resolved"
    case.resolution_document_id = int(correction["id"])
    case.resolution_type = "goods_income_unexplained_surplus"
    case.resolved_by_user_id = int(user_id)
    case.resolved_at = datetime.utcnow()
    db.flush()
    db.commit()
    return {"case": _serialize(get_case(db, business_id, case.id)), "correction_document": correction}
