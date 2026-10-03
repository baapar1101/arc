from __future__ import annotations

from decimal import Decimal
from typing import Any

from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session, selectinload

from adapters.api.v1.schema_models.product_bundle import (
    ProductBundleCreateRequest,
    ProductBundleItemRequest,
    ProductBundleUpdateRequest,
)
from adapters.db.models.product import Product, ProductItemType
from adapters.db.models.product_bundle import ProductBundle, ProductBundleItem
from app.core.responses import ApiError

_SORT_COLUMNS = {
    "id": ProductBundle.id,
    "name": ProductBundle.name,
    "is_active": ProductBundle.is_active,
    "created_at": ProductBundle.created_at,
    "updated_at": ProductBundle.updated_at,
}


def _item_type_value(product: Product) -> str:
    value = product.item_type
    return value.value if hasattr(value, "value") else str(value)


def _validate_items(
    db: Session,
    business_id: int,
    items: list[ProductBundleItemRequest],
    *,
    require_active: bool,
) -> dict[int, Product]:
    product_ids = [int(item.product_id) for item in items]
    if len(product_ids) != len(set(product_ids)):
        raise ApiError(
            "DUPLICATE_BUNDLE_PRODUCT",
            "هر کالا فقط یک بار می‌تواند در یک باندل قرار بگیرد.",
            http_status=400,
        )

    products = db.query(Product).filter(Product.id.in_(product_ids)).all()
    by_id = {int(product.id): product for product in products}
    missing = [product_id for product_id in product_ids if product_id not in by_id]
    if missing:
        raise ApiError(
            "BUNDLE_PRODUCT_NOT_FOUND",
            "یک یا چند کالای انتخاب‌شده یافت نشد.",
            http_status=400,
            details={"product_ids": missing},
        )

    wrong_business = [
        product.id for product in products if int(product.business_id) != int(business_id)
    ]
    if wrong_business:
        raise ApiError(
            "BUNDLE_PRODUCT_NOT_FOUND",
            "یک یا چند کالای انتخاب‌شده متعلق به این کسب‌وکار نیست.",
            http_status=400,
        )

    services = [
        product.name
        for product in products
        if _item_type_value(product) != ProductItemType.PRODUCT.value
    ]
    if services:
        raise ApiError(
            "BUNDLE_PRODUCTS_ONLY",
            "باندل فقط می‌تواند شامل کالا باشد؛ خدمت مجاز نیست.",
            http_status=400,
            details={"products": services},
        )

    if require_active:
        inactive = [product.name for product in products if not bool(product.is_active)]
        if inactive:
            raise ApiError(
                "BUNDLE_PRODUCT_INACTIVE",
                "باندل شامل کالای غیرفعال است و قابل افزودن به فاکتور نیست.",
                http_status=409,
                details={"products": inactive},
            )

    return by_id


def _ensure_name_available(
    db: Session,
    business_id: int,
    name: str,
    *,
    exclude_bundle_id: int | None = None,
) -> None:
    query = db.query(ProductBundle.id).filter(
        ProductBundle.business_id == business_id,
        func.lower(ProductBundle.name) == name.strip().lower(),
    )
    if exclude_bundle_id is not None:
        query = query.filter(ProductBundle.id != exclude_bundle_id)
    if query.first() is not None:
        raise ApiError("DUPLICATE_BUNDLE_NAME", "نام باندل تکراری است.", http_status=400)


def _product_dict(product: Product) -> dict[str, Any]:
    return {
        "id": product.id,
        "code": product.code,
        "name": product.name,
        "description": product.description,
        "item_type": _item_type_value(product),
        "is_active": bool(product.is_active),
        "main_unit": product.main_unit,
        "secondary_unit": product.secondary_unit,
        "unit_conversion_factor": product.unit_conversion_factor,
        "base_sales_price": product.base_sales_price,
        "base_sales_note": product.base_sales_note,
        "sales_price_fx": product.sales_price_fx,
        "price_fx_currency_id": product.price_fx_currency_id,
        "is_sales_taxable": bool(product.is_sales_taxable),
        "sales_tax_rate": product.sales_tax_rate,
        "track_inventory": bool(product.track_inventory),
        "inventory_mode": product.inventory_mode,
        "default_warehouse_id": product.default_warehouse_id,
        "min_order_qty": product.min_order_qty,
    }


def to_dict(bundle: ProductBundle, *, include_items: bool = True) -> dict[str, Any]:
    result: dict[str, Any] = {
        "id": bundle.id,
        "business_id": bundle.business_id,
        "name": bundle.name,
        "description": bundle.description,
        "is_active": bool(bundle.is_active),
        "items_count": len(bundle.items),
        "created_at": bundle.created_at,
        "updated_at": bundle.updated_at,
    }
    if include_items:
        result["items"] = [
            {
                "id": item.id,
                "product_id": item.product_id,
                "quantity": item.quantity,
                "line_order": item.line_order,
                "product": _product_dict(item.product),
            }
            for item in bundle.items
        ]
    return result


def _get_bundle(db: Session, business_id: int, bundle_id: int) -> ProductBundle | None:
    return db.scalar(
        select(ProductBundle)
        .options(selectinload(ProductBundle.items).selectinload(ProductBundleItem.product))
        .where(ProductBundle.id == bundle_id, ProductBundle.business_id == business_id)
    )


