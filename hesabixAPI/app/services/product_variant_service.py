"""CRUD ابعاد و ترکیب‌های کالای فله‌ای. سقف دو بُعد Policy است نه Schema."""

from __future__ import annotations

from decimal import Decimal
from typing import Any, Dict, Iterable, List, Optional, Sequence

from sqlalchemy import and_, func, or_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from adapters.db.models.product import Product
from adapters.db.models.product_attribute import ProductAttribute
from adapters.db.models.product_attribute_link import ProductAttributeLink
from adapters.db.models.product_attribute_option import ProductAttributeOption
from adapters.db.models.product_variant import (
    ProductVariant,
    ProductVariantDimension,
    ProductVariantValue,
)
from adapters.db.models.product_variant_allocation import (
    InvoiceItemLineVariantAllocation,
    WarehouseLineVariantAllocation,
)
from adapters.db.models.warehouse_document import WarehouseDocument
from adapters.db.models.warehouse_document_line import WarehouseDocumentLine
from app.core.responses import ApiError
from app.services.product_attribute_option_service import ensure_options_for_attribute, get_option
from app.services.product_general_barcode_service import (
    assert_tokens_not_used_by_unique_instances,
    assert_tokens_unique_among_products,
)

MAX_VARIANT_DIMENSIONS = 2
MAX_VARIANTS_PER_PRODUCT = 100
VARIANT_MODE_NONE = "none"
VARIANT_MODE_INVENTORY = "inventory"


def is_variant_inventory_product(product: Product | None) -> bool:
    if product is None:
        return False
    return str(getattr(product, "variant_mode", None) or VARIANT_MODE_NONE) == VARIANT_MODE_INVENTORY


def build_combination_key(pairs: Sequence[tuple[int, int]]) -> str:
    ordered = sorted({(int(attr_id), int(option_id)) for attr_id, option_id in pairs}, key=lambda x: x[0])
    return "|".join(f"{attr_id}:{option_id}" for attr_id, option_id in ordered)


def _load_product(db: Session, business_id: int, product_id: int) -> Product:
    product = (
        db.query(Product)
        .filter(Product.id == int(product_id), Product.business_id == int(business_id))
        .first()
    )
    if not product:
        raise ApiError("PRODUCT_NOT_FOUND", "کالا یافت نشد", http_status=404)
    return product


def _assert_bulk_product(product: Product) -> None:
    mode = str(product.inventory_mode or "bulk")
    if mode == "unique":
        raise ApiError(
            "VARIANT_UNIQUE_NOT_SUPPORTED",
            "تفکیک موجودی ویژگی برای کالای یونیک در این نسخه پشتیبانی نمی‌شود",
            http_status=422,
        )


def list_dimensions(db: Session, business_id: int, product_id: int) -> List[ProductVariantDimension]:
    return (
        db.query(ProductVariantDimension)
        .filter(
            ProductVariantDimension.business_id == int(business_id),
            ProductVariantDimension.product_id == int(product_id),
        )
        .order_by(ProductVariantDimension.sort_order.asc(), ProductVariantDimension.id.asc())
        .all()
    )


def product_has_variant_movement(db: Session, business_id: int, product_id: int) -> bool:
    wh_hit = (
        db.query(WarehouseLineVariantAllocation.id)
        .join(
            WarehouseDocumentLine,
            WarehouseDocumentLine.id == WarehouseLineVariantAllocation.warehouse_document_line_id,
        )
        .join(WarehouseDocument, WarehouseDocument.id == WarehouseDocumentLine.warehouse_document_id)
        .filter(
            WarehouseLineVariantAllocation.business_id == int(business_id),
            WarehouseLineVariantAllocation.product_id == int(product_id),
            WarehouseDocument.status == "posted",
        )
        .first()
    )
    if wh_hit:
        return True
    inv_hit = (
        db.query(InvoiceItemLineVariantAllocation.id)
        .filter(
            InvoiceItemLineVariantAllocation.business_id == int(business_id),
            InvoiceItemLineVariantAllocation.product_id == int(product_id),
        )
        .first()
    )
    return inv_hit is not None


