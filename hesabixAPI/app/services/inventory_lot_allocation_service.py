"""اعتبارسنجی و ذخیره تخصیص لات روی فاکتور و حواله."""

from __future__ import annotations

from datetime import date
from decimal import Decimal
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple

from sqlalchemy.orm import Session

from adapters.db.models.document import Document
from adapters.db.models.inventory_lot import (
    InventoryLot,
    InvoiceItemLineLotAllocation,
    WarehouseLineLotAllocation,
)
from adapters.db.models.invoice_item_line import InvoiceItemLine
from adapters.db.models.product import Product
from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
from app.core.responses import ApiError
from app.services.inventory_lot_service import (
    EXPIRED_SALE_CONFIRM,
    compute_available_lot_stock,
    find_or_create_lot,
    is_expiry_tracked_product,
    is_lot_sellable,
    suggest_fefo,
)
from app.services.invoice_unit_conversion_service import extra_info_dict, quantity_line_to_main

ZERO = Decimal("0")


def _d(value: Any) -> Decimal:
    return Decimal(str(value if value is not None else 0))


def parse_payload_lot_allocations(payload: Dict[str, Any] | None) -> List[Dict[str, Any]]:
    data = payload if isinstance(payload, dict) else {}
    extra = extra_info_dict(data.get("extra_info"))
    raw = data.get("lot_allocations")
    if raw is None:
        raw = extra.get("lot_allocations")
    if not raw:
        code = data.get("lot_code") or extra.get("lot_code")
        mfg = data.get("manufacturing_date") or extra.get("manufacturing_date")
        exp = data.get("expiry_date") or extra.get("expiry_date")
        if code or mfg or exp:
            qty = data.get("quantity")
            if qty is None:
                qty = extra.get("quantity")
            return [{
                "lot_code": code,
                "manufacturing_date": mfg,
                "expiry_date": exp,
                "quantity": qty,
            }]
        return []
    if not isinstance(raw, list):
        raise ApiError("INVALID_LOT_ALLOCATION", "ساختار تخصیص لات نامعتبر است", http_status=422)
    return [item for item in raw if isinstance(item, dict)]


def _variant_quantity_slices(
    payload: Dict[str, Any],
    extra: Dict[str, Any],
    fallback_qty: Decimal,
) -> List[Tuple[Optional[int], Decimal]]:
    allocs = extra.get("allocations") or payload.get("allocations")
    slices: List[Tuple[Optional[int], Decimal]] = []
    if isinstance(allocs, list):
        for row in allocs:
            if not isinstance(row, dict):
                continue
            qty = _d(row.get("quantity"))
            if qty <= 0:
                continue
            raw = row.get("variant_id")
            try:
                vid = int(raw) if raw is not None else None
            except (TypeError, ValueError):
                vid = None
            slices.append((vid, qty))
    if len(slices) >= 1:
        return slices
    return [(_parse_variant_id(payload), _d(fallback_qty))]


def _parse_variant_id(payload: Dict[str, Any]) -> int | None:
    extra = extra_info_dict(payload.get("extra_info"))
    raw = payload.get("variant_id")
    if raw is None:
        raw = extra.get("variant_id")
    allocs = extra.get("allocations") or payload.get("allocations")
    if raw is None and isinstance(allocs, list) and len(allocs) == 1:
        raw = allocs[0].get("variant_id") if isinstance(allocs[0], dict) else None
    if raw is None:
        return None
    try:
        return int(raw)
    except (TypeError, ValueError):
        return None


def scale_allocations_to_qty(
    allocated: Sequence[Tuple[int, Decimal]],
    remaining: Decimal,
) -> List[Tuple[int, Decimal]]:
    """برای حواله جزئی، همان لات‌های فاکتور را تا مقدار باقی‌مانده نگه می‌دارد."""
    left = _d(remaining)
    if left <= ZERO:
        return []
    out: List[Tuple[int, Decimal]] = []
    for lot_id, qty in allocated:
        qty = _d(qty)
        if qty <= ZERO:
            continue
        take = qty if qty <= left else left
        out.append((int(lot_id), take))
        left -= take
        if left <= ZERO:
            break
    return out


