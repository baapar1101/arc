"""P6: همگام‌سازی قیمت پایه کالا از قیمت ارزی × نرخ تسعیر (+ همگام اختیاری PriceList)."""
from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal
from typing import Any, Dict, List, Optional

from sqlalchemy import and_
from sqlalchemy.orm import Session

from adapters.db.models.business import Business
from adapters.db.models.price_list import PriceItem, PriceList
from adapters.db.models.product import Product
from adapters.db.models.quick_sales_settings import QuickSalesSetting
from app.core.responses import ApiError
from app.services.business_currency_rate_service import resolve_rate_to_base
from app.services.currency_quant import get_currency_quant_and_round
from app.services.document_line_fx_service import quantize_money
from app.services.fx_rate_provider_service import assert_multi_currency, business_is_multi_currency

DEFAULT_PRICE_TIER = "پیش‌فرض"


def _d(v: Any) -> Optional[Decimal]:
	if v is None:
		return None
	try:
		return Decimal(str(v))
	except Exception:
		return None


def resolve_default_price_list_id(db: Session, business_id: int) -> Optional[int]:
	"""لیست قیمت پیش‌فرض: Quick Sales → اولین لیست فعال."""
	qs = (
		db.query(QuickSalesSetting)
		.filter(QuickSalesSetting.business_id == int(business_id))
		.first()
	)
	if qs and qs.default_price_list_id:
		pl = db.get(PriceList, int(qs.default_price_list_id))
		if pl and int(pl.business_id) == int(business_id) and bool(pl.is_active):
			return int(pl.id)

	pl = (
		db.query(PriceList)
		.filter(
			PriceList.business_id == int(business_id),
			PriceList.is_active.is_(True),
		)
		.order_by(PriceList.id.asc())
		.first()
	)
	return int(pl.id) if pl else None


def _upsert_price_item_no_commit(
	db: Session,
	*,
	price_list_id: int,
	product_id: int,
	currency_id: int,
	price: Decimal,
	tier_name: str = DEFAULT_PRICE_TIER,
	min_qty: Decimal = Decimal("0"),
	unit_id: Optional[int] = None,
) -> Dict[str, Any]:
	"""Upsert بدون commit جدا — هم‌تراکنش با sync کالا."""
	tier = (tier_name or DEFAULT_PRICE_TIER).strip() or DEFAULT_PRICE_TIER
	stmt_filters = [
		PriceItem.price_list_id == int(price_list_id),
		PriceItem.product_id == int(product_id),
		PriceItem.tier_name == tier,
		PriceItem.min_qty == min_qty,
		PriceItem.currency_id == int(currency_id),
	]
	if unit_id is None:
		stmt_filters.append(PriceItem.unit_id.is_(None))
	else:
		stmt_filters.append(PriceItem.unit_id == int(unit_id))

	existing = db.query(PriceItem).filter(and_(*stmt_filters)).first()
	if existing:
		before = existing.price
		existing.price = price
		return {
			"action": "updated",
			"price_item_id": int(existing.id),
			"currency_id": int(currency_id),
			"before": str(before) if before is not None else None,
			"after": str(price),
		}

	obj = PriceItem(
		price_list_id=int(price_list_id),
		product_id=int(product_id),
		unit_id=unit_id,
		currency_id=int(currency_id),
		tier_name=tier,
		min_qty=min_qty,
		price=price,
	)
	db.add(obj)
	db.flush()
	return {
		"action": "created",
		"price_item_id": int(obj.id),
		"currency_id": int(currency_id),
		"before": None,
		"after": str(price),
	}


def sync_price_list_from_product_base(
	db: Session,
	product: Product,
	*,
	price_list_id: Optional[int] = None,
) -> Dict[str, Any]:
	"""
	همگام اختیاری PriceList با قیمت پایه کالا (فروش به ارز پایه).
	اگر لیست قیمتی نباشد → skipped.
	"""
	bid = int(product.business_id)
	pl_id = int(price_list_id) if price_list_id else resolve_default_price_list_id(db, bid)
	if not pl_id:
		return {"synced": False, "reason": "no_price_list", "items": []}

	pl = db.get(PriceList, pl_id)
	if not pl or int(pl.business_id) != bid:
		return {"synced": False, "reason": "price_list_not_found", "items": []}

	biz = db.get(Business, bid)
	if not biz or not biz.default_currency_id:
		return {"synced": False, "reason": "no_base_currency", "items": []}
	base_id = int(biz.default_currency_id)

	sales = _d(product.base_sales_price)
	if sales is None or sales < 0:
		return {
			"synced": False,
			"reason": "no_base_sales_price",
			"price_list_id": pl_id,
			"items": [],
		}

	item = _upsert_price_item_no_commit(
		db,
		price_list_id=pl_id,
		product_id=int(product.id),
		currency_id=base_id,
		price=sales,
	)
	return {
		"synced": True,
		"price_list_id": pl_id,
		"items": [item],
	}