def _serialize_dimension(row: ProductVariantDimension) -> Dict[str, Any]:
    return {
        "id": int(row.id),
        "product_id": int(row.product_id),
        "attribute_id": int(row.attribute_id),
        "is_required": bool(row.is_required),
        "sort_order": int(row.sort_order or 0),
    }


def replace_dimensions(
    db: Session,
    business_id: int,
    product_id: int,
    dimensions: Sequence[Dict[str, Any]],
) -> List[Dict[str, Any]]:
    product = _load_product(db, business_id, product_id)
    _assert_bulk_product(product)
    if product_has_variant_movement(db, business_id, product_id):
        raise ApiError(
            "VARIANT_DIMENSION_IN_USE",
            "پس از گردش Variantدار، حذف یا جایگزینی ابعاد مجاز نیست",
            http_status=409,
        )
    if len(dimensions) > MAX_VARIANT_DIMENSIONS:
        raise ApiError(
            "VARIANT_DIMENSION_LIMIT",
            f"در نسخه اول حداکثر {MAX_VARIANT_DIMENSIONS} ویژگی انباری مجاز است",
            http_status=422,
        )

    seen_attr: set[int] = set()
    normalized: List[Dict[str, Any]] = []
    for idx, item in enumerate(dimensions):
        try:
            attribute_id = int(item.get("attribute_id"))
        except (TypeError, ValueError):
            raise ApiError("INVALID_ATTRIBUTE", "شناسه ویژگی نامعتبر است", http_status=422)
        if attribute_id in seen_attr:
            raise ApiError("VARIANT_DIMENSION_DUPLICATE", "ویژگی تکراری در ابعاد کالا مجاز نیست", http_status=409)
        seen_attr.add(attribute_id)
        link = (
            db.query(ProductAttributeLink)
            .filter(
                ProductAttributeLink.product_id == int(product_id),
                ProductAttributeLink.attribute_id == attribute_id,
            )
            .first()
        )
        if not link:
            raise ApiError(
                "VARIANT_ATTRIBUTE_NOT_LINKED",
                "ویژگی انباری باید از ویژگی‌های همین کالا انتخاب شود",
                http_status=422,
            )
        attr = (
            db.query(ProductAttribute)
            .filter(
                ProductAttribute.id == attribute_id,
                ProductAttribute.business_id == int(business_id),
            )
            .first()
        )
        if not attr:
            raise ApiError("ATTRIBUTE_NOT_FOUND", "ویژگی یافت نشد", http_status=404)
        if (attr.data_type or "text") != "select":
            raise ApiError(
                "VARIANT_ATTRIBUTE_NOT_SELECT",
                "فقط ویژگی از نوع فهرست انتخابی می‌تواند موجودی را تفکیک کند",
                http_status=422,
            )
        ensure_options_for_attribute(db, attr)
        sort_order = int(item.get("sort_order") or (idx + 1))
        is_required = bool(item.get("is_required", True))
        normalized.append(
            {
                "attribute_id": attribute_id,
                "sort_order": sort_order,
                "is_required": is_required,
            }
        )

    db.query(ProductVariantDimension).filter(
        ProductVariantDimension.business_id == int(business_id),
        ProductVariantDimension.product_id == int(product_id),
    ).delete(synchronize_session=False)
    rows: List[ProductVariantDimension] = []
    for item in normalized:
        row = ProductVariantDimension(
            business_id=int(business_id),
            product_id=int(product_id),
            attribute_id=int(item["attribute_id"]),
            is_required=bool(item["is_required"]),
            sort_order=int(item["sort_order"]),
        )
        db.add(row)
        rows.append(row)
    db.flush()
    return [_serialize_dimension(r) for r in rows]


def _display_title_from_values(db: Session, values: Sequence[tuple[int, int]]) -> str:
    titles: List[str] = []
    for attr_id, option_id in sorted(values, key=lambda x: x[0]):
        opt = db.get(ProductAttributeOption, int(option_id))
        if opt:
            titles.append(str(opt.label))
    return " / ".join(titles)


