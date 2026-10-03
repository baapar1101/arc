"""همگام‌سازی موجودی فیزیکی انبار با خطوط کالای سند افتتاحیه."""
from __future__ import annotations

from collections import defaultdict
from decimal import Decimal
from typing import Any, Dict, Iterable, List, Mapping, Tuple
from uuid import uuid4

from sqlalchemy import func
from sqlalchemy.orm import Session

from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.product import Product
from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
from app.core.responses import ApiError

InventoryKey = Tuple[int, int]


def _decimal(value: Any) -> Decimal:
    try:
        return Decimal(str(value or 0))
    except Exception:
        return Decimal(0)


def build_opening_balance_warehouse_deltas(
    desired: Mapping[InventoryKey, Decimal],
    linked_physical: Mapping[InventoryKey, Decimal],
) -> Dict[InventoryKey, Decimal]:
    """اختلاف موردنیاز را بدون وابستگی به دیتابیس محاسبه می‌کند."""
    result: Dict[InventoryKey, Decimal] = {}
    for key in set(desired) | set(linked_physical):
        delta = _decimal(desired.get(key)) - _decimal(linked_physical.get(key))
        if delta:
            result[key] = delta
    return result


def _desired_opening_inventory(
    db: Session,
    document_id: int,
    product_ids: List[int],
) -> tuple[Dict[InventoryKey, Decimal], Dict[InventoryKey, Decimal]]:
    desired: Dict[InventoryKey, Decimal] = defaultdict(Decimal)
    costs: Dict[InventoryKey, Decimal] = {}
    rows = db.query(DocumentLine).filter(
        DocumentLine.document_id == int(document_id),
        DocumentLine.product_id.in_(product_ids),
    ).all()
    for row in rows:
        info = dict(row.extra_info or {})
        if str(info.get("movement") or "in").strip().lower() != "in":
            continue
        warehouse_id = info.get("warehouse_id")
        quantity = _decimal(row.quantity)
        if warehouse_id is None or quantity <= 0:
            continue
        key = (int(row.product_id), int(warehouse_id))
        desired[key] += quantity
        costs[key] = _decimal(info.get("cost_price"))
    return dict(desired), costs


def _linked_opening_inventory(
    db: Session,
    business_id: int,
    document_id: int,
    product_ids: List[int],
) -> Dict[InventoryKey, Decimal]:
    linked: Dict[InventoryKey, Decimal] = defaultdict(Decimal)
    rows = (
        db.query(WarehouseDocumentLine)
        .join(
            WarehouseDocument,
            WarehouseDocument.id == WarehouseDocumentLine.warehouse_document_id,
        )
        .filter(
            WarehouseDocument.business_id == int(business_id),
            WarehouseDocument.status == "posted",
            func.lower(func.coalesce(WarehouseDocument.source_type, "")) == "opening_balance",
            WarehouseDocument.source_document_id == int(document_id),
            WarehouseDocumentLine.product_id.in_(product_ids),
        )
        .all()
    )
    for row in rows:
        if row.warehouse_id is None:
            continue
        key = (int(row.product_id), int(row.warehouse_id))
        quantity = _decimal(row.quantity)
        if str(row.movement or "").lower() == "in":
            linked[key] += quantity
        elif str(row.movement or "").lower() == "out":
            linked[key] -= quantity
    return dict(linked)


def _assert_products_can_sync(
    db: Session,
    business_id: int,
    product_ids: List[int],
) -> None:
    products = db.query(
        Product.id,
        Product.name,
        Product.track_inventory,
        Product.inventory_mode,
    ).filter(
        Product.business_id == int(business_id),
        Product.id.in_(product_ids),
    ).all()
    by_id = {int(row.id): row for row in products}
    for product_id in product_ids:
        product = by_id.get(int(product_id))
        if product is None:
            raise ApiError("PRODUCT_NOT_FOUND", f"کالا با شناسه {product_id} یافت نشد", http_status=404)
        if not bool(product.track_inventory):
            raise ApiError(
                "OPENING_BALANCE_REQUIRES_TRACK_INVENTORY",
                f"کنترل موجودی کالای «{product.name}» فعال نیست",
                http_status=400,
            )
        if str(product.inventory_mode or "bulk").strip().lower() == "unique":
            raise ApiError(
                "UNIQUE_OPENING_BALANCE_REQUIRES_INSTANCES",
                f"ثبت خودکار موجودی اولیه کالای یونیک «{product.name}» بدون اطلاعات سریال/نمونه مجاز نیست",
                http_status=400,
            )


def find_products_with_unrelated_posted_warehouse_history(
    db: Session,
    business_id: int,
    product_ids: List[int],
) -> set[int]:
    if not product_ids:
        return set()
    rows = (
        db.query(WarehouseDocumentLine.product_id)
        .join(
            WarehouseDocument,
            WarehouseDocument.id == WarehouseDocumentLine.warehouse_document_id,
        )
        .filter(
            WarehouseDocument.business_id == int(business_id),
            WarehouseDocument.status == "posted",
            func.lower(func.coalesce(WarehouseDocument.source_type, "")) != "opening_balance",
            WarehouseDocumentLine.product_id.in_(product_ids),
        )
        .distinct()
        .all()
    )
    return {int(row.product_id) for row in rows}


