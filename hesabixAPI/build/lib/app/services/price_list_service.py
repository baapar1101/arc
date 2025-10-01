from __future__ import annotations

from typing import Dict, Any, Optional
from sqlalchemy.orm import Session
from sqlalchemy import and_

from app.core.responses import ApiError
from adapters.db.repositories.price_list_repository import PriceListRepository, PriceItemRepository
from adapters.db.models.price_list import PriceList, PriceItem
from adapters.api.v1.schema_models.price_list import PriceListCreateRequest, PriceListUpdateRequest, PriceItemUpsertRequest
from adapters.db.models.product import Product


def create_price_list(db: Session, business_id: int, payload: PriceListCreateRequest) -> Dict[str, Any]:
    repo = PriceListRepository(db)
    # یکتایی نام در هر کسب‌وکار
    dup = db.query(PriceList).filter(and_(PriceList.business_id == business_id, PriceList.name == payload.name.strip())).first()
    if dup:
        raise ApiError("DUPLICATE_PRICE_LIST_NAME", "نام لیست قیمت تکراری است", http_status=400)
    obj = repo.create(
        business_id=business_id,
        name=payload.name.strip(),
        is_active=payload.is_active,
    )
    return {"message": "لیست قیمت ایجاد شد", "data": _pl_to_dict(obj)}


def list_price_lists(db: Session, business_id: int, query: Dict[str, Any]) -> Dict[str, Any]:
    repo = PriceListRepository(db)
    take = int(query.get("take", 20) or 20)
    skip = int(query.get("skip", 0) or 0)
    sort_by = query.get("sort_by")
    sort_desc = bool(query.get("sort_desc", True))
    search = query.get("search")
    return repo.search(business_id=business_id, take=take, skip=skip, sort_by=sort_by, sort_desc=sort_desc, search=search)


def get_price_list(db: Session, business_id: int, id: int) -> Optional[Dict[str, Any]]:
    obj = db.get(PriceList, id)
    if not obj or obj.business_id != business_id:
        return None
    return _pl_to_dict(obj)


def update_price_list(db: Session, business_id: int, id: int, payload: PriceListUpdateRequest) -> Optional[Dict[str, Any]]:
    repo = PriceListRepository(db)
    obj = db.get(PriceList, id)
    if not obj or obj.business_id != business_id:
        return None
    if payload.name is not None and payload.name.strip() and payload.name.strip() != obj.name:
        dup = db.query(PriceList).filter(and_(PriceList.business_id == business_id, PriceList.name == payload.name.strip(), PriceList.id != id)).first()
        if dup:
            raise ApiError("DUPLICATE_PRICE_LIST_NAME", "نام لیست قیمت تکراری است", http_status=400)
    updated = repo.update(id, name=payload.name.strip() if isinstance(payload.name, str) else None, is_active=payload.is_active)
    if not updated:
        return None
    return {"message": "لیست قیمت بروزرسانی شد", "data": _pl_to_dict(updated)}


def delete_price_list(db: Session, business_id: int, id: int) -> bool:
    repo = PriceListRepository(db)
    obj = db.get(PriceList, id)
    if not obj or obj.business_id != business_id:
        return False
    return repo.delete(id)


def list_price_items(db: Session, business_id: int, price_list_id: int, take: int = 50, skip: int = 0, product_id: int | None = None, currency_id: int | None = None) -> Dict[str, Any]:
    # مالکیت را از روی price_list بررسی می‌کنیم
    pl = db.get(PriceList, price_list_id)
    if not pl or pl.business_id != business_id:
        raise ApiError("NOT_FOUND", "لیست قیمت یافت نشد", http_status=404)
    repo = PriceItemRepository(db)
    return repo.list_for_price_list(price_list_id=price_list_id, take=take, skip=skip, product_id=product_id, currency_id=currency_id)


def upsert_price_item(db: Session, business_id: int, price_list_id: int, payload: PriceItemUpsertRequest) -> Dict[str, Any]:
    pl = db.get(PriceList, price_list_id)
    if not pl or pl.business_id != business_id:
        raise ApiError("NOT_FOUND", "لیست قیمت یافت نشد", http_status=404)
    # صحت وجود محصول
    pr = db.get(Product, payload.product_id)
    if not pr or pr.business_id != business_id:
        raise ApiError("NOT_FOUND", "کالا/خدمت یافت نشد", http_status=404)
    # اگر unit_id داده شده و با واحدهای محصول سازگار نباشد، خطا بده
    if payload.unit_id is not None and payload.unit_id not in [pr.main_unit_id, pr.secondary_unit_id]:
        raise ApiError("INVALID_UNIT", "واحد انتخابی با واحدهای محصول همخوانی ندارد", http_status=400)

    repo = PriceItemRepository(db)
    obj = repo.upsert(
        price_list_id=price_list_id,
        product_id=payload.product_id,
        unit_id=payload.unit_id,
        currency_id=payload.currency_id,
        tier_name=(payload.tier_name.strip() if isinstance(payload.tier_name, str) and payload.tier_name.strip() else 'پیش‌فرض'),
        min_qty=payload.min_qty,
        price=payload.price,
    )
    return {"message": "قیمت ثبت شد", "data": _pi_to_dict(obj)}


def delete_price_item(db: Session, business_id: int, id: int) -> bool:
    repo = PriceItemRepository(db)
    pi = db.get(PriceItem, id)
    if not pi:
        return False
    # بررسی مالکیت از طریق price_list
    pl = db.get(PriceList, pi.price_list_id)
    if not pl or pl.business_id != business_id:
        return False
    return repo.delete(id)


def _pl_to_dict(obj: PriceList) -> Dict[str, Any]:
    return {
        "id": obj.id,
        "business_id": obj.business_id,
        "name": obj.name,
        "is_active": obj.is_active,
        "created_at": obj.created_at,
        "updated_at": obj.updated_at,
    }


def _pi_to_dict(obj: PriceItem) -> Dict[str, Any]:
    return {
        "id": obj.id,
        "price_list_id": obj.price_list_id,
        "product_id": obj.product_id,
        "unit_id": obj.unit_id,
        "currency_id": obj.currency_id,
        "tier_name": obj.tier_name,
        "min_qty": obj.min_qty,
        "price": obj.price,
        "created_at": obj.created_at,
        "updated_at": obj.updated_at,
    }