def validate_allocation_sum(line_quantity: Decimal, allocated: Sequence[Tuple[Any, Decimal]]) -> None:
    total = sum((qty for _, qty in allocated), ZERO)
    if total != _d(line_quantity):
        raise ApiError(
            "LOT_ALLOCATION_MISMATCH",
            "جمع تخصیص لات‌ها با مقدار ردیف برابر نیست",
            http_status=422,
            details={"line_quantity": str(_d(line_quantity)), "allocated": str(total)},
        )


def _resolve_lot_from_item(
    db: Session,
    business_id: int,
    product: Product,
    item: Dict[str, Any],
    *,
    variant_id: int | None,
    inbound: bool,
    allow_undated: bool,
) -> InventoryLot:
    lot_id = item.get("lot_id")
    if lot_id is not None:
        try:
            lid = int(lot_id)
        except (TypeError, ValueError) as exc:
            raise ApiError("INVALID_LOT_ALLOCATION", "شناسه لات نامعتبر است", http_status=422) from exc
        lot = (
            db.query(InventoryLot)
            .filter(
                InventoryLot.id == lid,
                InventoryLot.business_id == int(business_id),
                InventoryLot.product_id == int(product.id),
            )
            .first()
        )
        if lot is None:
            raise ApiError("LOT_NOT_FOUND", "لات انتخاب‌شده یافت نشد", http_status=422)
        return lot
    from app.services.inventory_lot_service import _as_date

    return find_or_create_lot(
        db,
        business_id,
        product,
        lot_code=item.get("lot_code"),
        variant_id=variant_id,
        manufacturing_date=_as_date(item.get("manufacturing_date")),
        expiry_date=_as_date(item.get("expiry_date")),
        best_before_date=_as_date(item.get("best_before_date")),
        removal_date=_as_date(item.get("removal_date")),
        alert_date=_as_date(item.get("alert_date")),
        is_undated=bool(item.get("is_undated")) and allow_undated,
        allow_missing_dates=not inbound and bool(item.get("lot_id")),
    )


def pick_return_lots(
    sold_newest_first: Sequence[Tuple[int, Decimal]],
    already_returned: Dict[int, Decimal],
    need: Decimal,
) -> List[Tuple[int, Decimal]]:
    """آخرین لات‌های فروخته‌شده را تا سقف مقدار برگشت برمی‌گرداند (LIFO فروش)."""
    remaining = {int(lot_id): _d(qty) for lot_id, qty in already_returned.items()}
    available: Dict[int, Decimal] = {}
    order: List[int] = []
    for lot_id, qty in sold_newest_first:
        lid = int(lot_id)
        available[lid] = available.get(lid, ZERO) + _d(qty)
        if lid not in order:
            order.append(lid)
    for lid, qty in remaining.items():
        available[lid] = available.get(lid, ZERO) - _d(qty)
    picked: List[Tuple[int, Decimal]] = []
    need_left = _d(need)
    for lid in order:
        avail = available.get(lid, ZERO)
        if avail <= ZERO or need_left <= ZERO:
            continue
        take = avail if avail <= need_left else need_left
        picked.append((lid, take))
        need_left -= take
        if need_left <= ZERO:
            break
    return picked


