from __future__ import annotations

from typing import Dict, Any, Optional, List
from sqlalchemy.orm import Session
from sqlalchemy import select, and_, func
from decimal import Decimal

from app.core.responses import ApiError
from adapters.db.models.product import Product, ProductItemType
from adapters.db.models.product_attribute import ProductAttribute
from adapters.db.models.product_attribute_link import ProductAttributeLink
from adapters.db.repositories.product_repository import ProductRepository
from adapters.api.v1.schema_models.product import ProductCreateRequest, ProductUpdateRequest


def _generate_auto_code(db: Session, business_id: int) -> str:
    codes = [
        r[0] for r in db.execute(
            select(Product.code).where(Product.business_id == business_id)
        ).all()
    ]
    max_num = 0
    for c in codes:
        if c and c.isdigit():
            try:
                max_num = max(max_num, int(c))
            except ValueError:
                continue
    if max_num > 0:
        return str(max_num + 1)
    max_id = db.execute(select(func.max(Product.id))).scalar() or 0
    return f"P{max_id + 1:06d}"


def _validate_tax(payload: ProductCreateRequest | ProductUpdateRequest) -> None:
    if getattr(payload, 'is_sales_taxable', False) and getattr(payload, 'sales_tax_rate', None) is None:
        pass
    if getattr(payload, 'is_purchase_taxable', False) and getattr(payload, 'purchase_tax_rate', None) is None:
        pass


def _validate_units(main_unit_id: Optional[int], secondary_unit_id: Optional[int], factor: Optional[Decimal]) -> None:
    if secondary_unit_id and not factor:
        raise ApiError("INVALID_UNIT_FACTOR", "برای واحد فرعی تعیین ضریب تبدیل الزامی است", http_status=400)


def _upsert_attributes(db: Session, product_id: int, business_id: int, attribute_ids: Optional[List[int]]) -> None:
    if attribute_ids is None:
        return
    db.query(ProductAttributeLink).filter(ProductAttributeLink.product_id == product_id).delete()
    if not attribute_ids:
        db.commit()
        return
    valid_ids = [
        a.id for a in db.query(ProductAttribute.id, ProductAttribute.business_id)
        .filter(ProductAttribute.id.in_(attribute_ids), ProductAttribute.business_id == business_id)
        .all()
    ]
    for aid in valid_ids:
        db.add(ProductAttributeLink(product_id=product_id, attribute_id=aid))
    db.commit()


def create_product(db: Session, business_id: int, payload: ProductCreateRequest) -> Dict[str, Any]:
    repo = ProductRepository(db)
    _validate_tax(payload)
    _validate_units(payload.main_unit_id, payload.secondary_unit_id, payload.unit_conversion_factor)

    code = payload.code.strip() if isinstance(payload.code, str) and payload.code.strip() else None
    if code:
        dup = db.query(Product).filter(and_(Product.business_id == business_id, Product.code == code)).first()
        if dup:
            raise ApiError("DUPLICATE_PRODUCT_CODE", "کد کالا/خدمت تکراری است", http_status=400)
    else:
        code = _generate_auto_code(db, business_id)

    obj = repo.create(
        business_id=business_id,
        item_type=payload.item_type,
        code=code,
        name=payload.name.strip(),
        description=payload.description,
        category_id=payload.category_id,
        main_unit_id=payload.main_unit_id,
        secondary_unit_id=payload.secondary_unit_id,
        unit_conversion_factor=payload.unit_conversion_factor,
        base_sales_price=payload.base_sales_price,
        base_sales_note=payload.base_sales_note,
        base_purchase_price=payload.base_purchase_price,
        base_purchase_note=payload.base_purchase_note,
        track_inventory=payload.track_inventory,
        reorder_point=payload.reorder_point,
        min_order_qty=payload.min_order_qty,
        lead_time_days=payload.lead_time_days,
        is_sales_taxable=payload.is_sales_taxable,
        is_purchase_taxable=payload.is_purchase_taxable,
        sales_tax_rate=payload.sales_tax_rate,
        purchase_tax_rate=payload.purchase_tax_rate,
        tax_type_id=payload.tax_type_id,
        tax_code=payload.tax_code,
        tax_unit_id=payload.tax_unit_id,
    )

    _upsert_attributes(db, obj.id, business_id, payload.attribute_ids)

    return {"message": "PRODUCT_CREATED", "data": _to_dict(obj)}


