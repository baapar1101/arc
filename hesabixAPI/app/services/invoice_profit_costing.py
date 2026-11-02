"""Profit costing helpers: document-currency → base, and sales-return layer restore.

Invoice line monetary fields (``unit_price``, ``cost_price``, ``cogs_amount``)
are stored in the *document* currency. Inventory layers used by FIFO/LIFO/WMA
and average purchase cost must be in the business base currency, per product
main unit.

``invoice_sales`` / ``invoice_sales_return`` selling prices are never used as
inventory cost. Sales-return inbound layers without an explicit cost are
restored from lots consumed by prior sales.
"""
from __future__ import annotations

from collections import deque
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy.orm import Session

from adapters.db.models.business import Business
from adapters.db.models.document import Document
from app.services.invoice_unit_conversion_service import (
    extra_info_dict,
    inventory_price_to_main,
    inventory_quantity_to_main,
)

INVOICE_SALES = "invoice_sales"
INVOICE_SALES_RETURN = "invoice_sales_return"
_SALES_DOC_TYPES = frozenset({INVOICE_SALES, INVOICE_SALES_RETURN})


def _d(value: Any) -> Decimal:
    try:
        return Decimal(str(value if value is not None else 0))
    except Exception:
        return Decimal(0)


def movement_sort_key(mv: Dict[str, Any]) -> Tuple[Any, Any, int, int]:
    """Temporal order: document date, registered_at, document id, invoice line id."""
    ra = mv.get("registered_at")
    if ra is None:
        ra = datetime.min.replace(tzinfo=timezone.utc)
    elif isinstance(ra, datetime):
        if ra.tzinfo is None:
            ra = ra.replace(tzinfo=timezone.utc)
        else:
            ra = ra.astimezone(timezone.utc)
    else:
        try:
            ra = datetime.fromisoformat(str(ra).replace("Z", "+00:00"))
            if ra.tzinfo is None:
                ra = ra.replace(tzinfo=timezone.utc)
            else:
                ra = ra.astimezone(timezone.utc)
        except (TypeError, ValueError):
            ra = datetime.min.replace(tzinfo=timezone.utc)
    return (
        mv["document_date"],
        ra,
        int(mv["document_id"]),
        int(mv.get("invoice_item_line_id") or 0),
    )


def document_rate_to_base(
    db: Session,
    document: Document,
    business: Optional[Business] = None,
    cache: Optional[Dict[int, Decimal]] = None,
) -> Decimal:
    """1 document-currency unit → business base currency.

    Uses the locked snapshot, then inferred rate. Same-currency documents are 1.
    Historical rows without a rate fall back to 1 so listing profit cannot die
    on a single old invoice; documents that *have* a snapshot/infer rate are
    converted (the multi-currency bug this module exists to fix).
    """
    doc_id = int(getattr(document, "id", 0) or 0)
    if cache is not None and doc_id in cache:
        return cache[doc_id]
    from app.services.document_line_fx_service import resolve_document_fx_rate

    rate, _source = resolve_document_fx_rate(
        db,
        document,
        business=business,
        allow_infer=True,
        fallback_one_on_missing=True,
    )
    if rate is None or rate <= 0:
        rate = Decimal(1)
    else:
        rate = Decimal(str(rate))
    if cache is not None and doc_id:
        cache[doc_id] = rate
    return rate


def inventory_line_unit_cost_main_base(
    product: Any,
    extra_info: Any,
    quantity: Any,
    *,
    document_type: str,
    fx_rate: Decimal,
    movement: Optional[str] = None,
) -> Optional[Decimal]:
    """Unit inventory cost in product main unit and business base currency.

    Returns ``None`` when a sales/sales-return line has no explicit cost (so
    callers can restore sales-return inbound lots instead of using sell price).
    """
    info = extra_info_dict(extra_info)
    qty_main = inventory_quantity_to_main(quantity, product, info, strict=False)
    rate = _d(fx_rate)
    if rate <= 0:
        rate = Decimal(1)
    doc_type = str(document_type or "")
    is_sales_family = doc_type in _SALES_DOC_TYPES

    if info.get("cogs_amount") is not None and qty_main > 0:
        return (_d(info.get("cogs_amount")) / qty_main) * rate

    if info.get("cost_price") is not None:
        return inventory_price_to_main(info.get("cost_price"), product, info, strict=False) * rate

    if info.get("unit_price") is not None:
        if is_sales_family:
            return None
        return inventory_price_to_main(info.get("unit_price"), product, info, strict=False) * rate

    if is_sales_family and movement == "in":
        return None
    return Decimal(0)