def slice_lots_across_quantities(
    picked: Sequence[Tuple[InventoryLot, Decimal]],
    quantities: Sequence[Tuple[Optional[int], Decimal]],
) -> List[Tuple[Optional[int], List[Dict[str, Any]]]]:
    """لات‌های برداشت‌شده را به سهم واریانت/مقدار می‌شکند تا تاریخ‌ها در تفکیک موجودی حفظ شود."""
    remaining: List[Tuple[InventoryLot, Decimal]] = [(lot, _d(qty)) for lot, qty in picked if _d(qty) > ZERO]
    out: List[Tuple[Optional[int], List[Dict[str, Any]]]] = []
    for variant_id, need in quantities:
        need_left = _d(need)
        allocs: List[Dict[str, Any]] = []
        while need_left > ZERO and remaining:
            lot, avail = remaining[0]
            take = avail if avail <= need_left else need_left
            allocs.append(
                {
                    "lot_code": lot.lot_code,
                    "manufacturing_date": lot.manufacturing_date.isoformat() if lot.manufacturing_date else None,
                    "expiry_date": lot.expiry_date.isoformat() if lot.expiry_date else None,
                    "quantity": str(take),
                    "is_undated": bool(getattr(lot, "is_undated", False)),
                }
            )
            leftover = avail - take
            if leftover > ZERO:
                remaining[0] = (lot, leftover)
            else:
                remaining.pop(0)
            need_left -= take
        if need_left > ZERO:
            raise ApiError(
                "INSUFFICIENT_LOT",
                "موجودی لات برای تفکیک واریانت کافی نیست",
                http_status=409,
                details={"shortage_main": str(need_left), "variant_id": variant_id},
            )
        out.append((variant_id, allocs))
    return out


def _effective_allow_unsellable(
    product: Product,
    *,
    allow_expired_confirm: bool,
    allow_unsellable: Optional[bool],
) -> bool:
    if allow_unsellable is not None:
        return bool(allow_unsellable)
    return bool(allow_expired_confirm) and str(
        getattr(product, "expired_sale_policy", None) or ""
    ) == EXPIRED_SALE_CONFIRM


def _allocation_rows_to_line_items(
    rows: Sequence[InvoiceItemLineLotAllocation],
    product: Product,
    source_unit: Any,
    dest_unit: Any,
    need_line: Decimal,
) -> List[Dict[str, Any]]:
    from app.services.invoice_unit_conversion_service import quantity_main_to_line

    need_main = quantity_line_to_main(need_line, product, dest_unit, strict=True)
    sold_newest: List[Tuple[int, Decimal]] = []
    for row in reversed(list(rows)):
        sold_newest.append(
            (int(row.lot_id), quantity_line_to_main(row.quantity, product, source_unit, strict=True))
        )
    picked = pick_return_lots(sold_newest, {}, need_main)
    items: List[Dict[str, Any]] = []
    for lot_id, qty_main in picked:
        items.append(
            {
                "lot_id": int(lot_id),
                "quantity": quantity_main_to_line(qty_main, product, dest_unit, strict=True),
            }
        )
    return items


