"""لات و تاریخ انقضا؛ موجودی لات از دو دفتر فاکتور/حواله مثل واریانت محاسبه می‌شود."""

from __future__ import annotations

from datetime import date, datetime, timedelta
from decimal import Decimal
from types import SimpleNamespace
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
from app.core.transaction_lock import acquire_transaction_lock
from app.services.invoice_unit_conversion_service import extra_info_dict, inventory_quantity_to_main
from app.services.invoice_unit_conversion_service import quantity_main_to_line

ZERO = Decimal("0")
UNDATED_LOT_CODE = "-"
LOT_POLICY_OPTIONAL = "optional"
LOT_POLICY_REQUIRED = "required"
EXPIRED_SALE_BLOCK = "block"
EXPIRED_SALE_CONFIRM = "manager_confirm"
STATUS_SELLABLE = "sellable"
STATUS_NEAR_EXPIRY = "near_expiry"
STATUS_BLOCKED = "blocked"
STATUS_EXPIRED = "expired"
STATUS_UNDATED = "undated"


def _d(value: Any) -> Decimal:
    return Decimal(str(value if value is not None else 0))


def business_as_of(business_id: Optional[int] = None, explicit: date | None = None) -> date:
    if explicit is not None:
        return explicit
    from app.core.business_calendar import business_today

    return business_today(business_id)


def _as_date(value: Any) -> date | None:
    if value is None or value == "":
        return None
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, date):
        return value
    text = str(value).strip()
    if not text:
        return None
    try:
        return date.fromisoformat(text[:10])
    except ValueError as exc:
        raise ApiError("INVALID_LOT_DATE", "تاریخ لات نامعتبر است", http_status=422) from exc


def is_expiry_tracked_product(product: Any) -> bool:
    if product is None:
        return False
    if not bool(getattr(product, "track_inventory", False)):
        return False
    return bool(getattr(product, "track_expiry", False))


def lot_identity_key(
    product_id: int,
    variant_id: int | None,
    lot_code: str | None,
    manufacturing_date: date | None,
    expiry_date: date | None,
    *,
    is_undated: bool = False,
) -> str:
    code = (lot_code or UNDATED_LOT_CODE).strip() or UNDATED_LOT_CODE
    mfg = manufacturing_date.isoformat() if manufacturing_date else ""
    exp = expiry_date.isoformat() if expiry_date else ""
    marker = "U" if is_undated else "D"
    return f"{int(product_id)}|{int(variant_id or 0)}|{code}|{mfg}|{exp}|{marker}"


def compute_lot_dates(
    product: Product,
    *,
    manufacturing_date: date | None,
    expiry_date: date | None,
    best_before_date: date | None = None,
    removal_date: date | None = None,
    alert_date: date | None = None,
) -> Dict[str, date | None]:
    shelf = getattr(product, "shelf_life_days", None)
    try:
        shelf_i = int(shelf) if shelf is not None else None
    except (TypeError, ValueError):
        shelf_i = None
    if shelf_i is not None and shelf_i <= 0:
        shelf_i = None

    mfg = manufacturing_date
    exp = expiry_date
    if exp is None and mfg is not None and shelf_i is not None:
        exp = mfg + timedelta(days=shelf_i)

    def _offset(raw: Any) -> int | None:
        try:
            n = int(raw) if raw is not None else None
        except (TypeError, ValueError):
            return None
        if n is None or n < 0:
            return None
        return n

    best = best_before_date
    removal = removal_date
    alert = alert_date
    if exp is not None:
        bb = _offset(getattr(product, "best_before_offset_days", None))
        rm = _offset(getattr(product, "removal_offset_days", None))
        al = _offset(getattr(product, "alert_offset_days", None))
        if best is None and bb is not None:
            best = exp - timedelta(days=bb)
        if removal is None and rm is not None:
            removal = exp - timedelta(days=rm)
        if alert is None and al is not None:
            alert = exp - timedelta(days=al)
    return {
        "manufacturing_date": mfg,
        "expiry_date": exp,
        "best_before_date": best,
        "removal_date": removal,
        "alert_date": alert,
    }