def _serialize_variant(db: Session, variant: ProductVariant) -> Dict[str, Any]:
    values = (
        db.query(ProductVariantValue)
        .filter(ProductVariantValue.variant_id == int(variant.id))
        .all()
    )
    return {
        "id": int(variant.id),
        "product_id": int(variant.product_id),
        "code": variant.code,
        "barcode": variant.barcode,
        "display_title": variant.display_title,
        "combination_key": variant.combination_key,
        "sales_price": str(variant.sales_price) if variant.sales_price is not None else None,
        "purchase_price": str(variant.purchase_price) if variant.purchase_price is not None else None,
        "row_version": int(variant.row_version or 1),
        "is_active": bool(variant.is_active),
        "attribute_values": [
            {
                "attribute_id": int(v.attribute_id),
                "option_id": int(v.option_id),
            }
            for v in sorted(values, key=lambda x: int(x.attribute_id))
        ],
        "created_at": variant.created_at,
        "updated_at": variant.updated_at,
    }


def _assert_barcode_available(
    db: Session,
    business_id: int,
    barcode: Optional[str],
    *,
    exclude_variant_id: Optional[int] = None,
    exclude_product_id: Optional[int] = None,
) -> None:
    token = (barcode or "").strip()
    if not token:
        return
    assert_tokens_unique_among_products(db, business_id, [token], exclude_product_id=exclude_product_id)
    assert_tokens_not_used_by_unique_instances(db, business_id, [token], exclude_product_id=exclude_product_id)
    q = db.query(ProductVariant.id).filter(
        ProductVariant.business_id == int(business_id),
        func.lower(ProductVariant.barcode) == token.lower(),
    )
    if exclude_variant_id is not None:
        q = q.filter(ProductVariant.id != int(exclude_variant_id))
    if q.first():
        raise ApiError("DUPLICATE_VARIANT_BARCODE", "این بارکد قبلاً برای ترکیب دیگری ثبت شده است", http_status=409)


def _validate_attribute_values(
    db: Session,
    business_id: int,
    product_id: int,
    attribute_values: Sequence[Dict[str, Any]],
) -> List[tuple[int, int]]:
    dims = list_dimensions(db, business_id, product_id)
    if not dims:
        raise ApiError(
            "VARIANT_DIMENSION_REQUIRED",
            "ابتدا ویژگی‌های اثرگذار بر موجودی این کالا را انتخاب کنید",
            http_status=422,
        )
    required_attrs = {int(d.attribute_id) for d in dims if d.is_required}
    dim_attrs = {int(d.attribute_id) for d in dims}
    pairs: List[tuple[int, int]] = []
    seen: set[int] = set()
    for item in attribute_values:
        try:
            attribute_id = int(item.get("attribute_id"))
            option_id = int(item.get("option_id"))
        except (TypeError, ValueError):
            raise ApiError("INVALID_VARIANT_VALUE", "شناسه ویژگی یا گزینه نامعتبر است", http_status=422)
        if attribute_id not in dim_attrs:
            raise ApiError("VARIANT_ATTRIBUTE_NOT_DIMENSION", "این ویژگی بعد انباری کالا نیست", http_status=422)
        if attribute_id in seen:
            raise ApiError("VARIANT_VALUE_DUPLICATE", "برای هر ویژگی فقط یک گزینه مجاز است", http_status=422)
        seen.add(attribute_id)
        option = get_option(
            db,
            business_id=business_id,
            attribute_id=attribute_id,
            option_id=option_id,
        )
        if not option or not option.is_active:
            raise ApiError("VARIANT_OPTION_NOT_FOUND", "گزینه ویژگی یافت نشد یا غیرفعال است", http_status=422)
        pairs.append((attribute_id, option_id))
    missing = required_attrs - seen
    if missing:
        raise ApiError(
            "VARIANT_VALUE_INCOMPLETE",
            "ترکیب باید برای همه ابعاد الزامی مقدار داشته باشد",
            http_status=422,
            details={"missing_attribute_ids": sorted(missing)},
        )
    extra = seen - dim_attrs
    if extra:
        raise ApiError("VARIANT_ATTRIBUTE_NOT_DIMENSION", "ویژگی اضافه‌ای در ترکیب ارسال شده است", http_status=422)
    return pairs


