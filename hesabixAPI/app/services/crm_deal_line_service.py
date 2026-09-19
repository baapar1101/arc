# noqa: D100
"""سرویس خطوط فرصت فروش: لیست/جایگزینی خطوط و محاسبه مجدد مبلغ معامله."""
from __future__ import annotations

from decimal import Decimal, ROUND_HALF_UP
from typing import Any, Dict, List, Optional

from sqlalchemy import and_
from sqlalchemy.orm import Session

from adapters.db.models.crm import CrmDealLine, Deal
from adapters.db.models.product import Product
from app.core.responses import ApiError

_TWO = Decimal("0.01")


def line_to_dict(ln: CrmDealLine) -> Dict[str, Any]:
    return {
        "id": ln.id,
        "deal_id": ln.deal_id,
        "product_id": ln.product_id,
        "description": ln.description,
        "quantity": float(ln.quantity or 0),
        "unit_price": float(ln.unit_price or 0),
        "discount_percent": float(ln.discount_percent or 0),
        "line_total": float(ln.line_total or 0),
        "sort_order": ln.sort_order,
    }


def _compute_line_total(quantity: Decimal, unit_price: Decimal, discount_percent: Decimal) -> Decimal:
    gross = quantity * unit_price
    discount = gross * (discount_percent / Decimal(100)) if discount_percent else Decimal(0)
    total = gross - discount
    return total.quantize(_TWO, rounding=ROUND_HALF_UP)


def list_lines(db: Session, business_id: int, deal_id: int) -> List[Dict[str, Any]]:
    deal = _get_deal(db, business_id, deal_id)
    rows = (
        db.query(CrmDealLine)
        .filter(CrmDealLine.deal_id == deal.id)
        .order_by(CrmDealLine.sort_order, CrmDealLine.id)
        .all()
    )
    return [line_to_dict(r) for r in rows]


def _get_deal(db: Session, business_id: int, deal_id: int) -> Deal:
    deal = (
        db.query(Deal)
        .filter(and_(Deal.id == deal_id, Deal.business_id == business_id))
        .first()
    )
    if not deal:
        raise ApiError("NOT_FOUND", "فرصت فروش یافت نشد.", http_status=404)
    return deal


def replace_lines(
    db: Session,
    business_id: int,
    deal_id: int,
    lines: List[Dict[str, Any]],
    *,
    recompute_amount: bool = True,
) -> Dict[str, Any]:
    """همه خطوط معامله را جایگزین می‌کند و در صورت وجود خطوط، مبلغ معامله را بازمحاسبه می‌کند."""
    deal = _get_deal(db, business_id, deal_id)

    # اعتبارسنجی product_idها
    product_ids = [int(l["product_id"]) for l in (lines or []) if l.get("product_id")]
    valid_products: set[int] = set()
    if product_ids:
        valid_products = {
            p.id
            for p in db.query(Product.id)
            .filter(Product.business_id == business_id, Product.id.in_(product_ids))
            .all()
        }
        missing = [p for p in product_ids if p not in valid_products]
        if missing:
            raise ApiError("CRM_DEAL_LINE_PRODUCT_NOT_FOUND", f"کالا(های) نامعتبر: {missing}", http_status=400)

    db.query(CrmDealLine).filter(CrmDealLine.deal_id == deal.id).delete(synchronize_session=False)

    total_sum = Decimal(0)
    for i, l in enumerate(lines or []):
        product_id = int(l["product_id"]) if l.get("product_id") else None
        description = (l.get("description") or None)
        if not product_id and not description:
            raise ApiError(
                "CRM_DEAL_LINE_INVALID",
                "هر خط باید product_id یا description داشته باشد.",
                http_status=400,
            )
        try:
            quantity = Decimal(str(l.get("quantity", 0) or 0))
            unit_price = Decimal(str(l.get("unit_price", 0) or 0))
            discount_percent = Decimal(str(l.get("discount_percent", 0) or 0))
        except (TypeError, ValueError):
            raise ApiError("CRM_DEAL_LINE_INVALID", "مقادیر عددی خط نامعتبر است.", http_status=400)
        if quantity <= 0:
            raise ApiError("CRM_DEAL_LINE_INVALID", "تعداد باید بزرگ‌تر از صفر باشد.", http_status=400)
        line_total = _compute_line_total(quantity, unit_price, discount_percent)
        total_sum += line_total
        db.add(
            CrmDealLine(
                business_id=business_id,
                deal_id=deal.id,
                product_id=product_id,
                description=description,
                quantity=quantity,
                unit_price=unit_price,
                discount_percent=discount_percent,
                line_total=line_total,
                sort_order=l.get("sort_order", i),
            )
        )

    if recompute_amount and (lines or []):
        deal.amount = total_sum
    db.flush()
    return {
        "lines": list_lines(db, business_id, deal_id),
        "amount": float(deal.amount or 0),
    }