def lot_status(lot: InventoryLot, as_of: date, *, min_remaining_days: int = 0) -> str:
    if bool(getattr(lot, "is_undated", False)):
        return STATUS_UNDATED
    exp = lot.expiry_date
    if exp is not None and as_of >= exp:
        return STATUS_EXPIRED
    removal = lot.removal_date
    if removal is not None and as_of >= removal:
        return STATUS_BLOCKED
    if exp is not None and min_remaining_days > 0:
        remaining = (exp - as_of).days
        if remaining < int(min_remaining_days):
            return STATUS_BLOCKED
    alert = lot.alert_date
    if alert is not None and as_of >= alert:
        return STATUS_NEAR_EXPIRY
    if exp is not None:
        default_alert = getattr(lot, "alert_date", None)
        if default_alert is None:
            remaining = (exp - as_of).days
            if remaining <= 7:
                return STATUS_NEAR_EXPIRY
    return STATUS_SELLABLE


def is_lot_sellable(lot: InventoryLot, product: Product, as_of: date) -> bool:
    min_rsl = int(getattr(product, "min_remaining_shelf_life_days", 0) or 0)
    status = lot_status(lot, as_of, min_remaining_days=min_rsl)
    return status in {STATUS_SELLABLE, STATUS_NEAR_EXPIRY, STATUS_UNDATED}


def instance_expiry_view(instance: Any, product: Product, as_of: date) -> Dict[str, Any]:
    dates = compute_lot_dates(
        product,
        manufacturing_date=getattr(instance, "manufacturing_date", None),
        expiry_date=getattr(instance, "expiry_date", None),
    )
    fake = SimpleNamespace(
        is_undated=dates["manufacturing_date"] is None and dates["expiry_date"] is None,
        expiry_date=dates["expiry_date"],
        removal_date=dates["removal_date"],
        alert_date=dates["alert_date"],
    )
    min_rsl = int(getattr(product, "min_remaining_shelf_life_days", 0) or 0)
    status = lot_status(fake, as_of, min_remaining_days=min_rsl)
    remaining = None
    if dates["expiry_date"] is not None:
        remaining = (dates["expiry_date"] - as_of).days
    return {**dates, "status": status, "remaining_days": remaining}


def is_instance_sellable(instance: Any, product: Product, as_of: date) -> bool:
    return instance_expiry_view(instance, product, as_of)["status"] in {
        STATUS_SELLABLE,
        STATUS_NEAR_EXPIRY,
        STATUS_UNDATED,
    }


def unique_sellable_quantity(
    db: Session,
    business_id: int,
    product: Product,
    warehouse_id: Optional[int],
    as_of: date,
) -> Decimal:
    from adapters.db.models.product_instance import ProductInstance

    q = db.query(ProductInstance).filter(
        ProductInstance.business_id == int(business_id),
        ProductInstance.product_id == int(product.id),
        ProductInstance.status == "available",
    )
    if warehouse_id is not None:
        q = q.filter(ProductInstance.warehouse_id == int(warehouse_id))
    count = 0
    for inst in q.all():
        if is_instance_sellable(inst, product, as_of):
            count += 1
    return Decimal(count)


def pick_unique_instances_fefo(
    db: Session,
    business_id: int,
    product: Product,
    warehouse_id: Optional[int],
    quantity: Any,
    as_of: date,
    *,
    skip_expired: Optional[bool] = None,
) -> List[int]:
    """واحدهای یونیک موجود را به ترتیب نزدیک‌ترین انقضا برمی‌گرداند."""
    from adapters.db.models.product_instance import ProductInstance

    try:
        need = int(Decimal(str(quantity or 0)))
    except Exception:
        need = 0
    if need <= 0:
        return []
    if skip_expired is None:
        skip_expired = is_expiry_tracked_product(product)
    q = db.query(ProductInstance).filter(
        ProductInstance.business_id == int(business_id),
        ProductInstance.product_id == int(product.id),
        ProductInstance.status == "available",
    )
    if warehouse_id is not None:
        q = q.filter(ProductInstance.warehouse_id == int(warehouse_id))
    scored: List[Tuple[date, int]] = []
    for inst in q.all():
        if skip_expired and not is_instance_sellable(inst, product, as_of):
            continue
        view = instance_expiry_view(inst, product, as_of)
        exp = view.get("expiry_date") or date.max
        scored.append((exp, int(inst.id)))
    scored.sort(key=lambda row: (row[0], row[1]))
    if len(scored) < need:
        raise ApiError(
            "INSUFFICIENT_UNIQUE",
            "واحد یونیک قابل‌مصرف کافی در انبار نیست",
            http_status=409,
        )
    return [inst_id for _, inst_id in scored[:need]]


