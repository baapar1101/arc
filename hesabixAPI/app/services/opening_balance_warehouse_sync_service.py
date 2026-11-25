"""همگام‌سازی موجودی فیزیکی انبار با خطوط کالای سند افتتاحیه."""
from __future__ import annotations

from collections import defaultdict
from decimal import Decimal
from typing import Any, Dict, Iterable, List, Mapping, Optional
from uuid import uuid4

from sqlalchemy import func
from sqlalchemy.orm import Session

from adapters.db.models.document import Document
from adapters.db.models.document_line import DocumentLine
from adapters.db.models.product import Product
from adapters.db.models.product_variant_allocation import WarehouseLineVariantAllocation
from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
from app.core.responses import ApiError
from app.services.invoice_unit_conversion_service import (
    inventory_price_to_main,
    inventory_quantity_to_main,
)
from app.services.product_variant_service import is_variant_inventory_product
from app.services.variant_allocation_service import (
    opening_allocations_in_main_units,
    validate_payload_for_product,
)

InventoryKey = tuple[int, int] | tuple[int, int, int]


def _record_cost(costs: dict, key: InventoryKey, cost: Decimal) -> None:
    if len(key) == 3 and key in costs and costs[key] != cost:
        raise ApiError("OPENING_VARIANT_COST_AMBIGUOUS", "بهای ثبت‌شدهٔ این ترکیب یکتا نیست؛ همگام‌سازی خودکار مجاز نیست", http_status=409)
    costs[key] = cost


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
    business_id: int,
    document_id: int,
    product_ids: List[int],
) -> tuple[Dict[InventoryKey, Decimal], Dict[InventoryKey, Decimal], Dict[InventoryKey, Dict[str, Any]]]:
    desired: Dict[InventoryKey, Decimal] = defaultdict(Decimal)
    costs: Dict[InventoryKey, Decimal] = {}
    lots: Dict[InventoryKey, Dict[str, Any]] = {}
    rows = db.query(DocumentLine).filter(
        DocumentLine.document_id == int(document_id),
        DocumentLine.product_id.in_(product_ids),
    ).all()
    products_by_id: Dict[int, Any] = {}
    if product_ids:
        products_by_id = {
            int(product.id): product
            for product in db.query(Product).filter(Product.id.in_(product_ids), Product.business_id == business_id).all()
        }
    for row in rows:
        info = dict(row.extra_info or {})
        if str(info.get("movement") or "in").strip().lower() != "in":
            continue
        warehouse_id = info.get("warehouse_id")
        quantity = inventory_quantity_to_main(
            row.quantity,
            products_by_id.get(int(row.product_id)),
            info,
            strict=False,
        )
        if warehouse_id is None or quantity <= 0:
            continue
        product = products_by_id[int(row.product_id)]
        native = is_variant_inventory_product(product)
        if native:
            quantities = [((int(row.product_id), int(warehouse_id), vid), qty)
                          for vid, qty, _price in opening_allocations_in_main_units(
                              db, business_id, product, row.quantity, info, require_active=True)]
            cost = inventory_price_to_main(info.get("cost_price"), product, info, strict=True)
        else:
            quantities = [((int(row.product_id), int(warehouse_id)), quantity)]
            cost = _decimal(info.get("cost_price"))
        for key, qty in quantities:
            desired[key] += qty
            _record_cost(costs, key, cost)
        lot_payload: Dict[str, Any] = {}
        if info.get("lot_allocations"):
            lot_payload["lot_allocations"] = info.get("lot_allocations")
        elif info.get("lot_code") or info.get("manufacturing_date") or info.get("expiry_date"):
            lot_payload = {
                "lot_code": info.get("lot_code"),
                "manufacturing_date": info.get("manufacturing_date"),
                "expiry_date": info.get("expiry_date"),
                "lot_allocations": [
                    {
                        "lot_code": info.get("lot_code"),
                        "manufacturing_date": info.get("manufacturing_date"),
                        "expiry_date": info.get("expiry_date"),
                        "quantity": float(quantity),
                    }
                ],
            }
        if lot_payload:
            for key, _qty in quantities:
                lots[key] = lot_payload
    return dict(desired), costs, lots


