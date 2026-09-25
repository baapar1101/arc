from __future__ import annotations

from typing import Dict, Any, Optional
from sqlalchemy.orm import Session
from sqlalchemy import and_, or_

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
    return {"message": "PRICE_LIST_CREATED", "data": _pl_to_dict(obj)}


def list_price_lists(db: Session, business_id: int, query: Dict[str, Any]) -> Dict[str, Any]:
    repo = PriceListRepository(db)
    take = int(query.get("take", 20) or 20)
    skip = int(query.get("skip", 0) or 0)
    sort_by = query.get("sort_by")
    sort_desc = bool(query.get("sort_desc", True))
    sort_multi = query.get("sort") if isinstance(query.get("sort"), list) else None
    search = query.get("search")
    return repo.search(
        business_id=business_id,
        take=take,
        skip=skip,
        sort_by=sort_by,
        sort_desc=sort_desc,
        sort=sort_multi,
        search=search,
    )


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
    return {"message": "PRICE_LIST_UPDATED", "data": _pl_to_dict(updated)}


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
    if payload.unit_id is not None and payload.unit_id not in [pr.main_unit, pr.secondary_unit]:
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
    return {"message": "PRICE_ITEM_UPSERTED", "data": _pi_to_dict(obj)}


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


def _resolve_price_list_id(db: Session, business_id: int, item: Dict[str, Any]) -> int:
    if item.get("price_list_id") is not None and item.get("price_list_id") != "":
        pl_id = int(item["price_list_id"])
        pl = db.get(PriceList, pl_id)
        if not pl or pl.business_id != business_id:
            raise ApiError("NOT_FOUND", "لیست قیمت یافت نشد", http_status=404)
        return pl_id
    name = str(item.get("price_list_name") or "").strip()
    if not name:
        raise ApiError(
            "PRICE_LIST_REQUIRED",
            "برای ردیف لیست قیمت باید price_list_id یا price_list_name بفرستی",
            http_status=400,
        )
    exact = (
        db.query(PriceList)
        .filter(and_(PriceList.business_id == business_id, PriceList.name == name))
        .all()
    )
    if len(exact) == 1:
        return int(exact[0].id)
    fuzzy = (
        db.query(PriceList)
        .filter(and_(PriceList.business_id == business_id, PriceList.name.ilike(f"%{name}%")))
        .all()
    )
    if len(fuzzy) == 1:
        return int(fuzzy[0].id)
    if not fuzzy:
        raise ApiError(
            "NOT_FOUND",
            f"لیست قیمت «{name}» یافت نشد. ابتدا list_price_lists را صدا بزن.",
            http_status=404,
        )
    raise ApiError(
        "AMBIGUOUS_PRICE_LIST",
        f"چند لیست قیمت با نام شبیه «{name}» پیدا شد؛ price_list_id بفرست.",
        http_status=400,
    )


def _resolve_currency_id(db: Session, business_id: int, item: Dict[str, Any]) -> int:
    from adapters.db.models.business import Business
    from adapters.db.models.currency import BusinessCurrency, Currency

    if item.get("currency_id") is not None and item.get("currency_id") != "":
        return int(item["currency_id"])
    code = str(item.get("currency_code") or "").strip()
    if code:
        linked = (
            db.query(Currency)
            .join(BusinessCurrency, BusinessCurrency.currency_id == Currency.id)
            .filter(BusinessCurrency.business_id == business_id)
            .filter(
                or_(
                    Currency.code.ilike(code),
                    Currency.name.ilike(code),
                    Currency.title.ilike(code),
                )
            )
            .all()
        )
        if len(linked) == 1:
            return int(linked[0].id)
        global_rows = (
            db.query(Currency)
            .filter(
                or_(
                    Currency.code.ilike(code),
                    Currency.name.ilike(code),
                    Currency.title.ilike(code),
                )
            )
            .all()
        )
        if len(global_rows) == 1:
            return int(global_rows[0].id)
        if not linked and not global_rows:
            raise ApiError(
                "NOT_FOUND",
                f"ارز «{code}» یافت نشد. ابتدا list_currencies را صدا بزن.",
                http_status=404,
            )
        raise ApiError(
            "AMBIGUOUS_CURRENCY",
            f"چند ارز با کد/نام «{code}» پیدا شد؛ currency_id بفرست.",
            http_status=400,
        )
    biz = db.get(Business, business_id)
    if biz and biz.default_currency_id:
        return int(biz.default_currency_id)
    raise ApiError(
        "CURRENCY_REQUIRED",
        "currency_id یا currency_code الزامی است مگر ارز پیش‌فرض کسب‌وکار تنظیم باشد",
        http_status=400,
    )


def upsert_price_items_for_product(
    db: Session,
    business_id: int,
    product_id: int,
    items: list[Dict[str, Any]],
) -> list[Dict[str, Any]]:
    """همان ذخیرهٔ ردیف‌های لیست قیمت در فرم کالا (upsert به‌ازای هر ردیف)."""
    applied: list[Dict[str, Any]] = []
    for item in items:
        pl_id = _resolve_price_list_id(db, business_id, item)
        currency_id = _resolve_currency_id(db, business_id, item)
        payload = PriceItemUpsertRequest(
            product_id=product_id,
            currency_id=currency_id,
            price=item["price"],
            tier_name=item.get("tier_name"),
            min_qty=item.get("min_qty") or 0,
        )
        result = upsert_price_item(db, business_id, pl_id, payload)
        row = dict(result.get("data") or {})
        if item.get("price_list_name"):
            row["price_list_name"] = item["price_list_name"]
        applied.append(row)
    return applied


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