def stamp_sales_return_in_layer_costs(
    movements: List[Dict[str, Any]],
    *,
    reverse: bool = False,
    wma: bool = False,
) -> None:
    """Fill missing cost on sales-return IN from lots consumed by prior sales.

    Mutates ``movements`` in place. Purchase/production inbound costs must
    already be in base currency per main unit.
    """
    sorted_mvs = sorted(movements, key=movement_sort_key)
    layers: deque = deque()
    consumed: List[Dict[str, Decimal]] = []
    q = Decimal(0)
    v = Decimal(0)
    last_wac: Optional[Decimal] = None

    def _wac() -> Decimal:
        if q > 0:
            return v / q
        return Decimal(str(last_wac or 0))

    def _restore_from_consumed(need: Decimal) -> Decimal:
        remain = need
        total = Decimal(0)
        taken = Decimal(0)
        while remain > 0 and consumed:
            lot = consumed[-1]
            lot_qty = Decimal(str(lot.get("qty") or 0))
            lot_cost = Decimal(str(lot.get("cost") or 0))
            if lot_qty <= 0:
                consumed.pop()
                continue
            take = min(remain, lot_qty)
            total += take * lot_cost
            taken += take
            lot["qty"] = lot_qty - take
            remain -= take
            if lot["qty"] <= 0:
                consumed.pop()
        if taken <= 0:
            if wma:
                return _wac()
            if layers:
                return Decimal(str(layers[0].get("cost") or 0))
            return Decimal(0)
        if remain > 0:
            fill = _wac() if wma else (
                Decimal(str(layers[0].get("cost") or 0)) if layers else Decimal(0)
            )
            total += remain * fill
            taken += remain
        return total / taken if taken else Decimal(0)

    for mv in sorted_mvs:
        qty = _d(mv.get("quantity"))
        if qty <= 0:
            continue
        mtype = mv.get("movement")
        dtype = str(mv.get("document_type") or "")
        raw_cost = mv.get("cost_price")

        if mtype == "in":
            if dtype == INVOICE_SALES_RETURN and raw_cost is None:
                unit = _restore_from_consumed(qty)
                mv["cost_price"] = unit
                raw_cost = unit
            unit_cost = _d(raw_cost)
            if wma:
                new_q = q + qty
                new_v = v + qty * unit_cost
                last_wac = (new_v / new_q) if new_q > 0 else last_wac
                q, v = new_q, new_v
            layer = {"qty": qty, "cost": unit_cost}
            if reverse:
                layers.appendleft(layer)
            else:
                layers.append(layer)
            continue

        if mtype != "out":
            continue

        if wma:
            wac = _wac()
            consumed.append({"qty": qty, "cost": wac})
            cogs = qty * wac
            q = q - qty
            v = v - cogs
            last_wac = wac
            remain_layers = qty
            while remain_layers > 0 and layers:
                top = layers[0]
                take = min(remain_layers, Decimal(str(top.get("qty") or 0)))
                top["qty"] = Decimal(str(top.get("qty") or 0)) - take
                remain_layers -= take
                if top["qty"] <= 0:
                    layers.popleft()
            continue

        remain = qty
        while remain > 0 and layers:
            top = layers[0]
            layer_qty = Decimal(str(top.get("qty") or 0))
            if layer_qty <= 0:
                layers.popleft()
                continue
            take = min(remain, layer_qty)
            consumed.append({"qty": take, "cost": Decimal(str(top.get("cost") or 0))})
            top["qty"] = layer_qty - take
            remain -= take
            if top["qty"] <= 0:
                layers.popleft()