def search_bundles(db: Session, business_id: int, query: dict[str, Any]) -> dict[str, Any]:
    stmt = (
        select(ProductBundle)
        .options(selectinload(ProductBundle.items).selectinload(ProductBundleItem.product))
        .where(ProductBundle.business_id == business_id)
    )
    count_stmt = select(func.count(ProductBundle.id)).where(
        ProductBundle.business_id == business_id
    )

    search = str(query.get("search") or "").strip()
    if search:
        predicate = or_(
            ProductBundle.name.ilike(f"%{search}%"), ProductBundle.description.ilike(f"%{search}%")
        )
        stmt = stmt.where(predicate)
        count_stmt = count_stmt.where(predicate)

    for raw_filter in query.get("filters") or []:
        prop = (
            raw_filter.get("property")
            if isinstance(raw_filter, dict)
            else getattr(raw_filter, "property", None)
        )
        value = (
            raw_filter.get("value")
            if isinstance(raw_filter, dict)
            else getattr(raw_filter, "value", None)
        )
        if prop == "is_active" and value is not None:
            active = (
                value
                if isinstance(value, bool)
                else str(value).strip().lower() in {"1", "true", "yes"}
            )
            stmt = stmt.where(ProductBundle.is_active == active)
            count_stmt = count_stmt.where(ProductBundle.is_active == active)

    total = int(db.scalar(count_stmt) or 0)
    take = max(1, min(int(query.get("take") or 20), 100))
    skip = max(0, int(query.get("skip") or 0))
    sort_column = _SORT_COLUMNS.get(
        str(query.get("sort_by") or "updated_at"), ProductBundle.updated_at
    )
    sort_desc = bool(query.get("sort_desc", True))
    stmt = stmt.order_by(
        sort_column.desc() if sort_desc else sort_column.asc(), ProductBundle.id.desc()
    )
    rows = list(db.scalars(stmt.offset(skip).limit(take)).unique().all())
    page = (skip // take) + 1
    total_pages = (total + take - 1) // take if total else 0
    return {
        "items": [to_dict(row, include_items=False) for row in rows],
        "pagination": {
            "total": total,
            "page": page,
            "per_page": take,
            "total_pages": total_pages,
        },
    }


def get_bundle(db: Session, business_id: int, bundle_id: int) -> dict[str, Any] | None:
    bundle = _get_bundle(db, business_id, bundle_id)
    return to_dict(bundle) if bundle is not None else None


def create_bundle(
    db: Session,
    business_id: int,
    payload: ProductBundleCreateRequest,
) -> dict[str, Any]:
    _validate_items(db, business_id, payload.items, require_active=False)
    _ensure_name_available(db, business_id, payload.name)
    bundle = ProductBundle(
        business_id=business_id,
        name=payload.name,
        description=payload.description.strip()
        if payload.description and payload.description.strip()
        else None,
        is_active=payload.is_active,
    )
    for index, item in enumerate(payload.items, start=1):
        bundle.items.append(
            ProductBundleItem(product_id=item.product_id, quantity=item.quantity, line_order=index)
        )
    db.add(bundle)
    db.commit()
    created = _get_bundle(db, business_id, bundle.id)
    if created is None:
        raise ApiError("BUNDLE_NOT_FOUND", "باندل پس از ایجاد یافت نشد.", http_status=500)
    return to_dict(created)


def update_bundle(
    db: Session,
    business_id: int,
    bundle_id: int,
    payload: ProductBundleUpdateRequest,
) -> dict[str, Any] | None:
    bundle = _get_bundle(db, business_id, bundle_id)
    if bundle is None:
        return None
    fields = payload.model_fields_set
    if "name" in fields and payload.name is not None:
        _ensure_name_available(db, business_id, payload.name, exclude_bundle_id=bundle_id)
        bundle.name = payload.name
    if "description" in fields:
        bundle.description = (
            payload.description.strip()
            if payload.description and payload.description.strip()
            else None
        )
    if "is_active" in fields and payload.is_active is not None:
        bundle.is_active = payload.is_active
    if "items" in fields and payload.items is not None:
        _validate_items(db, business_id, payload.items, require_active=False)
        bundle.items.clear()
        db.flush()
        for index, item in enumerate(payload.items, start=1):
            bundle.items.append(
                ProductBundleItem(
                    product_id=item.product_id, quantity=item.quantity, line_order=index
                )
            )
    db.commit()
    updated = _get_bundle(db, business_id, bundle_id)
    if updated is None:
        raise ApiError("BUNDLE_NOT_FOUND", "باندل پس از ویرایش یافت نشد.", http_status=500)
    return to_dict(updated)


def delete_bundle(db: Session, business_id: int, bundle_id: int) -> bool:
    bundle = _get_bundle(db, business_id, bundle_id)
    if bundle is None:
        return False
    db.delete(bundle)
    db.commit()
    return True


def expand_bundle(
    db: Session,
    business_id: int,
    bundle_id: int,
    quantity: Decimal,
) -> dict[str, Any]:
    bundle = _get_bundle(db, business_id, bundle_id)
    if bundle is None:
        raise ApiError("BUNDLE_NOT_FOUND", "باندل یافت نشد.", http_status=404)
    if not bundle.is_active:
        raise ApiError("BUNDLE_INACTIVE", "باندل غیرفعال است.", http_status=409)
    item_requests = [
        ProductBundleItemRequest(product_id=item.product_id, quantity=item.quantity)
        for item in bundle.items
    ]
    _validate_items(db, business_id, item_requests, require_active=True)
    multiplier = Decimal(str(quantity))
    return {
        "bundle_id": bundle.id,
        "quantity": multiplier,
        "items": [
            {
                "product_id": item.product_id,
                "quantity": Decimal(str(item.quantity)) * multiplier,
                "line_order": item.line_order,
                "product": _product_dict(item.product),
            }
            for item in bundle.items
        ],
    }
