from __future__ import annotations

from typing import Dict, Any, List, Optional
from decimal import Decimal
from collections import defaultdict

from sqlalchemy.orm import Session
from sqlalchemy import or_

from adapters.db.models.product import Product
from adapters.db.models.price_list import PriceItem, PriceList
from adapters.db.models.category import BusinessCategory
from adapters.api.v1.schema_models.product import (
    BulkPriceUpdateRequest,
    BulkPriceUpdatePreview,
    BulkPriceUpdatePreviewResponse,
    BulkPriceUpdateType,
    BulkPriceUpdateTarget,
    BulkPriceUpdateDirection,
    BulkPriceUpdateScope,
    BulkPriceListItemPreview,
)


def _quantize_non_negative_integer(value: Decimal) -> Decimal:
    """رُند کردن به عدد صحیح غیرمنفی (بدون اعشار)."""
    quantized = value.quantize(Decimal("1"))
    if quantized < 0:
        return Decimal("0")
    return quantized


def _quantize_integer_keep_sign(value: Decimal) -> Decimal:
    """رُند کردن به عدد صحیح با حفظ علامت (بدون اعشار)."""
    return value.quantize(Decimal("1"))


def calculate_new_price(
    current_price: Optional[Decimal],
    update_type: BulkPriceUpdateType,
    direction: BulkPriceUpdateDirection,
    value: Decimal,
) -> Optional[Decimal]:
    """محاسبه قیمت جدید بر اساس نوع تغییر با جهت، سپس رُند و کلَمپ به صفر"""
    if current_price is None:
        return None

    if update_type == BulkPriceUpdateType.PERCENTAGE:
        sign = Decimal("1") if direction == BulkPriceUpdateDirection.INCREASE else Decimal("-1")
        multiplier = Decimal("1") + (sign * (value / Decimal("100")))
        new_value = current_price * multiplier
    else:
        sign = Decimal("1") if direction == BulkPriceUpdateDirection.INCREASE else Decimal("-1")
        new_value = current_price + (sign * value)

    return _quantize_non_negative_integer(new_value)


def _scope_includes_base(request: BulkPriceUpdateRequest) -> bool:
    return request.update_scope in (BulkPriceUpdateScope.BASE_PRICES, BulkPriceUpdateScope.BOTH)


def _scope_includes_lists(request: BulkPriceUpdateRequest) -> bool:
    return request.update_scope in (BulkPriceUpdateScope.PRICE_LIST_ITEMS, BulkPriceUpdateScope.BOTH)


def _affects_price_list_items(request: BulkPriceUpdateRequest) -> bool:
    """آیتم لیست قیمت فقط با هدف فروش (یا هر دو) معنی دارد؛ فیلد واحد price دارد."""
    if not _scope_includes_lists(request):
        return False
    if request.target == BulkPriceUpdateTarget.PURCHASE_PRICE:
        return False
    return request.target in (BulkPriceUpdateTarget.SALES_PRICE, BulkPriceUpdateTarget.BOTH)


def _apply_price_item_filters(q, request: BulkPriceUpdateRequest):
    if request.currency_ids:
        q = q.filter(PriceItem.currency_id.in_(request.currency_ids))
    if request.price_list_ids:
        q = q.filter(PriceItem.price_list_id.in_(request.price_list_ids))
    return q


