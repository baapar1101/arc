"""اعتبارسنجی و نرمال‌سازی پروفایل کاتالوگ (شبکهٔ تأمین)."""

from __future__ import annotations

from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

from adapters.db.models.business_catalog_spec_field import BusinessCatalogSpecField
from app.core.responses import ApiError


def _options_raw_to_api_list(raw: Any) -> Optional[List[str]]:
	if raw is None:
		return None
	if isinstance(raw, list):
		return [str(x) for x in raw if str(x).strip()]
	if isinstance(raw, dict):
		items = raw.get("items")
		if isinstance(items, list):
			return [str(x) for x in items if str(x).strip()]
	return None


def normalize_catalog_specifications(raw: Any) -> Optional[List[Dict[str, Any]]]:
	if raw is None:
		return None
	if not isinstance(raw, list):
		raise ApiError("INVALID_CATALOG_SPECIFICATIONS", "مشخصات کاتالوگ باید آرایه باشد", http_status=400)
	out: List[Dict[str, Any]] = []
	for idx, item in enumerate(raw):
		if not isinstance(item, dict):
			raise ApiError("INVALID_CATALOG_SPECIFICATIONS", f"ردیف مشخصات {idx + 1} نامعتبر است", http_status=400)
		label = str(item.get("label") or "").strip()
		value = str(item.get("value") or "").strip()
		if not label:
			continue
		field_id = item.get("field_id")
		if field_id is not None:
			try:
				field_id = int(field_id)
			except (TypeError, ValueError):
				raise ApiError("INVALID_CATALOG_SPECIFICATIONS", f"شناسه فیلد در ردیف {idx + 1} نامعتبر است", http_status=400)
		sort_order = item.get("sort_order", idx)
		try:
			sort_order = int(sort_order)
		except (TypeError, ValueError):
			sort_order = idx
		out.append(
			{
				"field_id": field_id,
				"label": label[:255],
				"value": value[:2000],
				"sort_order": max(0, sort_order),
			}
		)
	out.sort(key=lambda x: (x.get("sort_order", 0), x.get("label", "")))
	return out or None


def validate_catalog_profile_for_publish(
	db: Session,
	business_id: int,
	*,
	is_public_catalog: bool,
	catalog_specifications: Optional[List[Dict[str, Any]]],
) -> None:
	if not is_public_catalog:
		return
	required_fields = (
		db.query(BusinessCatalogSpecField)
		.filter(
			BusinessCatalogSpecField.business_id == business_id,
			BusinessCatalogSpecField.is_active.is_(True),
			BusinessCatalogSpecField.is_required.is_(True),
		)
		.all()
	)
	if not required_fields:
		return
	values_by_field_id: Dict[int, str] = {}
	for item in catalog_specifications or []:
		fid = item.get("field_id")
		if fid is None:
			continue
		val = str(item.get("value") or "").strip()
		if val:
			values_by_field_id[int(fid)] = val
	missing = [f.title for f in required_fields if f.id not in values_by_field_id]
	if missing:
		raise ApiError(
			"CATALOG_REQUIRED_SPECS_MISSING",
			f"فیلدهای اجباری کاتالوگ تکمیل نشده‌اند: {', '.join(missing)}",
			http_status=400,
		)


def catalog_specifications_to_api(raw: Any) -> Optional[List[Dict[str, Any]]]:
	if not raw:
		return None
	if not isinstance(raw, list):
		return None
	out = []
	for item in raw:
		if not isinstance(item, dict):
			continue
		out.append(
			{
				"field_id": item.get("field_id"),
				"label": item.get("label"),
				"value": item.get("value"),
				"sort_order": item.get("sort_order", 0),
			}
		)
	return out or None


_MAX_GALLERY_IMAGES = 12


def normalize_catalog_gallery_file_ids(raw: Any) -> Optional[List[str]]:
	if raw is None:
		return None
	if not isinstance(raw, list):
		raise ApiError("INVALID_CATALOG_GALLERY", "گالری کاتالوگ باید آرایه باشد", http_status=400)
	seen: set[str] = set()
	out: List[str] = []
	for item in raw:
		s = str(item or "").strip()
		if not s or s in seen:
			continue
		if len(s) > 64:
			raise ApiError("INVALID_CATALOG_GALLERY", "شناسه فایل گالری نامعتبر است", http_status=400)
		seen.add(s)
		out.append(s)
		if len(out) > _MAX_GALLERY_IMAGES:
			raise ApiError(
				"CATALOG_GALLERY_TOO_LARGE",
				f"حداکثر {_MAX_GALLERY_IMAGES} تصویر در گالری مجاز است",
				http_status=400,
			)
	return out or None


def catalog_gallery_file_ids_to_api(raw: Any) -> Optional[List[str]]:
	if not raw or not isinstance(raw, list):
		return None
	out = [str(x).strip() for x in raw if str(x).strip()]
	return out or None


def catalog_profile_from_product(obj: Any) -> Dict[str, Any]:
	return {
		"catalog_short_description": getattr(obj, "catalog_short_description", None),
		"catalog_expert_review": getattr(obj, "catalog_expert_review", None),
		"catalog_specifications": catalog_specifications_to_api(getattr(obj, "catalog_specifications", None)),
		"catalog_brand": getattr(obj, "catalog_brand", None),
		"catalog_model": getattr(obj, "catalog_model", None),
		"catalog_country_of_origin": getattr(obj, "catalog_country_of_origin", None),
		"catalog_video_url": getattr(obj, "catalog_video_url", None),
		"catalog_gallery_file_ids": catalog_gallery_file_ids_to_api(getattr(obj, "catalog_gallery_file_ids", None)),
	}