def unit_dates_from_lot_balances(
    balances: Sequence[Dict[str, Any]],
    unit_count: int,
) -> List[Tuple[Optional[str], Optional[str]]]:
    """تاریخ تولید/انقضای هر واحد یونیک را از ماندهٔ لات‌ها به ترتیب FEFO می‌سازد."""
    queue: List[Tuple[Optional[str], Optional[str]]] = []
    for row in balances or []:
        try:
            qty = int(Decimal(str(row.get("quantity_main") or 0)))
        except Exception:
            qty = 0
        mfg = row.get("manufacturing_date")
        exp = row.get("expiry_date")
        mfg_s = mfg.isoformat() if hasattr(mfg, "isoformat") else (str(mfg)[:10] if mfg else None)
        exp_s = exp.isoformat() if hasattr(exp, "isoformat") else (str(exp)[:10] if exp else None)
        for _ in range(max(qty, 0)):
            queue.append((mfg_s, exp_s))
    need = max(int(unit_count or 0), 0)
    if len(queue) < need:
        queue.extend([(None, None)] * (need - len(queue)))
    return queue[:need]


def dual_unit_qty(product: Product, qty_main: Decimal) -> Dict[str, Any]:
    main = str(getattr(product, "main_unit", None) or "").strip() or None
    secondary = str(getattr(product, "secondary_unit", None) or "").strip() or None
    qty_sec = None
    if secondary:
        try:
            qty_sec = float(quantity_main_to_line(qty_main, product, secondary, strict=False))
        except Exception:
            qty_sec = None
    return {
        "quantity_main": float(qty_main),
        "main_unit": main,
        "quantity_secondary": qty_sec,
        "secondary_unit": secondary,
    }


def acquire_lot_stock_locks(
    db: Session,
    business_id: int,
    keys: Sequence[Tuple[int, int, int]],
) -> None:
    product_keys = sorted({(int(wh), int(pid)) for wh, pid, _lid in keys})
    for warehouse_id, product_id in product_keys:
        acquire_transaction_lock(
            db,
            f"inventory_stock:{int(business_id)}:{warehouse_id}:{product_id}",
        )
    lot_keys = sorted({(int(wh), int(pid), int(lid)) for wh, pid, lid in keys})
    for warehouse_id, product_id, lot_id in lot_keys:
        acquire_transaction_lock(
            db,
            f"inventory_lot:{int(business_id)}:{warehouse_id}:{product_id}:{lot_id}",
        )


