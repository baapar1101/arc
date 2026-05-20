"""سرویس کاتالوگ عمومی (شبکهٔ انتشار کالا): جستجو، جزئیات، فید، تماس."""

from __future__ import annotations

import hashlib
import json
import logging
import re
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy import and_, func, or_, select
from sqlalchemy.orm import Session

from adapters.db.models.business import Business
from adapters.db.models.category import BusinessCategory
from adapters.db.models.product import Product
from adapters.db.models.public_catalog_contact_message import PublicCatalogContactMessage
from app.core.cache import get_cache
from app.services.public_catalog_utils import normalize_catalog_public_uuid

logger = logging.getLogger(__name__)

_CACHE_PREFIX = "public_catalog:v1:"
_LIST_TTL_SECONDS = 45


def invalidate_public_catalog_caches() -> None:
	"""پاک‌سازی کش لیست/فید کاتالوگ عمومی."""
	cache = get_cache()
	if not cache.enabled:
		return
	try:
		deleted = cache.delete_pattern(_CACHE_PREFIX + "*")
		if deleted:
			logger.debug("public_catalog cache invalidated (%s keys)", deleted)
	except Exception as exc:
		logger.warning("public_catalog cache invalidate failed: %s", exc)


_SPLIT_RE = re.compile(r"(?:\s+|(?:[\-‐‑–—])+)+")


def _search_tokens(search: str) -> List[str]:
	s = (search or "").strip()
	if not s:
		return []
	parts = [p for p in _SPLIT_RE.split(s) if p]
	return parts if parts else [s]


def _like_escape(s: str) -> str:
	return s.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


def _column_contains_all_tokens(column, tokens: List[str]):
	if not tokens:
		return True
	if len(tokens) == 1:
		t = _like_escape(tokens[0])
		return column.ilike(f"%{t}%", escape="\\")
	return and_(*[column.ilike(f"%{_like_escape(t)}%", escape="\\") for t in tokens])


def _category_display_name(cat: BusinessCategory | None) -> Optional[str]:
	if not cat:
		return None
	t = cat.title_translations
	if isinstance(t, dict):
		return t.get("fa") or t.get("en") or t.get("default") or None
	return None


def _business_contact_block(b: Business) -> Dict[str, Any]:
	out: Dict[str, Any] = {
		"show_contact": bool(getattr(b, "public_catalog_show_contact", False)),
		"business_name": b.name,
		"address": b.address,
		"province": b.province,
		"city": b.city,
		"country": b.country,
	}
	if out["show_contact"]:
		out["phone"] = b.phone
		out["mobile"] = b.mobile
	else:
		out["phone"] = None
		out["mobile"] = None
	return out


def _product_public_core(p: Product, cat: BusinessCategory | None, b: Business) -> Dict[str, Any]:
	show_price = bool(getattr(b, "public_catalog_show_base_sales_price", True))
	return {
		"catalog_public_uuid": p.catalog_public_uuid,
		"name": p.name,
		"item_type": p.item_type.value if hasattr(p.item_type, "value") else str(p.item_type),
		"description": p.description,
		"category_id": p.category_id,
		"category_name": _category_display_name(cat),
		"main_unit": p.main_unit,
		"base_sales_price": (
			float(p.base_sales_price) if show_price and p.base_sales_price is not None else None
		),
		"updated_at": p.updated_at.isoformat() if p.updated_at else None,
		"image_url": (
			f"/api/v1/public/catalog/products/{p.catalog_public_uuid}/image"
			if p.catalog_public_uuid and p.image_file_id
			else None
		),
		"thumbnail_url": (
			f"/api/v1/public/catalog/products/{p.catalog_public_uuid}/image?size=small"
			if p.catalog_public_uuid and p.image_file_id
			else None
		),
	}


def search_public_catalog(
	db: Session,
	*,
	search: Optional[str] = None,
	business_id: Optional[int] = None,
	category_id: Optional[int] = None,
	province: Optional[str] = None,
	city: Optional[str] = None,
	skip: int = 0,
	take: int = 20,
) -> Dict[str, Any]:
	take = max(1, min(100, int(take)))
	skip = max(0, int(skip))

	cache_params = {
		"search": (search or "").strip(),
		"business_id": business_id,
		"category_id": category_id,
		"province": (province or "").strip() or None,
		"city": (city or "").strip() or None,
		"skip": skip,
		"take": take,
	}
	cache = get_cache()
	cache_key = _CACHE_PREFIX + "list:" + hashlib.sha256(
		json.dumps(cache_params, sort_keys=True, default=str).encode("utf-8")
	).hexdigest()[:40]

	if cache.enabled:
		try:
			cached = cache.get(cache_key)
			if isinstance(cached, dict):
				return cached
		except Exception:
			pass

	where_extra = []
	if business_id is not None:
		where_extra.append(Product.business_id == int(business_id))
	if category_id is not None:
		where_extra.append(Product.category_id == int(category_id))
	if province:
		where_extra.append(Business.province.ilike(f"%{_like_escape(province.strip())}%", escape="\\"))
	if city:
		where_extra.append(Business.city.ilike(f"%{_like_escape(city.strip())}%", escape="\\"))

	tokens = _search_tokens(search or "")
	if tokens:
		desc_col = func.coalesce(Product.description, "")
		where_extra.append(
			or_(
				_column_contains_all_tokens(Product.name, tokens),
				_column_contains_all_tokens(desc_col, tokens),
			)
		)

	base_where = and_(
		Product.is_public_catalog.is_(True),
		Product.is_active.is_(True),
		Product.catalog_public_uuid.isnot(None),
		Business.deleted_at.is_(None),
		*where_extra,
	)

	count_stmt = (
		select(func.count(Product.id))
		.select_from(Product)
		.join(Business, Business.id == Product.business_id)
		.where(base_where)
	)
	total = int(db.execute(count_stmt).scalar() or 0)

	stmt = (
		select(Product, Business, BusinessCategory)
		.join(Business, Business.id == Product.business_id)
		.outerjoin(
			BusinessCategory,
			and_(
				BusinessCategory.id == Product.category_id,
				BusinessCategory.business_id == Product.business_id,
			),
		)
		.where(base_where)
		.order_by(Product.updated_at.desc().nullslast(), Product.id.desc())
		.offset(skip)
		.limit(take)
	)
	rows = db.execute(stmt).all()

	items: List[Dict[str, Any]] = []
	for p, b, cat in rows:
		row = {
			"business_id": b.id,
			"supplier": _business_contact_block(b),
			"product": _product_public_core(p, cat, b),
		}
		items.append(row)

	out = {
		"items": items,
		"total_count": total,
		"skip": skip,
		"take": take,
	}
	if cache.enabled:
		try:
			cache.set(cache_key, out, ttl=_LIST_TTL_SECONDS)
		except Exception:
			pass
	return out