def get_filtered_products(db: Session, business_id: int, request: BulkPriceUpdateRequest) -> List[Product]:
    """دریافت کالاهای فیلتر شده بر اساس معیارهای درخواست"""
    query = db.query(Product).filter(Product.business_id == business_id)

    if request.category_ids:
        query = query.filter(Product.category_id.in_(request.category_ids))

    if request.item_types:
        query = query.filter(Product.item_type.in_([t.value for t in request.item_types]))

    if request.currency_ids:
        query = query.filter(
            db.query(PriceItem.id)
            .filter(
                PriceItem.product_id == Product.id,
                PriceItem.currency_id.in_(request.currency_ids),
            )
            .exists()
        )

    if request.price_list_ids:
        query = query.filter(
            db.query(PriceItem.id)
            .filter(
                PriceItem.product_id == Product.id,
                PriceItem.price_list_id.in_(request.price_list_ids),
            )
            .exists()
        )

    if request.product_ids:
        query = query.filter(Product.id.in_(request.product_ids))

    if request.only_products_with_inventory is not None:
        if request.only_products_with_inventory:
            query = query.filter(Product.track_inventory == True)
        else:
            query = query.filter(Product.track_inventory == False)

    if request.only_products_with_base_price and _scope_includes_base(request):
        if request.target == BulkPriceUpdateTarget.SALES_PRICE:
            query = query.filter(Product.base_sales_price.isnot(None))
        elif request.target == BulkPriceUpdateTarget.PURCHASE_PRICE:
            query = query.filter(Product.base_purchase_price.isnot(None))
        else:
            query = query.filter(
                or_(Product.base_sales_price.isnot(None), Product.base_purchase_price.isnot(None))
            )

    if _scope_includes_lists(request) and not _scope_includes_base(request):
        sub = (
            db.query(PriceItem.id)
            .join(PriceList, PriceList.id == PriceItem.price_list_id)
            .filter(
                PriceItem.product_id == Product.id,
                PriceList.business_id == business_id,
            )
        )
        if request.currency_ids:
            sub = sub.filter(PriceItem.currency_id.in_(request.currency_ids))
        if request.price_list_ids:
            sub = sub.filter(PriceItem.price_list_id.in_(request.price_list_ids))
        query = query.filter(sub.exists())

    return query.all()


def preview_bulk_price_update(
    db: Session, business_id: int, request: BulkPriceUpdateRequest
) -> BulkPriceUpdatePreviewResponse:
    """پیش‌نمایش تغییرات قیمت گروهی (قیمت پایه و در صورت نیاز آیتم‌های لیست قیمت)"""
    products = get_filtered_products(db, business_id, request)

    category_titles: Dict[int, str] = {}

    def _resolve_category_name(cid: Optional[int]) -> Optional[str]:
        if cid is None:
            return None
        if cid in category_titles:
            return category_titles[cid]
        try:
            cat = (
                db.query(BusinessCategory)
                .filter(BusinessCategory.id == cid, BusinessCategory.business_id == business_id)
                .first()
            )
            if cat and isinstance(cat.title_translations, dict):
                title = cat.title_translations.get("fa") or cat.title_translations.get("default") or ""
                category_titles[cid] = title
                return title
        except Exception:
            return None
        return None

    price_list_names = {pl.id: pl.name for pl in db.query(PriceList).filter(PriceList.business_id == business_id).all()}

    product_ids = [p.id for p in products]
    items_by_product: Dict[int, List[PriceItem]] = defaultdict(list)
    if product_ids and _affects_price_list_items(request):
        q_items = (
            db.query(PriceItem)
            .join(PriceList, PriceList.id == PriceItem.price_list_id)
            .filter(PriceList.business_id == business_id, PriceItem.product_id.in_(product_ids))
        )
        q_items = _apply_price_item_filters(q_items, request)
        for pi in q_items.all():
            items_by_product[pi.product_id].append(pi)

    affected_products: List[BulkPriceUpdatePreview] = []
    total_sales_change = Decimal("0")
    total_purchase_change = Decimal("0")
    total_list_change = Decimal("0")
    products_with_sales_change = 0
    products_with_purchase_change = 0
    price_list_rows_changed = 0

    for product in products:
        preview = BulkPriceUpdatePreview(
            product_id=product.id,
            product_name=product.name or "بدون نام",
            product_code=product.code or "بدون کد",
            category_name=_resolve_category_name(product.category_id),
            current_sales_price=product.base_sales_price,
            current_purchase_price=product.base_purchase_price,
            new_sales_price=None,
            new_purchase_price=None,
            sales_price_change=None,
            purchase_price_change=None,
            price_list_items=[],
        )

        if _scope_includes_base(request):
            if (
                request.target in [BulkPriceUpdateTarget.SALES_PRICE, BulkPriceUpdateTarget.BOTH]
                and product.base_sales_price is not None
            ):
                new_sales_price = calculate_new_price(
                    product.base_sales_price, request.update_type, request.direction, request.value
                )
                preview.new_sales_price = new_sales_price
                preview.sales_price_change = (
                    (new_sales_price - product.base_sales_price) if new_sales_price is not None else None
                )
                total_sales_change += preview.sales_price_change or Decimal("0")
                products_with_sales_change += 1

            if (
                request.target in [BulkPriceUpdateTarget.PURCHASE_PRICE, BulkPriceUpdateTarget.BOTH]
                and product.base_purchase_price is not None
            ):
                new_purchase_price = calculate_new_price(
                    product.base_purchase_price, request.update_type, request.direction, request.value
                )
                preview.new_purchase_price = new_purchase_price
                preview.purchase_price_change = (
                    (new_purchase_price - product.base_purchase_price) if new_purchase_price is not None else None
                )
                total_purchase_change += preview.purchase_price_change or Decimal("0")
                products_with_purchase_change += 1

        if _affects_price_list_items(request):
            for pi in items_by_product.get(product.id, []):
                cur = Decimal(pi.price)
                new_pi = calculate_new_price(cur, request.update_type, request.direction, request.value)
                if new_pi is None:
                    continue
                ch = new_pi - cur
                preview.price_list_items.append(
                    BulkPriceListItemPreview(
                        price_item_id=pi.id,
                        price_list_id=pi.price_list_id,
                        price_list_name=price_list_names.get(pi.price_list_id),
                        currency_id=pi.currency_id,
                        tier_name=pi.tier_name or "",
                        current_price=cur,
                        new_price=new_pi,
                        price_change=ch,
                    )
                )
                total_list_change += ch
                price_list_rows_changed += 1

        affected_products.append(preview)

    summary = {
        "total_products": len(products),
        "affected_products": len(affected_products),
        "products_with_sales_change": products_with_sales_change,
        "products_with_purchase_change": products_with_purchase_change,
        "price_list_items_changed": price_list_rows_changed,
        "total_sales_change": float(_quantize_integer_keep_sign(total_sales_change)),
        "total_purchase_change": float(_quantize_integer_keep_sign(total_purchase_change)),
        "total_price_list_change": float(_quantize_integer_keep_sign(total_list_change)),
        "update_type": request.update_type.value,
        "direction": request.direction.value,
        "target": request.target.value,
        "update_scope": request.update_scope.value,
        "value": float(_quantize_non_negative_integer(request.value))
        if request.update_type == BulkPriceUpdateType.AMOUNT
        else float(request.value),
    }

    return BulkPriceUpdatePreviewResponse(
        total_products=len(products),
        affected_products=affected_products,
        summary=summary,
    )