def find_or_create_lot(
    db: Session,
    business_id: int,
    product: Product,
    *,
    lot_code: str | None = None,
    variant_id: int | None = None,
    manufacturing_date: date | None = None,
    expiry_date: date | None = None,
    best_before_date: date | None = None,
    removal_date: date | None = None,
    alert_date: date | None = None,
    is_undated: bool = False,
    allow_missing_dates: bool = False,
) -> InventoryLot:
    if not is_expiry_tracked_product(product) and not is_undated:
        raise ApiError("EXPIRY_NOT_ENABLED", "ردیابی تاریخ برای این کالا فعال نیست", http_status=422)

    policy = str(getattr(product, "lot_policy", None) or LOT_POLICY_OPTIONAL)
    code = (lot_code or UNDATED_LOT_CODE).strip() or UNDATED_LOT_CODE
    if policy == LOT_POLICY_REQUIRED and not is_undated and code == UNDATED_LOT_CODE:
        raise ApiError("LOT_CODE_REQUIRED", "برای این کالا شماره لات الزامی است", http_status=422)

    dates = compute_lot_dates(
        product,
        manufacturing_date=manufacturing_date,
        expiry_date=expiry_date,
        best_before_date=best_before_date,
        removal_date=removal_date,
        alert_date=alert_date,
    )
    if (
        not is_undated
        and not allow_missing_dates
        and dates["manufacturing_date"] is None
        and dates["expiry_date"] is None
    ):
        raise ApiError(
            "LOT_DATE_REQUIRED",
            "برای کالای تاریخ‌دار باید تاریخ تولید یا تاریخ انقضا ثبت شود",
            http_status=422,
        )

    key = lot_identity_key(
        int(product.id),
        variant_id,
        code,
        dates["manufacturing_date"],
        dates["expiry_date"],
        is_undated=is_undated,
    )
    row = (
        db.query(InventoryLot)
        .filter(InventoryLot.business_id == int(business_id), InventoryLot.identity_key == key)
        .first()
    )
    if row is not None:
        changed = False
        for field in ("best_before_date", "removal_date", "alert_date"):
            incoming = dates.get(field)
            if incoming is not None and getattr(row, field) is None:
                setattr(row, field, incoming)
                changed = True
        if changed:
            row.updated_at = datetime.utcnow()
            db.flush()
        return row

    row = InventoryLot(
        business_id=int(business_id),
        product_id=int(product.id),
        variant_id=int(variant_id) if variant_id else None,
        lot_code=code,
        identity_key=key,
        manufacturing_date=dates["manufacturing_date"],
        expiry_date=dates["expiry_date"],
        best_before_date=dates["best_before_date"],
        removal_date=dates["removal_date"],
        alert_date=dates["alert_date"],
        is_undated=bool(is_undated),
    )
    db.add(row)
    db.flush()
    return row


def lot_to_dict(lot: InventoryLot, product: Product | None = None, qty_main: Decimal | None = None, as_of: date | None = None) -> Dict[str, Any]:
    as_of = as_of or business_as_of(getattr(lot, "business_id", None))
    status = lot_status(lot, as_of, min_remaining_days=int(getattr(product, "min_remaining_shelf_life_days", 0) or 0) if product else 0)
    payload: Dict[str, Any] = {
        "id": int(lot.id),
        "product_id": int(lot.product_id),
        "variant_id": int(lot.variant_id) if lot.variant_id else None,
        "lot_code": lot.lot_code,
        "manufacturing_date": lot.manufacturing_date.isoformat() if lot.manufacturing_date else None,
        "expiry_date": lot.expiry_date.isoformat() if lot.expiry_date else None,
        "best_before_date": lot.best_before_date.isoformat() if lot.best_before_date else None,
        "removal_date": lot.removal_date.isoformat() if lot.removal_date else None,
        "alert_date": lot.alert_date.isoformat() if lot.alert_date else None,
        "is_undated": bool(lot.is_undated),
        "status": status,
    }
    if product is not None and qty_main is not None:
        payload.update(dual_unit_qty(product, qty_main))
        remaining = None
        if lot.expiry_date is not None:
            remaining = (lot.expiry_date - as_of).days
        payload["remaining_days"] = remaining
    elif qty_main is not None:
        payload["quantity_main"] = float(qty_main)
    return payload


def _warehouse_doc_is_cancel_reversal_of_cancelled(
    db: Session,
    business_id: int,
    wh_doc: WarehouseDocument,
) -> bool:
    extra = extra_info_dict(wh_doc.extra_info)
    src_id = extra.get("cancels_warehouse_document_id") or wh_doc.source_document_id
    if not src_id:
        return False
    try:
        src_id_int = int(src_id)
    except (TypeError, ValueError):
        return False
    src = (
        db.query(WarehouseDocument.status)
        .filter(
            WarehouseDocument.id == src_id_int,
            WarehouseDocument.business_id == int(business_id),
        )
        .first()
    )
    if not src:
        return False
    return str(src[0] or "").strip().lower() == "cancelled"


def ensure_undated_lot(
    db: Session,
    business_id: int,
    product: Product,
    *,
    variant_id: int | None = None,
) -> InventoryLot:
    return find_or_create_lot(
        db,
        business_id,
        product,
        lot_code=UNDATED_LOT_CODE,
        variant_id=variant_id,
        is_undated=True,
        allow_missing_dates=True,
    )