def apply_fx_prices_to_base_for_product(
	db: Session,
	product: Product,
	*,
	as_of: Optional[datetime] = None,
	force: bool = False,
) -> Dict[str, Any]:
	"""
	base = fx_price × rate (نسبت به ارز پایه).
	اگر force=False فقط وقتی auto_update_base_from_fx=True اجرا می‌شود.
	"""
	if not force and not bool(getattr(product, "auto_update_base_from_fx", False)):
		return {"updated": False, "reason": "auto_update_disabled", "product_id": int(product.id)}

	fx_cur = getattr(product, "price_fx_currency_id", None)
	if not fx_cur:
		return {"updated": False, "reason": "no_fx_currency", "product_id": int(product.id)}

	biz = db.get(Business, int(product.business_id))
	if not biz or not biz.default_currency_id:
		return {"updated": False, "reason": "no_base_currency", "product_id": int(product.id)}
	base_id = int(biz.default_currency_id)
	if int(fx_cur) == base_id:
		return {"updated": False, "reason": "fx_currency_is_base", "product_id": int(product.id)}

	when = as_of or datetime.now(timezone.utc)
	try:
		rate_info = resolve_rate_to_base(db, int(product.business_id), int(fx_cur), when)
		rate = Decimal(str(rate_info["rate"]))
	except ApiError:
		return {"updated": False, "reason": "no_rate", "product_id": int(product.id)}
	except Exception:
		return {"updated": False, "reason": "no_rate", "product_id": int(product.id)}

	if rate <= 0:
		return {"updated": False, "reason": "invalid_rate", "product_id": int(product.id)}

	base_quant, round_on = get_currency_quant_and_round(db, base_id)
	changed = False
	before = {
		"base_sales_price": str(product.base_sales_price) if product.base_sales_price is not None else None,
		"base_purchase_price": str(product.base_purchase_price) if product.base_purchase_price is not None else None,
	}

	sales_fx = _d(getattr(product, "sales_price_fx", None))
	if sales_fx is not None and sales_fx >= 0:
		new_sales = quantize_money(sales_fx * rate, base_quant, round_on=round_on)
		if product.base_sales_price != new_sales:
			product.base_sales_price = new_sales
			changed = True

	purchase_fx = _d(getattr(product, "purchase_price_fx", None))
	if purchase_fx is not None and purchase_fx >= 0:
		new_purch = quantize_money(purchase_fx * rate, base_quant, round_on=round_on)
		if product.base_purchase_price != new_purch:
			product.base_purchase_price = new_purch
			changed = True

	return {
		"updated": changed,
		"product_id": int(product.id),
		"rate": str(rate),
		"before": before,
		"after": {
			"base_sales_price": str(product.base_sales_price) if product.base_sales_price is not None else None,
			"base_purchase_price": str(product.base_purchase_price) if product.base_purchase_price is not None else None,
		},
	}


def sync_product_base_from_fx(
	db: Session,
	business_id: int,
	product_id: int,
	*,
	force: bool = True,
	sync_price_list: bool = False,
	price_list_id: Optional[int] = None,
) -> Dict[str, Any]:
	assert_multi_currency(db, int(business_id))
	obj = (
		db.query(Product)
		.filter(Product.id == int(product_id), Product.business_id == int(business_id))
		.first()
	)
	if not obj:
		raise ApiError("PRODUCT_NOT_FOUND", "کالا یافت نشد", http_status=404)
	result = apply_fx_prices_to_base_for_product(db, obj, force=force)
	price_list_result: Optional[Dict[str, Any]] = None
	# همگام PriceList حتی اگر base قبلاً هم‌نرخ بوده (کاربر صریحاً خواسته)
	if sync_price_list:
		price_list_result = sync_price_list_from_product_base(
			db, obj, price_list_id=price_list_id
		)
		result["price_list"] = price_list_result

	if result.get("updated") or (price_list_result and price_list_result.get("synced")):
		db.commit()
		db.refresh(obj)
	return result


def sync_business_products_base_from_fx(
	db: Session,
	business_id: int,
	*,
	only_auto: bool = True,
	product_ids: Optional[List[int]] = None,
	sync_price_list: bool = False,
) -> Dict[str, Any]:
	"""به‌روزرسانی گروهی؛ معمولاً پس از ثبت نرخ جدید."""
	if not business_is_multi_currency(db, int(business_id)):
		return {"updated_count": 0, "items": [], "skipped": "not_multi_currency"}

	q = db.query(Product).filter(Product.business_id == int(business_id))
	if only_auto:
		q = q.filter(Product.auto_update_base_from_fx.is_(True))
	if product_ids:
		q = q.filter(Product.id.in_([int(x) for x in product_ids]))
	q = q.filter(Product.price_fx_currency_id.isnot(None))

	items: List[Dict[str, Any]] = []
	updated = 0
	pl_synced = 0
	for prod in q.all():
		res = apply_fx_prices_to_base_for_product(db, prod, force=True)
		if sync_price_list:
			pl_res = sync_price_list_from_product_base(db, prod)
			res["price_list"] = pl_res
			if pl_res.get("synced"):
				pl_synced += 1
		if res.get("updated"):
			updated += 1
		items.append(res)
	if updated or pl_synced:
		db.commit()
	return {
		"updated_count": updated,
		"price_list_synced_count": pl_synced,
		"items": items,
		"total_checked": len(items),
	}