def create_variant(
    db: Session,
    business_id: int,
    product_id: int,
    payload: Dict[str, Any],
) -> Dict[str, Any]:
    product = _load_product(db, business_id, product_id)
    _assert_bulk_product(product)
    count = (
        db.query(func.count(ProductVariant.id))
        .filter(
            ProductVariant.business_id == int(business_id),
            ProductVariant.product_id == int(product_id),
        )
        .scalar()
        or 0
    )
    if int(count) >= MAX_VARIANTS_PER_PRODUCT:
        raise ApiError(
            "VARIANT_LIMIT",
            f"سقف تعداد ترکیب برای هر کالا {MAX_VARIANTS_PER_PRODUCT} است",
            http_status=422,
        )
    pairs = _validate_attribute_values(db, business_id, product_id, payload.get("attribute_values") or [])
    combination_key = build_combination_key(pairs)
    existing = (
        db.query(ProductVariant)
        .filter(
            ProductVariant.product_id == int(product_id),
            ProductVariant.combination_key == combination_key,
        )
        .first()
    )
    if existing:
        raise ApiError("VARIANT_COMBINATION_DUPLICATE", "این ترکیب قبلاً ساخته شده است", http_status=409)

    code = (payload.get("code") or "").strip() or None
    barcode = (payload.get("barcode") or "").strip() or None
    _assert_barcode_available(
        db, business_id, barcode, exclude_product_id=int(product_id)
    )
    title = (payload.get("display_title") or "").strip() or _display_title_from_values(db, pairs)
    sales_price = payload.get("sales_price")
    purchase_price = payload.get("purchase_price")
    variant = ProductVariant(
        business_id=int(business_id),
        product_id=int(product_id),
        code=code,
        barcode=barcode,
        sales_price=Decimal(str(sales_price)) if sales_price is not None and str(sales_price) != "" else None,
        purchase_price=Decimal(str(purchase_price)) if purchase_price is not None and str(purchase_price) != "" else None,
        display_title=title,
        combination_key=combination_key,
        row_version=1,
        is_active=True if payload.get("is_active") is None else bool(payload.get("is_active")),
    )
    db.add(variant)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        raise ApiError("VARIANT_COMBINATION_DUPLICATE", "این ترکیب قبلاً ساخته شده است", http_status=409)
    for attr_id, option_id in pairs:
        db.add(
            ProductVariantValue(
                variant_id=int(variant.id),
                business_id=int(business_id),
                attribute_id=int(attr_id),
                option_id=int(option_id),
            )
        )
    db.flush()
    return _serialize_variant(db, variant)


def list_variants(db: Session, business_id: int, product_id: int) -> List[Dict[str, Any]]:
    _load_product(db, business_id, product_id)
    rows = (
        db.query(ProductVariant)
        .filter(
            ProductVariant.business_id == int(business_id),
            ProductVariant.product_id == int(product_id),
        )
        .order_by(ProductVariant.id.asc())
        .all()
    )
    return [_serialize_variant(db, row) for row in rows]


def get_variant(db: Session, business_id: int, product_id: int, variant_id: int) -> ProductVariant:
    variant = (
        db.query(ProductVariant)
        .filter(
            ProductVariant.id == int(variant_id),
            ProductVariant.business_id == int(business_id),
            ProductVariant.product_id == int(product_id),
        )
        .first()
    )
    if not variant:
        raise ApiError("VARIANT_NOT_FOUND", "ترکیب کالا یافت نشد", http_status=404)
    return variant