def ensure_undated_lots_for_product(db: Session, business_id: int, product: Product) -> None:
    if str(getattr(product, "inventory_mode", None) or "bulk") == "unique":
        return
    from app.services.product_variant_service import is_variant_inventory_product, list_variants

    if is_variant_inventory_product(product):
        variants = list_variants(db, int(business_id), int(product.id))
        created = False
        for row in variants:
            vid = row.get("id") if isinstance(row, dict) else getattr(row, "id", None)
            if vid:
                ensure_undated_lot(db, business_id, product, variant_id=int(vid))
                created = True
        if created:
            return
    ensure_undated_lot(db, business_id, product)


def _allocated_lot_stock(
    db: Session,
    business_id: int,
    product_id: int,
    warehouse_id: Optional[int],
    lot_id: int,
    up_to_date: date,
    exclude_document_id: Optional[int] = None,
    *,
    exclude_invoice_source_document_id: Optional[int] = None,
    exclude_warehouse_document_ids: Optional[List[int]] = None,
) -> Decimal:
    product = (
        db.query(Product)
        .filter(Product.id == int(product_id), Product.business_id == int(business_id))
        .first()
    )
    bal = ZERO

    iil_q = (
        db.query(InvoiceItemLineLotAllocation, InvoiceItemLine, Document)
        .join(InvoiceItemLine, InvoiceItemLine.id == InvoiceItemLineLotAllocation.invoice_item_line_id)
        .join(Document, Document.id == InvoiceItemLine.document_id)
        .filter(
            InvoiceItemLineLotAllocation.business_id == int(business_id),
            InvoiceItemLineLotAllocation.product_id == int(product_id),
            InvoiceItemLineLotAllocation.lot_id == int(lot_id),
            Document.business_id == int(business_id),
            Document.is_proforma == False,  # noqa: E712
            Document.document_date <= up_to_date,
        )
    )
    if exclude_document_id is not None:
        iil_q = iil_q.filter(Document.id != int(exclude_document_id))
    for alloc, line, doc in iil_q.all():
        info = extra_info_dict(line.extra_info)
        if info.get("inventory_posted") is False or info.get("inventory_tracked") is False:
            continue
        movement = info.get("movement")
        if movement not in ("in", "out"):
            doc_type = str(doc.document_type or "")
            if doc_type in ("invoice_sales", "invoice_purchase_return", "invoice_waste", "invoice_direct_consumption"):
                movement = "out"
            elif doc_type in ("invoice_purchase", "invoice_sales_return"):
                movement = "in"
            else:
                continue
        try:
            wh_id = int(info.get("warehouse_id")) if info.get("warehouse_id") is not None else None
        except (TypeError, ValueError):
            wh_id = None
        if warehouse_id is not None:
            if wh_id is None or int(wh_id) != int(warehouse_id):
                continue
        qty = inventory_quantity_to_main(alloc.quantity, product, info, strict=False)
        if qty <= 0:
            continue
        if movement == "in":
            bal += qty
        else:
            bal -= qty

    wh_q = (
        db.query(WarehouseLineLotAllocation, WarehouseDocumentLine, WarehouseDocument)
        .join(
            WarehouseDocumentLine,
            WarehouseDocumentLine.id == WarehouseLineLotAllocation.warehouse_document_line_id,
        )
        .join(WarehouseDocument, WarehouseDocument.id == WarehouseDocumentLine.warehouse_document_id)
        .filter(
            WarehouseLineLotAllocation.business_id == int(business_id),
            WarehouseLineLotAllocation.product_id == int(product_id),
            WarehouseLineLotAllocation.lot_id == int(lot_id),
            WarehouseDocument.business_id == int(business_id),
            WarehouseDocument.status == "posted",
            WarehouseDocument.document_date <= up_to_date,
        )
    )
    exclude_wh_ids = {int(x) for x in (exclude_warehouse_document_ids or []) if x is not None}
    for alloc, line, doc in wh_q.all():
        if int(doc.id) in exclude_wh_ids:
            continue
        st = str(getattr(doc, "source_type", None) or "").strip().lower()
        if st == "invoice":
            continue
        if _warehouse_doc_is_cancel_reversal_of_cancelled(db, business_id, doc):
            continue
        if exclude_invoice_source_document_id is not None and doc.source_document_id is not None:
            if int(doc.source_document_id) == int(exclude_invoice_source_document_id) and st == "invoice":
                continue
        extra = extra_info_dict(line.extra_info)
        try:
            wh_id = int(line.warehouse_id) if line.warehouse_id is not None else None
        except (TypeError, ValueError):
            wh_id = None
        if warehouse_id is not None:
            if wh_id is None or int(wh_id) != int(warehouse_id):
                continue
        qty = inventory_quantity_to_main(alloc.quantity, product, extra, strict=False)
        if qty <= 0:
            continue
        if str(line.movement or "").lower() == "in":
            bal += qty
        else:
            bal -= qty
    return bal


