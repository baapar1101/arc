from __future__ import annotations

from typing import Any, Dict, List, Optional

from decimal import Decimal
from sqlalchemy.orm import Session

from adapters.db.models.product import Product
from adapters.db.models.price_list import PriceItem, PriceList
from adapters.db.models.currency import Currency
from adapters.api.v1.schema_models.product import (
    BulkProductPriceSheetApplyRequest,
    BulkProductPriceSheetItemsRequest,
)


def _quantize_non_negative_integer(value: Decimal) -> Decimal:
    quantized = value.quantize(Decimal("1"))
    if quantized < 0:
        return Decimal("0")
    return quantized


def list_bulk_price_sheet_items(
    db: Session, business_id: int, payload: BulkProductPriceSheetItemsRequest
) -> Dict[str, Any]:
    """لیست PriceItemها برای کالاهای داده‌شده و لیست‌های قیمت انتخابی."""
    q = (
        db.query(PriceItem, PriceList.name, Currency.code)
        .join(PriceList, PriceList.id == PriceItem.price_list_id)
        .outerjoin(Currency, Currency.id == PriceItem.currency_id)
        .filter(
            PriceList.business_id == business_id,
            PriceItem.product_id.in_(payload.product_ids),
            PriceItem.price_list_id.in_(payload.price_list_ids),
        )
        .order_by(PriceList.name, Currency.code, PriceItem.tier_name, PriceItem.product_id)
    )
    rows: List[Dict[str, Any]] = []
    for pi, pl_name, cur_code in q.all():
        rows.append(
            {
                "price_item_id": pi.id,
                "product_id": pi.product_id,
                "price_list_id": pi.price_list_id,
                "price_list_name": pl_name or "",
                "currency_id": pi.currency_id,
                "currency_code": cur_code or "",
                "tier_name": pi.tier_name or "",
                "price": pi.price,
            }
        )
    return {"items": rows}


def apply_bulk_product_price_sheet(
    db: Session, business_id: int, payload: BulkProductPriceSheetApplyRequest
) -> Dict[str, Any]:
    """به‌روزرسانی دسته‌ای قیمت پایه و ردیف‌های لیست قیمت."""
    updated_products = 0
    updated_price_items = 0
    errors: List[str] = []

    for row in payload.items:
        try:
            product = db.get(Product, row.product_id)
            if not product or product.business_id != business_id:
                errors.append(f"کالا یافت نشد: {row.product_id}")
                continue

            product_touched = False

            if row.clear_base_sales_price:
                product.base_sales_price = None
                product_touched = True
            elif row.base_sales_price is not None:
                product.base_sales_price = _quantize_non_negative_integer(Decimal(row.base_sales_price))
                product_touched = True

            if row.clear_base_purchase_price:
                product.base_purchase_price = None
                product_touched = True
            elif row.base_purchase_price is not None:
                product.base_purchase_price = _quantize_non_negative_integer(Decimal(row.base_purchase_price))
                product_touched = True

            for piu in row.price_item_updates:
                pi = db.get(PriceItem, piu.price_item_id)
                if not pi:
                    errors.append(f"ردیف لیست قیمت یافت نشد: {piu.price_item_id}")
                    continue
                if pi.product_id != row.product_id:
                    errors.append(f"ردیف {piu.price_item_id} متعلق به کالای دیگری است")
                    continue
                pl = db.get(PriceList, pi.price_list_id)
                if not pl or pl.business_id != business_id:
                    errors.append(f"لیست قیمت نامعتبر برای ردیف {piu.price_item_id}")
                    continue
                pi.price = _quantize_non_negative_integer(Decimal(piu.price))
                updated_price_items += 1
                product_touched = True

            if product_touched:
                updated_products += 1

        except Exception as e:  # noqa: BLE001
            errors.append(f"خطا در کالای {row.product_id}: {e!s}")

    db.commit()

    msg = f"{updated_products} کالا به‌روز شد"
    if updated_price_items:
        msg += f" ({updated_price_items} ردیف لیست قیمت)"

    return {
        "message": msg,
        "updated_count": updated_products,
        "updated_price_items": updated_price_items,
        "errors": errors,
    }