def update_variant(
    db: Session,
    business_id: int,
    product_id: int,
    variant_id: int,
    payload: Dict[str, Any],
) -> Dict[str, Any]:
    variant = get_variant(db, business_id, product_id, variant_id)
    expected_version = payload.get("row_version")
    if expected_version is not None and int(variant.row_version or 1) != int(expected_version):
        raise ApiError("VARIANT_VERSION_CONFLICT", "ترکیب توسط کاربر دیگری تغییر کرده است", http_status=409)
    if "attribute_values" in payload and payload.get("attribute_values") is not None:
        if product_has_variant_movement(db, business_id, product_id):
            raise ApiError(
                "VARIANT_IMMUTABLE_COMBINATION",
                "پس از گردش، ترکیب ویژگی‌ها قابل تغییر نیست",
                http_status=409,
            )
        pairs = _validate_attribute_values(db, business_id, product_id, payload.get("attribute_values") or [])
        combination_key = build_combination_key(pairs)
        dup = (
            db.query(ProductVariant.id)
            .filter(
                ProductVariant.product_id == int(product_id),
                ProductVariant.combination_key == combination_key,
                ProductVariant.id != int(variant.id),
            )
            .first()
        )
        if dup:
            raise ApiError("VARIANT_COMBINATION_DUPLICATE", "این ترکیب قبلاً ساخته شده است", http_status=409)
        db.query(ProductVariantValue).filter(ProductVariantValue.variant_id == int(variant.id)).delete(
            synchronize_session=False
        )
        for attr_id, option_id in pairs:
            db.add(
                ProductVariantValue(
                    variant_id=int(variant.id),
                    business_id=int(business_id),
                    attribute_id=int(attr_id),
                    option_id=int(option_id),
                )
            )
        variant.combination_key = combination_key
        if not payload.get("display_title"):
            variant.display_title = _display_title_from_values(db, pairs)
    if "code" in payload:
        variant.code = (payload.get("code") or "").strip() or None
    if "barcode" in payload:
        barcode = (payload.get("barcode") or "").strip() or None
        _assert_barcode_available(
            db,
            business_id,
            barcode,
            exclude_variant_id=int(variant.id),
            exclude_product_id=int(product_id),
        )
        variant.barcode = barcode
    if "display_title" in payload and payload.get("display_title"):
        variant.display_title = str(payload.get("display_title")).strip()
    if "is_active" in payload and payload.get("is_active") is not None:
        variant.is_active = bool(payload.get("is_active"))
    if "sales_price" in payload:
        sales_price = payload.get("sales_price")
        variant.sales_price = Decimal(str(sales_price)) if sales_price is not None and str(sales_price) != "" else None
    if "purchase_price" in payload:
        purchase_price = payload.get("purchase_price")
        variant.purchase_price = (
            Decimal(str(purchase_price)) if purchase_price is not None and str(purchase_price) != "" else None
        )
    variant.row_version = int(variant.row_version or 1) + 1
    try:
        db.flush()
    except IntegrityError:
        raise ApiError("VARIANT_COMBINATION_DUPLICATE", "این ترکیب قبلاً ساخته شده است", http_status=409)
    return _serialize_variant(db, variant)


def deactivate_variant(db: Session, business_id: int, product_id: int, variant_id: int) -> Dict[str, Any]:
    variant = get_variant(db, business_id, product_id, variant_id)
    variant.is_active = False
    variant.row_version = int(variant.row_version or 1) + 1
    db.flush()
    return _serialize_variant(db, variant)


def resolve_variant(
    db: Session,
    business_id: int,
    product_id: int,
    variant_id: int,
    *,
    require_active: bool = True,
) -> ProductVariant:
    variant = get_variant(db, business_id, product_id, variant_id)
    if require_active and not variant.is_active:
        raise ApiError("VARIANT_INACTIVE", "این ترکیب غیرفعال است و برای گردش جدید قابل انتخاب نیست", http_status=422)
    return variant


def build_attributes_snapshot(db: Session, variant: ProductVariant) -> List[Dict[str, Any]]:
    values = (
        db.query(ProductVariantValue, ProductAttribute, ProductAttributeOption)
        .join(ProductAttribute, ProductAttribute.id == ProductVariantValue.attribute_id)
        .join(ProductAttributeOption, ProductAttributeOption.id == ProductVariantValue.option_id)
        .filter(ProductVariantValue.variant_id == int(variant.id))
        .all()
    )
    snapshot: List[Dict[str, Any]] = []
    for value, attr, option in sorted(values, key=lambda row: int(row[0].attribute_id)):
        snapshot.append(
            {
                "attribute_id": int(attr.id),
                "option_id": int(option.id),
                "name": attr.title,
                "value": option.label,
            }
        )
    return snapshot


def assert_attribute_ids_keep_dimensions(
    db: Session,
    business_id: int,
    product_id: int,
    attribute_ids: Optional[List[int]],
) -> None:
    dims = list_dimensions(db, business_id, product_id)
    if not dims:
        return
    required = {int(d.attribute_id) for d in dims}
    incoming = set(int(x) for x in (attribute_ids or []))
    if not required.issubset(incoming):
        raise ApiError(
            "VARIANT_DIMENSION_IN_USE",
            "ویژگی اثرگذار بر موجودی را نمی‌توان از کالا حذف کرد",
            http_status=409,
        )