def list_products(db: Session, business_id: int, query: Dict[str, Any]) -> Dict[str, Any]:
    repo = ProductRepository(db)
    take = int(query.get("take", 20) or 20)
    skip = int(query.get("skip", 0) or 0)
    sort_by = query.get("sort_by")
    sort_desc = bool(query.get("sort_desc", True))
    search = query.get("search")
    filters = query.get("filters")
    return repo.search(
        business_id=business_id,
        take=take,
        skip=skip,
        sort_by=sort_by,
        sort_desc=sort_desc,
        search=search,
        filters=filters,
    )


def get_product(db: Session, product_id: int, business_id: int) -> Optional[Dict[str, Any]]:
    obj = db.get(Product, product_id)
    if not obj or obj.business_id != business_id:
        return None
    return _to_dict(obj)


def update_product(db: Session, product_id: int, business_id: int, payload: ProductUpdateRequest) -> Optional[Dict[str, Any]]:
    repo = ProductRepository(db)
    obj = db.get(Product, product_id)
    if not obj or obj.business_id != business_id:
        return None

    if payload.code is not None and payload.code.strip() and payload.code.strip() != obj.code:
        dup = db.query(Product).filter(and_(Product.business_id == business_id, Product.code == payload.code.strip(), Product.id != product_id)).first()
        if dup:
            raise ApiError("DUPLICATE_PRODUCT_CODE", "کد کالا/خدمت تکراری است", http_status=400)

    _validate_tax(payload)
    _validate_units(payload.main_unit_id if payload.main_unit_id is not None else obj.main_unit_id,
                    payload.secondary_unit_id if payload.secondary_unit_id is not None else obj.secondary_unit_id,
                    payload.unit_conversion_factor if payload.unit_conversion_factor is not None else obj.unit_conversion_factor)

    updated = repo.update(
        product_id,
        item_type=payload.item_type,
        code=payload.code.strip() if isinstance(payload.code, str) else None,
        name=payload.name.strip() if isinstance(payload.name, str) else None,
        description=payload.description,
        category_id=payload.category_id,
        main_unit_id=payload.main_unit_id,
        secondary_unit_id=payload.secondary_unit_id,
        unit_conversion_factor=payload.unit_conversion_factor,
        base_sales_price=payload.base_sales_price,
        base_sales_note=payload.base_sales_note,
        base_purchase_price=payload.base_purchase_price,
        base_purchase_note=payload.base_purchase_note,
        track_inventory=payload.track_inventory if payload.track_inventory is not None else None,
        reorder_point=payload.reorder_point,
        min_order_qty=payload.min_order_qty,
        lead_time_days=payload.lead_time_days,
        is_sales_taxable=payload.is_sales_taxable,
        is_purchase_taxable=payload.is_purchase_taxable,
        sales_tax_rate=payload.sales_tax_rate,
        purchase_tax_rate=payload.purchase_tax_rate,
        tax_type_id=payload.tax_type_id,
        tax_code=payload.tax_code,
        tax_unit_id=payload.tax_unit_id,
    )
    if not updated:
        return None

    _upsert_attributes(db, product_id, business_id, payload.attribute_ids)
    return {"message": "PRODUCT_UPDATED", "data": _to_dict(updated)}


def delete_product(db: Session, product_id: int, business_id: int) -> bool:
    repo = ProductRepository(db)
    obj = db.get(Product, product_id)
    if not obj or obj.business_id != business_id:
        return False
    return repo.delete(product_id)


def _to_dict(obj: Product) -> Dict[str, Any]:
    return {
        "id": obj.id,
        "business_id": obj.business_id,
        "item_type": obj.item_type.value if hasattr(obj.item_type, 'value') else str(obj.item_type),
        "code": obj.code,
        "name": obj.name,
        "description": obj.description,
        "category_id": obj.category_id,
        "main_unit_id": obj.main_unit_id,
        "secondary_unit_id": obj.secondary_unit_id,
        "unit_conversion_factor": obj.unit_conversion_factor,
        "base_sales_price": obj.base_sales_price,
        "base_sales_note": obj.base_sales_note,
        "base_purchase_price": obj.base_purchase_price,
        "base_purchase_note": obj.base_purchase_note,
        "track_inventory": obj.track_inventory,
        "reorder_point": obj.reorder_point,
        "min_order_qty": obj.min_order_qty,
        "lead_time_days": obj.lead_time_days,
        "is_sales_taxable": obj.is_sales_taxable,
        "is_purchase_taxable": obj.is_purchase_taxable,
        "sales_tax_rate": obj.sales_tax_rate,
        "purchase_tax_rate": obj.purchase_tax_rate,
        "tax_type_id": obj.tax_type_id,
        "tax_code": obj.tax_code,
        "tax_unit_id": obj.tax_unit_id,
        "created_at": obj.created_at,
        "updated_at": obj.updated_at,
    }