def _assert_no_unrelated_posted_history(
    db: Session,
    business_id: int,
    product_ids: List[int],
) -> None:
    conflicts = find_products_with_unrelated_posted_warehouse_history(
        db, business_id, product_ids
    )
    if conflicts:
        raise ApiError(
            "OPENING_BALANCE_WAREHOUSE_HISTORY_EXISTS",
            "برای یکی از کالاهای ایمپورت‌شده قبلاً گردش انبار ثبت شده است؛ "
            "تعداد افتتاحیه را تغییر ندهید و اختلاف را با رسید/حواله یا تعدیل انبار ثبت کنید",
            http_status=409,
            details={"product_ids": sorted(conflicts)},
        )


def _group_delta_lines(
    deltas: Mapping[InventoryKey, Decimal],
    costs: Mapping[InventoryKey, Decimal],
) -> tuple[Dict[int, List[Dict[str, Any]]], Dict[int, List[Dict[str, Any]]]]:
    receipts: Dict[int, List[Dict[str, Any]]] = defaultdict(list)
    issues: Dict[int, List[Dict[str, Any]]] = defaultdict(list)
    for (product_id, warehouse_id), delta in sorted(deltas.items()):
        if not delta:
            continue
        line = {
            "product_id": int(product_id),
            "quantity": abs(delta),
            "extra_info": {
                "opening_balance_sync": True,
                "cost_price": float(costs.get((product_id, warehouse_id), Decimal(0))),
            },
        }
        (receipts if delta > 0 else issues)[int(warehouse_id)].append(line)
    return dict(receipts), dict(issues)


def sync_opening_balance_warehouse_documents(
    db: Session,
    business_id: int,
    user_id: int,
    opening_balance_document_id: int,
    affected_product_ids: Iterable[int],
) -> Dict[str, Any]:
    """رسید/حواله اختلافی ایجاد و قطعی می‌کند؛ commit بر عهده caller است."""
    product_ids = sorted({int(product_id) for product_id in affected_product_ids})
    empty_summary: Dict[str, Any] = {
        "receipts_created": 0,
        "issues_created": 0,
        "lines_created": 0,
        "unchanged_lines": 0,
        "posted": True,
        "document_ids": [],
    }
    if not product_ids:
        return empty_summary

    opening_document = db.query(Document).filter(
        Document.id == int(opening_balance_document_id),
        Document.business_id == int(business_id),
        Document.document_type == "opening_balance",
    ).first()
    if opening_document is None:
        raise ApiError("OPENING_BALANCE_NOT_FOUND", "سند تراز افتتاحیه یافت نشد", http_status=404)

    _assert_products_can_sync(db, business_id, product_ids)
    _assert_no_unrelated_posted_history(db, business_id, product_ids)

    desired, costs = _desired_opening_inventory(db, int(opening_document.id), product_ids)
    linked = _linked_opening_inventory(db, business_id, int(opening_document.id), product_ids)
    deltas = build_opening_balance_warehouse_deltas(desired, linked)
    receipts, issues = _group_delta_lines(deltas, costs)

    unchanged = sum(1 for key in set(desired) | set(linked) if key not in deltas)
    summary = {**empty_summary, "unchanged_lines": unchanged}
    if not deltas:
        return summary

    from app.services.warehouse_service import (
        create_linked_warehouse_document_bulk,
        post_warehouse_document,
    )

    batch_id = str(uuid4())
    created_ids: List[int] = []
    common_extra = {
        "origin": "product_excel_import",
        "opening_balance_sync": True,
        "import_batch_id": batch_id,
        "opening_balance_document_id": int(opening_document.id),
    }

    # خروج اختلاف ابتدا ثبت می‌شود تا جابه‌جایی انبار با موجودی فیزیکی قبلی کنترل شود.
    for warehouse_id, lines in sorted(issues.items()):
        wh = create_linked_warehouse_document_bulk(
            db,
            business_id,
            user_id,
            doc_type="issue",
            document_date=opening_document.document_date,
            warehouse_id=warehouse_id,
            lines=lines,
            source_type="opening_balance",
            source_document_id=int(opening_document.id),
            extra_info={**common_extra, "description": "اصلاح خودکار موجودی افتتاحیه از ایمپورت اکسل"},
        )
        post_warehouse_document(db, int(wh.id))
        created_ids.append(int(wh.id))

    for warehouse_id, lines in sorted(receipts.items()):
        wh = create_linked_warehouse_document_bulk(
            db,
            business_id,
            user_id,
            doc_type="receipt",
            document_date=opening_document.document_date,
            warehouse_id=warehouse_id,
            lines=lines,
            source_type="opening_balance",
            source_document_id=int(opening_document.id),
            extra_info={**common_extra, "description": "رسید خودکار موجودی افتتاحیه از ایمپورت اکسل"},
        )
        post_warehouse_document(db, int(wh.id))
        created_ids.append(int(wh.id))

    summary.update({
        "receipts_created": len(receipts),
        "issues_created": len(issues),
        "lines_created": len(deltas),
        "document_ids": created_ids,
        "import_batch_id": batch_id,
    })
    return summary