def compute_available_lot_stock(
    db: Session,
    business_id: int,
    product_id: int,
    warehouse_id: Optional[int],
    lot_id: int,
    up_to_date: date,
    exclude_document_id: Optional[int] = None,
    *,
    exclude_invoice_source_document_id: Optional[int] = None,
    exclude_warehouse_document_ids: Optional[List[int]] = None,
) -> Decimal:
    allocated = _allocated_lot_stock(
        db,
        business_id,
        product_id,
        warehouse_id,
        lot_id,
        up_to_date,
        exclude_document_id,
        exclude_invoice_source_document_id=exclude_invoice_source_document_id,
        exclude_warehouse_document_ids=exclude_warehouse_document_ids,
    )
    lot = db.get(InventoryLot, int(lot_id))
    if lot is None or not bool(getattr(lot, "is_undated", False)):
        return allocated

    lot_variant_id = int(lot.variant_id) if getattr(lot, "variant_id", None) else None
    if lot_variant_id is not None:
        from app.services.variant_inventory_service import compute_available_variant_stock

        total = _d(
            compute_available_variant_stock(
                db,
                business_id,
                int(product_id),
                warehouse_id,
                lot_variant_id,
                up_to_date,
                exclude_document_id,
                exclude_invoice_source_document_id=exclude_invoice_source_document_id,
                exclude_warehouse_document_ids=exclude_warehouse_document_ids,
            )
        )
    else:
        from app.services.invoice_service import _compute_available_stock

        total = _d(
            _compute_available_stock(
                db,
                business_id,
                int(product_id),
                warehouse_id,
                up_to_date,
                exclude_document_id,
                exclude_invoice_source_document_id=exclude_invoice_source_document_id,
                exclude_warehouse_document_ids=exclude_warehouse_document_ids,
            )
        )
    others = ZERO
    sibling_q = db.query(InventoryLot).filter(
        InventoryLot.business_id == int(business_id),
        InventoryLot.product_id == int(product_id),
        InventoryLot.id != int(lot_id),
    )
    if lot_variant_id is not None:
        sibling_q = sibling_q.filter(InventoryLot.variant_id == lot_variant_id)
    else:
        sibling_q = sibling_q.filter(InventoryLot.variant_id.is_(None))
    sibling_lots = sibling_q.all()
    for sibling in sibling_lots:
        others += _allocated_lot_stock(
            db,
            business_id,
            product_id,
            warehouse_id,
            int(sibling.id),
            up_to_date,
            exclude_document_id,
            exclude_invoice_source_document_id=exclude_invoice_source_document_id,
            exclude_warehouse_document_ids=exclude_warehouse_document_ids,
        )
    remainder = total - others - allocated
    if remainder < ZERO:
        remainder = ZERO
    return allocated + remainder