def assert_not_inventory_variant(
    product: Product,
    *,
    code: str = "VARIANT_NOT_SUPPORTED_HERE",
    message: str = "کالای با تفکیک موجودی ویژگی در این بخش پشتیبانی نمی‌شود",
) -> None:
    if is_variant_inventory_product(product):
        raise ApiError(code, message, http_status=422)


def resolve_barcode_token(db: Session, business_id: int, token: str) -> Dict[str, Any]:
    """ترتیب: یونیک instance، سپس Variant، سپس بارکد عمومی کالا."""
    from adapters.db.models.product_general_barcode_alias import ProductGeneralBarcodeAlias
    from adapters.db.models.product_instance import ProductInstance

    raw = (token or "").strip()
    if not raw:
        raise ApiError("BARCODE_REQUIRED", "بارکد الزامی است", http_status=422)
    key = raw.lower()

    instance = (
        db.query(ProductInstance)
        .filter(
            ProductInstance.business_id == int(business_id),
            or_(
                func.lower(ProductInstance.barcode) == key,
                func.lower(ProductInstance.serial_number) == key,
            ),
        )
        .first()
    )
    if instance is not None:
        product = _load_product(db, business_id, int(instance.product_id))
        return {
            "match_type": "unique_instance",
            "product_id": int(product.id),
            "variant_id": None,
            "instance_id": int(instance.id),
            "product": {"id": int(product.id), "name": product.name, "code": product.code},
        }

    variant = (
        db.query(ProductVariant)
        .filter(
            ProductVariant.business_id == int(business_id),
            func.lower(ProductVariant.barcode) == key,
        )
        .first()
    )
    if variant is not None:
        product = _load_product(db, business_id, int(variant.product_id))
        return {
            "match_type": "variant",
            "product_id": int(product.id),
            "variant_id": int(variant.id),
            "instance_id": None,
            "product": {"id": int(product.id), "name": product.name, "code": product.code},
            "variant": _serialize_variant(db, variant),
        }

    alias = (
        db.query(ProductGeneralBarcodeAlias)
        .filter(
            ProductGeneralBarcodeAlias.business_id == int(business_id),
            ProductGeneralBarcodeAlias.token_normalized == key,
        )
        .first()
    )
    if alias is not None:
        product = _load_product(db, business_id, int(alias.product_id))
        return {
            "match_type": "product",
            "product_id": int(product.id),
            "variant_id": None,
            "instance_id": None,
            "product": {"id": int(product.id), "name": product.name, "code": product.code},
        }
    raise ApiError("BARCODE_NOT_FOUND", "بارکد یافت نشد", http_status=404)


def list_variant_balances(
    db: Session,
    business_id: int,
    product_id: int,
    warehouse_id: Optional[int] = None,
) -> List[Dict[str, Any]]:
    from adapters.db.models.inventory_variant_balance import InventoryVariantBalance

    product = _load_product(db, business_id, product_id)
    q = db.query(InventoryVariantBalance).filter(
        InventoryVariantBalance.business_id == int(business_id),
        InventoryVariantBalance.product_id == int(product_id),
    )
    if warehouse_id is not None:
        q = q.filter(InventoryVariantBalance.warehouse_id == int(warehouse_id))
    rows = q.all()
    from app.core.business_calendar import business_today
    from app.services.inventory_lot_service import is_expiry_tracked_product, sellable_quantity
    expiry_tracked = is_expiry_tracked_product(product)
    as_of = business_today(business_id)
    out: List[Dict[str, Any]] = []
    for row in rows:
        physical = row.quantity or 0
        item = {
            "warehouse_id": int(row.warehouse_id),
            "product_id": int(row.product_id),
            "variant_id": int(row.variant_id),
            "quantity": str(physical),
        }
        if expiry_tracked:
            item["sellable_quantity"] = str(
                sellable_quantity(
                    db,
                    business_id,
                    product,
                    int(row.warehouse_id),
                    as_of,
                    variant_id=int(row.variant_id),
                )
            )
        else:
            item["sellable_quantity"] = str(physical)
        out.append(item)
    return out