def suggest_sales_return_lot_items(
    db: Session,
    business_id: int,
    product: Product,
    qty_line: Decimal,
    extra: Dict[str, Any],
    *,
    source_invoice_id: Optional[int] = None,
    exclude_invoice_line_id: Optional[int] = None,
) -> List[Dict[str, Any]]:
    """لات‌های همان فروش را برای برگشت پیشنهاد می‌کند؛ در نبود منبع، آخرین فروش خالص."""
    dest_unit = extra.get("unit")
    source_line_id = extra.get("returned_from_invoice_item_line_id") or extra.get(
        "source_invoice_item_line_id"
    )
    if source_line_id is not None:
        try:
            source_line_id = int(source_line_id)
        except (TypeError, ValueError):
            source_line_id = None
    if source_line_id is not None:
        source_line = db.get(InvoiceItemLine, source_line_id)
        if source_line is not None and int(source_line.product_id) == int(product.id):
            src_extra = extra_info_dict(source_line.extra_info)
            rows = (
                db.query(InvoiceItemLineLotAllocation)
                .filter(InvoiceItemLineLotAllocation.invoice_item_line_id == int(source_line.id))
                .order_by(InvoiceItemLineLotAllocation.id.asc())
                .all()
            )
            return _allocation_rows_to_line_items(
                rows, product, src_extra.get("unit"), dest_unit, qty_line
            )

    src_inv = source_invoice_id or extra.get("returned_from_invoice_id") or extra.get("source_invoice_id")
    if src_inv is not None:
        try:
            src_inv = int(src_inv)
        except (TypeError, ValueError):
            src_inv = None
    if src_inv is not None:
        source_lines = (
            db.query(InvoiceItemLine)
            .filter(
                InvoiceItemLine.document_id == int(src_inv),
                InvoiceItemLine.product_id == int(product.id),
            )
            .order_by(InvoiceItemLine.id.asc())
            .all()
        )
        rows: List[InvoiceItemLineLotAllocation] = []
        src_unit = dest_unit
        for line in source_lines:
            src_unit = extra_info_dict(line.extra_info).get("unit") or src_unit
            rows.extend(
                db.query(InvoiceItemLineLotAllocation)
                .filter(InvoiceItemLineLotAllocation.invoice_item_line_id == int(line.id))
                .order_by(InvoiceItemLineLotAllocation.id.asc())
                .all()
            )
        if rows:
            return _allocation_rows_to_line_items(rows, product, src_unit, dest_unit, qty_line)

    history = (
        db.query(InvoiceItemLineLotAllocation, InvoiceItemLine, Document)
        .join(InvoiceItemLine, InvoiceItemLine.id == InvoiceItemLineLotAllocation.invoice_item_line_id)
        .join(Document, Document.id == InvoiceItemLine.document_id)
        .filter(
            InvoiceItemLineLotAllocation.business_id == int(business_id),
            InvoiceItemLineLotAllocation.product_id == int(product.id),
            Document.business_id == int(business_id),
            Document.document_type.in_(("invoice_sales", "invoice_sales_return")),
        )
        .order_by(Document.document_date.asc(), InvoiceItemLineLotAllocation.id.asc())
        .all()
    )
    sold_newest: List[Tuple[int, Decimal]] = []
    returned: Dict[int, Decimal] = {}
    from app.services.invoice_unit_conversion_service import quantity_line_to_main as _to_main

    for alloc, line, document in history:
        if exclude_invoice_line_id is not None and int(line.id) == int(exclude_invoice_line_id):
            continue
        line_unit = extra_info_dict(line.extra_info).get("unit")
        qty_main = _to_main(alloc.quantity, product, line_unit, strict=True)
        doc_type = str(document.document_type or "")
        if doc_type == "invoice_sales":
            sold_newest.append((int(alloc.lot_id), qty_main))
        elif doc_type == "invoice_sales_return":
            lid = int(alloc.lot_id)
            returned[lid] = returned.get(lid, ZERO) + qty_main
    sold_newest.reverse()
    need_main = quantity_line_to_main(qty_line, product, dest_unit, strict=True)
    picked = pick_return_lots(sold_newest, returned, need_main)
    from app.services.invoice_unit_conversion_service import quantity_main_to_line

    return [
        {
            "lot_id": int(lot_id),
            "quantity": quantity_main_to_line(qty_main, product, dest_unit, strict=True),
        }
        for lot_id, qty_main in picked
    ]


