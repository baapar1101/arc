from __future__ import annotations

from typing import Dict, Any, Optional
from sqlalchemy.orm import Session
from sqlalchemy import and_, func

from adapters.db.repositories.product_attribute_repository import ProductAttributeRepository
from adapters.db.models.product_attribute import ProductAttribute
from adapters.api.v1.schema_models.product_attribute import (
    ProductAttributeCreateRequest,
    ProductAttributeUpdateRequest,
)
from app.core.responses import ApiError


def create_attribute(db: Session, business_id: int, payload: ProductAttributeCreateRequest) -> Dict[str, Any]:
    repo = ProductAttributeRepository(db)
    # جلوگیری از عنوان تکراری در هر کسب‌وکار
    dup = db.query(ProductAttribute).filter(
        and_(ProductAttribute.business_id == business_id, func.lower(ProductAttribute.title) == func.lower(payload.title.strip()))
    ).first()
    if dup:
        raise ApiError("DUPLICATE_ATTRIBUTE_TITLE", "عنوان ویژگی تکراری است", http_status=400)

    obj = repo.create(business_id=business_id, title=payload.title.strip(), description=payload.description)
    return {
        "message": "ویژگی با موفقیت ایجاد شد",
        "data": _to_dict(obj),
    }


def list_attributes(db: Session, business_id: int, query: Dict[str, Any]) -> Dict[str, Any]:
    repo = ProductAttributeRepository(db)
    take = int(query.get("take", 20) or 20)
    skip = int(query.get("skip", 0) or 0)
    sort_by = query.get("sort_by")
    sort_desc = bool(query.get("sort_desc", True))
    search = query.get("search")
    filters = query.get("filters")
    result = repo.search(
        business_id=business_id,
        take=take,
        skip=skip,
        sort_by=sort_by,
        sort_desc=sort_desc,
        search=search,
        filters=filters,
    )
    return result


def get_attribute(db: Session, attribute_id: int, business_id: int) -> Optional[Dict[str, Any]]:
    obj = db.get(ProductAttribute, attribute_id)
    if not obj or obj.business_id != business_id:
        return None
    return _to_dict(obj)


def update_attribute(db: Session, attribute_id: int, business_id: int, payload: ProductAttributeUpdateRequest) -> Optional[Dict[str, Any]]:
    repo = ProductAttributeRepository(db)
    # کنترل مالکیت
    obj = db.get(ProductAttribute, attribute_id)
    if not obj or obj.business_id != business_id:
        return None
    # بررسی تکراری نبودن عنوان
    if payload.title is not None:
        title_norm = payload.title.strip()
        dup = db.query(ProductAttribute).filter(
            and_(
                ProductAttribute.business_id == business_id,
                func.lower(ProductAttribute.title) == func.lower(title_norm),
                ProductAttribute.id != attribute_id,
            )
        ).first()
        if dup:
            raise ApiError("DUPLICATE_ATTRIBUTE_TITLE", "عنوان ویژگی تکراری است", http_status=400)
    updated = repo.update(
        attribute_id=attribute_id,
        title=payload.title.strip() if isinstance(payload.title, str) else None,
        description=payload.description,
    )
    if not updated:
        return None
    return {
        "message": "ویژگی با موفقیت ویرایش شد",
        "data": _to_dict(updated),
    }


def delete_attribute(db: Session, attribute_id: int, business_id: int) -> bool:
    repo = ProductAttributeRepository(db)
    obj = db.get(ProductAttribute, attribute_id)
    if not obj or obj.business_id != business_id:
        return False
    return repo.delete(attribute_id=attribute_id)


def _to_dict(obj: ProductAttribute) -> Dict[str, Any]:
    return {
        "id": obj.id,
        "business_id": obj.business_id,
        "title": obj.title,
        "description": obj.description,
        "created_at": obj.created_at,
        "updated_at": obj.updated_at,
    }