def get_public_product_by_uuid(db: Session, catalog_public_uuid: str) -> Optional[Dict[str, Any]]:
	try:
		u = normalize_catalog_public_uuid(catalog_public_uuid)
	except ValueError:
		return None
	stmt = (
		select(Product, Business, BusinessCategory)
		.join(Business, Business.id == Product.business_id)
		.outerjoin(
			BusinessCategory,
			and_(
				BusinessCategory.id == Product.category_id,
				BusinessCategory.business_id == Product.business_id,
			),
		)
		.where(
			Product.catalog_public_uuid == u,
			Product.is_public_catalog.is_(True),
			Product.is_active.is_(True),
			Business.deleted_at.is_(None),
		)
	)
	row = db.execute(stmt).first()
	if not row:
		return None
	p, b, cat = row
	return {
		"business_id": b.id,
		"supplier": _business_contact_block(b),
		"product": _product_public_core(p, cat, b),
	}


def list_public_catalog_feed(
	db: Session,
	*,
	take: int = 50,
	skip: int = 0,
) -> Dict[str, Any]:
	take = max(1, min(200, int(take)))
	skip = max(0, int(skip))
	data = search_public_catalog(db, search=None, skip=skip, take=take)
	items = []
	for it in data.get("items") or []:
		items.append(
			{
				"business_id": it.get("business_id"),
				"catalog_public_uuid": (it.get("product") or {}).get("catalog_public_uuid"),
				"name": (it.get("product") or {}).get("name"),
				"updated_at": (it.get("product") or {}).get("updated_at"),
			}
		)
	return {"items": items, "take": take, "skip": skip}


def resolve_public_catalog_product_image(
	db: Session,
	catalog_public_uuid: str,
) -> Tuple[Optional[Product], Optional[str]]:
	"""برمی‌گرداند (Product, image_file_id) اگر انتشار فعال و فایل معتبر باشد."""
	try:
		u = normalize_catalog_public_uuid(catalog_public_uuid)
	except ValueError:
		return None, None
	p = (
		db.query(Product)
		.join(Business, Business.id == Product.business_id)
		.filter(
			Product.catalog_public_uuid == u,
			Product.is_public_catalog.is_(True),
			Product.is_active.is_(True),
			Business.deleted_at.is_(None),
			Product.image_file_id.isnot(None),
		)
		.first()
	)
	if not p or not p.image_file_id:
		return None, None
	return p, str(p.image_file_id)


def create_public_catalog_contact_message(
	db: Session,
	*,
	business_id: int,
	product_catalog_uuid: Optional[str],
	sender_name: str,
	sender_contact: str,
	message: str,
	client_ip: Optional[str],
) -> None:
	from app.core.responses import ApiError

	b = db.query(Business).filter(Business.id == int(business_id), Business.deleted_at.is_(None)).first()
	if not b:
		raise ApiError("NOT_FOUND", "کسب‌وکار یافت نشد", http_status=404)

	pu = (product_catalog_uuid or "").strip() or None
	if pu:
		p = (
			db.query(Product)
			.filter(
				Product.business_id == int(business_id),
				Product.catalog_public_uuid == pu,
				Product.is_public_catalog.is_(True),
				Product.is_active.is_(True),
			)
			.first()
		)
		if not p:
			raise ApiError("NOT_FOUND", "کالا در کاتالوگ عمومی یافت نشد", http_status=404)

	msg = PublicCatalogContactMessage(
		business_id=int(business_id),
		product_catalog_uuid=pu,
		sender_name=sender_name.strip()[:200],
		sender_contact=sender_contact.strip()[:200],
		message=message.strip()[:2000],
		client_ip=(client_ip or "")[:64] or None,
	)
	db.add(msg)
	db.commit()
	_notify_public_catalog_contact_submitted(db, int(business_id), sender_name.strip()[:200], message.strip()[:500])


def _notify_public_catalog_contact_submitted(
	db: Session,
	business_id: int,
	sender_name: str,
	message_preview: str,
) -> None:
	"""اعلان درون‌برنامه‌ای (و در صورت تنظیم، ایمیل) به مالک کسب‌وکار."""
	b = db.get(Business, business_id)
	if not b or b.owner_id is None:
		return
	try:
		from app.services.notification_service import NotificationService

		title = "پیام جدید از کاتالوگ عمومی کالا"
		body = f"فرستنده: {sender_name}\nمتن: {message_preview}"
		NotificationService(db).send(
			user_id=int(b.owner_id),
			event_key="system.generic",
			context={"subject": title, "message": body},
			preferred_channels=["inapp", "email"],
		)
	except Exception:
		logger.exception("notify business owner for public catalog contact failed business_id=%s", business_id)