def list_lot_balances(
    db: Session,
    business_id: int,
    product_id: int,
    warehouse_id: Optional[int],
    as_of: date,
    *,
    sellable_only: bool = False,
    variant_id: Optional[int] = None,
    exclude_document_id: Optional[int] = None,
    exclude_invoice_source_document_id: Optional[int] = None,
    exclude_warehouse_document_ids: Optional[List[int]] = None,
) -> List[Dict[str, Any]]:
    product = (
        db.query(Product)
        .filter(Product.id == int(product_id), Product.business_id == int(business_id))
        .first()
    )
    if product is None or not is_expiry_tracked_product(product):
        return []
    if str(product.inventory_mode or "bulk") == "unique":
        return []
    ensure_undated_lot(db, business_id, product, variant_id=variant_id)
    q = db.query(InventoryLot).filter(
        InventoryLot.business_id == int(business_id), InventoryLot.product_id == int(product_id)
    )
    if variant_id is not None:
        q = q.filter(InventoryLot.variant_id == int(variant_id))
    lots = q.order_by(
        InventoryLot.expiry_date.asc().nullslast(), InventoryLot.manufacturing_date.asc().nullslast(), InventoryLot.id.asc()
    ).all()
    rows: List[Dict[str, Any]] = []
    for lot in lots:
        qty = compute_available_lot_stock(
            db,
            business_id,
            int(product_id),
            warehouse_id,
            int(lot.id),
            as_of,
            exclude_document_id,
            exclude_invoice_source_document_id=exclude_invoice_source_document_id,
            exclude_warehouse_document_ids=exclude_warehouse_document_ids,
        )
        if qty <= 0:
            continue
        if sellable_only and not is_lot_sellable(lot, product, as_of):
            continue
        item = lot_to_dict(lot, product, qty, as_of)
        item["warehouse_id"] = warehouse_id
        rows.append(item)
    return rows


def suggest_fefo(
    db: Session,
    business_id: int,
    product: Product,
    warehouse_id: Optional[int],
    qty_main: Decimal,
    as_of: date,
    *,
    variant_id: int | None = None,
    allow_unsellable: bool = False,
) -> List[Tuple[InventoryLot, Decimal]]:
    need = _d(qty_main)
    if need <= 0:
        return []
    if str(product.inventory_mode or "bulk") == "unique":
        return []
    ensure_undated_lot(db, business_id, product, variant_id=variant_id)
    q = db.query(InventoryLot).filter(
        InventoryLot.business_id == int(business_id),
        InventoryLot.product_id == int(product.id),
    )
    if variant_id:
        q = q.filter(InventoryLot.variant_id == int(variant_id))
    lots = q.order_by(
        InventoryLot.expiry_date.asc().nullslast(),
        InventoryLot.manufacturing_date.asc().nullslast(),
        InventoryLot.id.asc(),
    ).all()
    picked: List[Tuple[InventoryLot, Decimal]] = []
    for lot in lots:
        if not allow_unsellable and not is_lot_sellable(lot, product, as_of):
            continue
        avail = compute_available_lot_stock(
            db, business_id, int(product.id), warehouse_id, int(lot.id), as_of
        )
        if avail <= 0:
            continue
        take = avail if avail <= need else need
        picked.append((lot, take))
        need -= take
        if need <= 0:
            break
    if need > ZERO:
        raise ApiError(
            "INSUFFICIENT_SELLABLE_LOT",
            f"موجودی قابل‌فروش لات برای کالای «{product.name}» کافی نیست (کمبود {need})",
            http_status=409,
            details={"shortage_main": str(need), "product_id": int(product.id)},
        )
    return picked


def sellable_quantity(
    db: Session,
    business_id: int,
    product: Product,
    warehouse_id: Optional[int],
    as_of: date,
    exclude_document_id: Optional[int] = None,
    *,
    variant_id: Optional[int] = None,
    exclude_invoice_source_document_id: Optional[int] = None,
    exclude_warehouse_document_ids: Optional[List[int]] = None,
) -> Decimal:
    if not is_expiry_tracked_product(product):
        return ZERO
    if str(getattr(product, "inventory_mode", None) or "bulk") == "unique":
        return unique_sellable_quantity(db, business_id, product, warehouse_id, as_of)
    total = ZERO
    for row in list_lot_balances(
        db,
        business_id,
        int(product.id),
        warehouse_id,
        as_of,
        sellable_only=True,
        variant_id=variant_id,
        exclude_document_id=exclude_document_id,
        exclude_invoice_source_document_id=exclude_invoice_source_document_id,
        exclude_warehouse_document_ids=exclude_warehouse_document_ids,
    ):
        total += _d(row.get("quantity_main"))
    return total