def persist_invoice_lot_allocations(
    db: Session,
    business_id: int,
    invoice_line: InvoiceItemLine,
    product: Product,
    payload: Dict[str, Any],
    *,
    movement: str,
    warehouse_id: Optional[int],
    document_date: date,
    allow_expired_confirm: bool = False,
    allow_unsellable: Optional[bool] = None,
    restore_from_sales: bool = False,
    source_invoice_id: Optional[int] = None,
) -> List[InvoiceItemLineLotAllocation]:
    db.query(InvoiceItemLineLotAllocation).filter(
        InvoiceItemLineLotAllocation.invoice_item_line_id == int(invoice_line.id)
    ).delete(synchronize_session=False)
    if not is_expiry_tracked_product(product):
        if parse_payload_lot_allocations(payload):
            raise ApiError("EXPIRY_NOT_ENABLED", "برای کالای بدون ردیابی تاریخ نمی‌توان لات ثبت کرد", http_status=422)
        db.flush()
        return []
    if str(product.inventory_mode or "bulk") == "unique":
        if parse_payload_lot_allocations(payload):
            raise ApiError(
                "LOT_UNIQUE_NOT_SUPPORTED",
                "کالای یونیک تاریخ را روی هر واحد نگه می‌دارد، نه روی لات جمعی",
                http_status=422,
            )
        db.flush()
        return []

    items = parse_payload_lot_allocations(payload)
    inbound = movement == "in"
    variant_id = _parse_variant_id(payload)
    extra = {
        **extra_info_dict(payload.get("extra_info") if isinstance(payload, dict) else None),
        **extra_info_dict(invoice_line.extra_info),
    }
    line_unit = extra.get("unit")
    qty_line = _d(invoice_line.quantity)

    if not items:
        if inbound:
            extra["allow_undated_opening"] = bool(
                extra.get("allow_undated_opening")
                or extra_info_dict(payload.get("extra_info") if isinstance(payload, dict) else None).get("allow_undated_opening")
            )
            if extra.get("allow_undated_opening"):
                from app.services.inventory_lot_service import ensure_undated_lot

                lot = ensure_undated_lot(db, business_id, product, variant_id=variant_id)
                row = InvoiceItemLineLotAllocation(
                    business_id=int(business_id),
                    invoice_item_line_id=int(invoice_line.id),
                    product_id=int(product.id),
                    lot_id=int(lot.id),
                    quantity=qty_line,
                )
                db.add(row)
                db.flush()
                extra["lot_allocations"] = invoice_lot_allocations_payload([row], db)
                invoice_line.extra_info = extra
                from sqlalchemy.orm.attributes import flag_modified

                flag_modified(invoice_line, "extra_info")
                return [row]
            if restore_from_sales:
                items = suggest_sales_return_lot_items(
                    db,
                    business_id,
                    product,
                    qty_line,
                    extra,
                    source_invoice_id=source_invoice_id,
                    exclude_invoice_line_id=int(invoice_line.id),
                )
            if not items:
                raise ApiError(
                    "LOT_REQUIRED",
                    "برای ورود کالای تاریخ‌دار باید لات و تاریخ تولید/انقضا ثبت شود",
                    http_status=422,
                )
        else:
            from app.services.invoice_unit_conversion_service import quantity_main_to_line

            allow = _effective_allow_unsellable(
                product,
                allow_expired_confirm=allow_expired_confirm,
                allow_unsellable=allow_unsellable,
            )
            rows: List[InvoiceItemLineLotAllocation] = []
            for vid, qty_slice in _variant_quantity_slices(payload, extra, qty_line):
                qty_main = quantity_line_to_main(qty_slice, product, line_unit, strict=True)
                picked = suggest_fefo(
                    db,
                    business_id,
                    product,
                    warehouse_id,
                    qty_main,
                    document_date,
                    variant_id=vid,
                    allow_unsellable=allow,
                )
                for lot, qty_main_take in picked:
                    qty_as_line = quantity_main_to_line(qty_main_take, product, line_unit, strict=True)
                    row = InvoiceItemLineLotAllocation(
                        business_id=int(business_id),
                        invoice_item_line_id=int(invoice_line.id),
                        product_id=int(product.id),
                        lot_id=int(lot.id),
                        quantity=qty_as_line,
                    )
                    db.add(row)
                    rows.append(row)
            db.flush()
            extra["lot_allocations"] = invoice_lot_allocations_payload(rows, db)
            invoice_line.extra_info = extra
            from sqlalchemy.orm.attributes import flag_modified

            flag_modified(invoice_line, "extra_info")
            return rows

    normalized: List[Tuple[InventoryLot, Decimal]] = []
    merged: Dict[int, Decimal] = {}
    lots_by_id: Dict[int, InventoryLot] = {}
    for item in items:
        qty = _d(item.get("quantity"))
        if qty <= 0:
            qty = qty_line
        if qty <= 0:
            raise ApiError("INVALID_LOT_ALLOCATION", "مقدار تخصیص لات باید بزرگ‌تر از صفر باشد", http_status=422)
        lot = _resolve_lot_from_item(
            db,
            business_id,
            product,
            item,
            variant_id=variant_id,
            inbound=inbound,
            allow_undated=bool(extra.get("allow_undated_opening")),
        )
        if not inbound and not is_lot_sellable(lot, product, document_date):
            if not _effective_allow_unsellable(
                product,
                allow_expired_confirm=allow_expired_confirm,
                allow_unsellable=allow_unsellable,
            ):
                raise ApiError(
                    "EXPIRED_LOT_BLOCKED",
                    "فروش/خروج لات منقضی یا مسدود برای این کالا مجاز نیست",
                    http_status=409,
                    details={"lot_id": int(lot.id)},
                )
        merged[int(lot.id)] = merged.get(int(lot.id), ZERO) + qty
        lots_by_id[int(lot.id)] = lot
    normalized = [(lots_by_id[lid], qty) for lid, qty in merged.items()]
    validate_allocation_sum(qty_line, [(lot.id, qty) for lot, qty in normalized])

    rows = []
    for lot, qty in normalized:
        row = InvoiceItemLineLotAllocation(
            business_id=int(business_id),
            invoice_item_line_id=int(invoice_line.id),
            product_id=int(product.id),
            lot_id=int(lot.id),
            quantity=qty,
        )
        db.add(row)
        rows.append(row)
    db.flush()
    extra["lot_allocations"] = invoice_lot_allocations_payload(rows, db)
    invoice_line.extra_info = extra
    from sqlalchemy.orm.attributes import flag_modified

    flag_modified(invoice_line, "extra_info")
    return rows