def apply_bulk_price_update(db: Session, business_id: int, request: BulkPriceUpdateRequest) -> Dict[str, Any]:
    """اعمال تغییرات قیمت گروهی روی قیمت پایه و/ یا آیتم‌های لیست قیمت"""
    products = get_filtered_products(db, business_id, request)

    updated_count = 0
    errors: List[str] = []

    for product in products:
        try:
            if _scope_includes_base(request):
                if (
                    request.target in [BulkPriceUpdateTarget.SALES_PRICE, BulkPriceUpdateTarget.BOTH]
                    and product.base_sales_price is not None
                ):
                    product.base_sales_price = calculate_new_price(
                        product.base_sales_price, request.update_type, request.direction, request.value
                    )

                if (
                    request.target in [BulkPriceUpdateTarget.PURCHASE_PRICE, BulkPriceUpdateTarget.BOTH]
                    and product.base_purchase_price is not None
                ):
                    product.base_purchase_price = calculate_new_price(
                        product.base_purchase_price, request.update_type, request.direction, request.value
                    )

            if _affects_price_list_items(request):
                q = (
                    db.query(PriceItem)
                    .join(PriceList, PriceList.id == PriceItem.price_list_id)
                    .filter(PriceList.business_id == business_id, PriceItem.product_id == product.id)
                )
                q = _apply_price_item_filters(q, request)
                for pi in q.all():
                    new_pi_price = calculate_new_price(
                        Decimal(pi.price), request.update_type, request.direction, request.value
                    )
                    if new_pi_price is not None:
                        pi.price = new_pi_price

            updated_count += 1

        except Exception as e:  # noqa: BLE001
            errors.append(f"خطا در بروزرسانی کالای {product.name}: {str(e)}")

    db.commit()

    return {
        "message": f"تغییرات قیمت برای {updated_count} کالا اعمال شد",
        "updated_count": updated_count,
        "total_products": len(products),
        "errors": errors,
    }