def _linked_opening_inventory(
    db: Session,
    business_id: int,
    document_id: int,
    product_ids: List[int],
) -> tuple[dict[InventoryKey, Decimal], dict[InventoryKey, Decimal]]:
    linked: Dict[InventoryKey, Decimal] = defaultdict(Decimal)
    costs: Dict[InventoryKey, Decimal] = {}
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
    products_by_id: Dict[int, Any] = {}
    if product_ids:
        products_by_id = {
            int(product.id): product
            for product in db.query(Product).filter(Product.id.in_(product_ids), Product.business_id == business_id).all()
        }
    allocations_by_line = defaultdict(list)
    if rows:
        for allocation in db.query(WarehouseLineVariantAllocation).filter(
            WarehouseLineVariantAllocation.warehouse_document_line_id.in_([row.id for row in rows])
        ):
            allocations_by_line[allocation.warehouse_document_line_id].append(allocation)
    for row in rows:
        if row.warehouse_id is None:
            continue
        quantity = inventory_quantity_to_main(
            row.quantity,
            products_by_id.get(int(row.product_id)),
            getattr(row, "extra_info", None),
            strict=False,
        )
        product = products_by_id[int(row.product_id)]
        if is_variant_inventory_product(product):
            allocations = allocations_by_line[row.id]
            if any(a.business_id != business_id or a.product_id != row.product_id for a in allocations):
                raise ApiError("OPENING_VARIANT_LINK_INVALID", "انتساب تخصیص حوالهٔ افتتاحیه نامعتبر است", http_status=409)
            items = validate_payload_for_product(db, business_id, product, {"allocations": [
                {"variant_id": a.variant_id, "quantity": a.quantity} for a in allocations
            ]}, quantity, require_active=False)
            quantities = [((int(row.product_id), int(row.warehouse_id), vid), qty) for vid, qty, _price in items]
            if "cost_price" not in (row.extra_info or {}):
                raise ApiError("OPENING_VARIANT_COST_AMBIGUOUS", "بهای حوالهٔ افتتاحیه مشخص نیست", http_status=409)
            cost = inventory_price_to_main(row.extra_info["cost_price"], product, row.extra_info, strict=True)
            for key, _qty in quantities:
                _record_cost(costs, key, cost)
        else:
            quantities = [((int(row.product_id), int(row.warehouse_id)), quantity)]
        for key, qty in quantities:
            if str(row.movement or "").lower() == "in":
                linked[key] += qty
            elif str(row.movement or "").lower() == "out":
                linked[key] -= qty
    return dict(linked), costs


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
    lots: Optional[Mapping[InventoryKey, Dict[str, Any]]] = None,
) -> tuple[Dict[int, List[Dict[str, Any]]], Dict[int, List[Dict[str, Any]]]]:
    receipts: Dict[int, List[Dict[str, Any]]] = defaultdict(list)
    issues: Dict[int, List[Dict[str, Any]]] = defaultdict(list)
    lot_map = lots or {}
    for key, delta in sorted(deltas.items()):
        product_id, warehouse_id = key[:2]
        if not delta:
            continue
        extra: Dict[str, Any] = {
            "opening_balance_sync": True,
            "cost_price": float(costs.get(key, Decimal(0))),
        }
        if delta > 0:
            lot_extra = dict(lot_map.get(key) or {})
            allocs = [
                dict(item)
                for item in (lot_extra.get("lot_allocations") or [])
                if isinstance(item, dict)
            ]
            if allocs:
                first = allocs[0]
                first["quantity"] = float(delta)
                lot_extra["lot_allocations"] = [first]
            extra.update(lot_extra)
        line = {
            "product_id": int(product_id),
            "quantity": abs(delta),
            "extra_info": extra,
            "lot_allocations": extra.get("lot_allocations"),
        }
        if len(key) == 3:
            extra["unit"] = "main"
            extra["allocations"] = [{"variant_id": key[2], "quantity": str(abs(delta))}]
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
    ).with_for_update().first()
    if opening_document is None:
        raise ApiError("OPENING_BALANCE_NOT_FOUND", "سند تراز افتتاحیه یافت نشد", http_status=404)

    _assert_products_can_sync(db, business_id, product_ids)
    _assert_no_unrelated_posted_history(db, business_id, product_ids)

    desired, costs, lots = _desired_opening_inventory(db, business_id, int(opening_document.id), product_ids)
    linked, linked_costs = _linked_opening_inventory(db, business_id, int(opening_document.id), product_ids)
    for key, cost in linked_costs.items():
        _record_cost(costs, key, cost)
    deltas = build_opening_balance_warehouse_deltas(desired, linked)
    receipts, issues = _group_delta_lines(deltas, costs, lots)

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