def invoice_lot_allocations_payload(
    rows: Iterable[InvoiceItemLineLotAllocation], db: Session
) -> List[Dict[str, Any]]:
    ids = [int(r.lot_id) for r in rows]
    lots = {
        int(l.id): l
        for l in db.query(InventoryLot).filter(InventoryLot.id.in_(ids)).all()
    } if ids else {}
    out: List[Dict[str, Any]] = []
    for row in rows:
        lot = lots.get(int(row.lot_id))
        out.append(
            {
                "lot_id": int(row.lot_id),
                "lot_code": lot.lot_code if lot else None,
                "manufacturing_date": lot.manufacturing_date.isoformat() if lot and lot.manufacturing_date else None,
                "expiry_date": lot.expiry_date.isoformat() if lot and lot.expiry_date else None,
                "quantity": str(row.quantity),
            }
        )
    return out


def persist_warehouse_lot_allocations(
    db: Session,
    business_id: int,
    warehouse_line: WarehouseDocumentLine,
    product: Product,
    allocations_main: Sequence[Tuple[int, Decimal]],
    *,
    source_by_lot: Optional[Dict[int, int]] = None,
) -> List[WarehouseLineLotAllocation]:
    db.query(WarehouseLineLotAllocation).filter(
        WarehouseLineLotAllocation.warehouse_document_line_id == int(warehouse_line.id)
    ).delete(synchronize_session=False)
    if not allocations_main:
        db.flush()
        return []
    validate_allocation_sum(_d(warehouse_line.quantity), allocations_main)
    rows: List[WarehouseLineLotAllocation] = []
    for lot_id, qty in allocations_main:
        row = WarehouseLineLotAllocation(
            business_id=int(business_id),
            warehouse_document_line_id=int(warehouse_line.id),
            product_id=int(product.id),
            lot_id=int(lot_id),
            source_document_allocation_id=(source_by_lot or {}).get(int(lot_id)),
            quantity=qty,
        )
        db.add(row)
        rows.append(row)
    db.flush()
    extra = extra_info_dict(warehouse_line.extra_info)
    extra["lot_allocations"] = [
        {"lot_id": int(r.lot_id), "quantity": str(r.quantity)} for r in rows
    ]
    warehouse_line.extra_info = extra
    from sqlalchemy.orm.attributes import flag_modified

    flag_modified(warehouse_line, "extra_info")
    return rows


def attach_warehouse_line_lots_from_payload(
    db: Session,
    business_id: int,
    warehouse_line: WarehouseDocumentLine,
    product: Product,
    payload: Dict[str, Any],
    *,
    document: Optional[WarehouseDocument] = None,
    source_line_unit: str | None = None,
    allow_expired_confirm: bool = False,
) -> List[WarehouseLineLotAllocation]:
    if not is_expiry_tracked_product(product):
        persist_warehouse_lot_allocations(db, business_id, warehouse_line, product, [])
        return []
    if str(product.inventory_mode or "bulk") == "unique":
        persist_warehouse_lot_allocations(db, business_id, warehouse_line, product, [])
        return []

    items = parse_payload_lot_allocations(payload)
    movement = str(warehouse_line.movement or "").lower()
    inbound = movement == "in"
    extra_payload = extra_info_dict(payload.get("extra_info"))
    variant_id = _parse_variant_id(payload)
    from app.core.business_calendar import business_today

    doc_date = getattr(document, "document_date", None) or business_today(business_id)
    warehouse_id = warehouse_line.warehouse_id
    qty_source = _d(payload.get("quantity") or warehouse_line.quantity)

    if not items:
        if inbound:
            if document is not None and str(getattr(document, "doc_type", "") or "") == "transfer":
                persist_warehouse_lot_allocations(db, business_id, warehouse_line, product, [])
                return []
            source_type = str(getattr(document, "source_type", "") or "") if document is not None else ""
            if source_type == "opening_balance" or extra_payload.get("allow_undated_opening") or extra_payload.get("allow_undated"):
                from app.services.inventory_lot_service import ensure_undated_lot

                lot = ensure_undated_lot(db, business_id, product, variant_id=variant_id)
                return persist_warehouse_lot_allocations(
                    db, business_id, warehouse_line, product, [(int(lot.id), _d(warehouse_line.quantity))]
                )
            raise ApiError(
                "LOT_REQUIRED",
                "برای ورود کالای تاریخ‌دار باید لات و تاریخ تولید/انقضا ثبت شود",
                http_status=422,
            )
        converted: List[Tuple[int, Decimal]] = []
        for vid, qty_slice in _variant_quantity_slices(payload, extra_payload, warehouse_line.quantity):
            picked = suggest_fefo(
                db,
                business_id,
                product,
                int(warehouse_id) if warehouse_id is not None else None,
                _d(qty_slice),
                doc_date,
                variant_id=vid,
                allow_unsellable=allow_expired_confirm,
            )
            converted.extend((int(lot.id), qty) for lot, qty in picked)
        return persist_warehouse_lot_allocations(db, business_id, warehouse_line, product, converted)

    converted: List[Tuple[int, Decimal]] = []
    merged: Dict[int, Decimal] = {}
    for item in items:
        qty = _d(item.get("quantity"))
        if qty <= 0:
            qty = qty_source
        if qty <= 0:
            raise ApiError("INVALID_LOT_ALLOCATION", "مقدار تخصیص لات باید بزرگ‌تر از صفر باشد", http_status=422)
        lot = _resolve_lot_from_item(
            db,
            business_id,
            product,
            item,
            variant_id=variant_id,
            inbound=inbound,
            allow_undated=bool(extra_payload.get("allow_undated_opening") or extra_payload.get("allow_undated")),
        )
        qty_main = quantity_line_to_main(qty, product, source_line_unit, strict=True)
        merged[int(lot.id)] = merged.get(int(lot.id), ZERO) + qty_main
        if not inbound:
            from app.services.inventory_lot_service import is_lot_sellable

            if not is_lot_sellable(lot, product, doc_date) and not allow_expired_confirm:
                raise ApiError(
                    "EXPIRED_LOT_BLOCKED",
                    "فروش/خروج لات منقضی یا مسدود برای این کالا مجاز نیست",
                    http_status=409,
                    details={"lot_id": int(lot.id)},
                )
            avail = compute_available_lot_stock(
                db,
                business_id,
                int(product.id),
                int(warehouse_id) if warehouse_id is not None else None,
                int(lot.id),
                doc_date,
            )
            if avail < qty_main:
                raise ApiError(
                    "INSUFFICIENT_LOT",
                    f"موجودی لات «{lot.lot_code}» کافی نیست",
                    http_status=409,
                    details={
                        "lot_id": int(lot.id),
                        "available": str(avail),
                        "requested": str(qty_main),
                    },
                )
    converted = list(merged.items())
    validate_allocation_sum(_d(warehouse_line.quantity), converted)
    return persist_warehouse_lot_allocations(db, business_id, warehouse_line, product, converted)


def copy_invoice_lot_allocations_to_warehouse_line(
    db: Session,
    business_id: int,
    warehouse_line: WarehouseDocumentLine,
    product: Product,
    invoice_line: InvoiceItemLine,
) -> List[WarehouseLineLotAllocation]:
    src_rows = (
        db.query(InvoiceItemLineLotAllocation)
        .filter(InvoiceItemLineLotAllocation.invoice_item_line_id == int(invoice_line.id))
        .order_by(InvoiceItemLineLotAllocation.id.asc())
        .all()
    )
    extra = extra_info_dict(invoice_line.extra_info)
    unit = extra.get("unit")
    converted: List[Tuple[int, Decimal]] = []
    source_map: Dict[int, int] = {}
    for row in src_rows:
        qty_main = quantity_line_to_main(row.quantity, product, unit, strict=True)
        converted.append((int(row.lot_id), qty_main))
        source_map[int(row.lot_id)] = int(row.id)
    if is_expiry_tracked_product(product) and str(product.inventory_mode or "bulk") != "unique" and not converted:
        raise ApiError("LOT_REQUIRED", "برای این کالا تخصیص لات الزامی است", http_status=422)
    converted = scale_allocations_to_qty(converted, _d(warehouse_line.quantity))
    if converted:
        validate_allocation_sum(_d(warehouse_line.quantity), converted)
    return persist_warehouse_lot_allocations(
        db,
        business_id,
        warehouse_line,
        product,
        converted,
        source_by_lot=source_map,
    )


def copy_warehouse_lot_allocations_to_reverse_line(
    db: Session,
    business_id: int,
    source_line: WarehouseDocumentLine,
    reverse_line: WarehouseDocumentLine,
) -> None:
    rows = (
        db.query(WarehouseLineLotAllocation)
        .filter(WarehouseLineLotAllocation.warehouse_document_line_id == int(source_line.id))
        .all()
    )
    for row in rows:
        db.add(
            WarehouseLineLotAllocation(
                business_id=int(business_id),
                warehouse_document_line_id=int(reverse_line.id),
                product_id=int(row.product_id),
                lot_id=int(row.lot_id),
                source_document_allocation_id=row.source_document_allocation_id,
                quantity=row.quantity,
            )
        )
    db.flush()


def assert_transfer_lot_allocations_match(
    db: Session,
    out_line: WarehouseDocumentLine,
    in_line: WarehouseDocumentLine,
) -> None:
    def _map(line_id: int) -> Dict[int, Decimal]:
        return {
            int(r.lot_id): _d(r.quantity)
            for r in db.query(WarehouseLineLotAllocation)
            .filter(WarehouseLineLotAllocation.warehouse_document_line_id == int(line_id))
            .all()
        }

    if _map(int(out_line.id)) != _map(int(in_line.id)):
        raise ApiError(
            "TRANSFER_LOT_MISMATCH",
            "تخصیص لات دو سمت حواله انتقال یکسان نیست",
            http_status=422,
        )
