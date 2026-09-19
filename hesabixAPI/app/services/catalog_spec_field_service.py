from __future__ import annotations

from typing import Any, Dict, List, Optional

from sqlalchemy import and_, func, select
from sqlalchemy.orm import Session

from adapters.api.v1.schema_models.catalog_spec_field import (
	CatalogSpecFieldCreateRequest,
	CatalogSpecFieldUpdateRequest,
)
from adapters.db.models.business_catalog_spec_field import BusinessCatalogSpecField
from app.core.responses import ApiError
from app.services.product_catalog_profile_service import _options_raw_to_api_list


def _to_dict(obj: BusinessCatalogSpecField) -> Dict[str, Any]:
	return {
		"id": obj.id,
		"business_id": obj.business_id,
		"title": obj.title,
		"description": obj.description,
		"data_type": obj.data_type,
		"options": _options_raw_to_api_list(obj.options),
		"sort_order": obj.sort_order,
		"is_required": obj.is_required,
		"is_active": obj.is_active,
		"created_at": obj.created_at,
		"updated_at": obj.updated_at,
	}


def create_catalog_spec_field(
	db: Session,
	business_id: int,
	payload: CatalogSpecFieldCreateRequest,
) -> Dict[str, Any]:
	title = payload.title.strip()
	dup = db.query(BusinessCatalogSpecField).filter(
		and_(
			BusinessCatalogSpecField.business_id == business_id,
			func.lower(BusinessCatalogSpecField.title) == func.lower(title),
		)
	).first()
	if dup:
		raise ApiError("DUPLICATE_CATALOG_SPEC_FIELD", "عنوان فیلد مشخصات تکراری است", http_status=400)

	data_type = payload.data_type or "text"
	options_dict = None
	if data_type == "select":
		if not payload.options:
			raise ApiError("INVALID_OPTIONS", "برای نوع select باید حداقل یک گزینه مشخص شود", http_status=400)
		options_dict = {"items": payload.options}

	obj = BusinessCatalogSpecField(
		business_id=business_id,
		title=title,
		description=payload.description,
		data_type=data_type,
		options=options_dict,
		sort_order=payload.sort_order,
		is_required=payload.is_required,
		is_active=payload.is_active,
	)
	db.add(obj)
	db.commit()
	db.refresh(obj)
	return {"message": "فیلد مشخصات کاتالوگ ایجاد شد", "data": _to_dict(obj)}


def list_catalog_spec_fields(
	db: Session,
	business_id: int,
	*,
	active_only: bool = False,
	take: int = 100,
	skip: int = 0,
	search: Optional[str] = None,
) -> Dict[str, Any]:
	stmt = select(BusinessCatalogSpecField).where(BusinessCatalogSpecField.business_id == business_id)
	if active_only:
		stmt = stmt.where(BusinessCatalogSpecField.is_active.is_(True))
	if search:
		stmt = stmt.where(BusinessCatalogSpecField.title.ilike(f"%{search.strip()}%"))
	total = db.execute(select(func.count()).select_from(stmt.subquery())).scalar() or 0
	stmt = stmt.order_by(
		BusinessCatalogSpecField.sort_order.asc(),
		BusinessCatalogSpecField.id.asc(),
	).offset(skip).limit(take)
	rows = list(db.execute(stmt).scalars().all())
	items = [_to_dict(r) for r in rows]
	return {
		"items": items,
		"pagination": {
			"total": total,
			"page": (skip // take) + 1 if take else 1,
			"per_page": take,
			"total_pages": (total + take - 1) // take if take else 1,
			"has_next": skip + take < total,
			"has_prev": skip > 0,
		},
	}


def get_catalog_spec_field(db: Session, business_id: int, field_id: int) -> Optional[Dict[str, Any]]:
	obj = db.get(BusinessCatalogSpecField, field_id)
	if not obj or obj.business_id != business_id:
		return None
	return _to_dict(obj)


def update_catalog_spec_field(
	db: Session,
	business_id: int,
	field_id: int,
	payload: CatalogSpecFieldUpdateRequest,
) -> Optional[Dict[str, Any]]:
	obj = db.get(BusinessCatalogSpecField, field_id)
	if not obj or obj.business_id != business_id:
		return None

	if payload.title is not None:
		title = payload.title.strip()
		dup = db.query(BusinessCatalogSpecField).filter(
			and_(
				BusinessCatalogSpecField.business_id == business_id,
				func.lower(BusinessCatalogSpecField.title) == func.lower(title),
				BusinessCatalogSpecField.id != field_id,
			)
		).first()
		if dup:
			raise ApiError("DUPLICATE_CATALOG_SPEC_FIELD", "عنوان فیلد مشخصات تکراری است", http_status=400)
		obj.title = title

	if payload.description is not None:
		obj.description = payload.description
	if payload.sort_order is not None:
		obj.sort_order = payload.sort_order
	if payload.is_required is not None:
		obj.is_required = payload.is_required
	if payload.is_active is not None:
		obj.is_active = payload.is_active

	new_data_type = payload.data_type if payload.data_type is not None else obj.data_type
	if payload.data_type is not None:
		obj.data_type = new_data_type

	if payload.options is not None or payload.data_type is not None:
		if new_data_type == "select":
			opts = payload.options if payload.options is not None else _options_raw_to_api_list(obj.options)
			if not opts:
				raise ApiError("INVALID_OPTIONS", "برای نوع select باید حداقل یک گزینه مشخص شود", http_status=400)
			obj.options = {"items": opts}
		else:
			obj.options = None

	db.commit()
	db.refresh(obj)
	return {"message": "فیلد مشخصات کاتالوگ به‌روزرسانی شد", "data": _to_dict(obj)}


def delete_catalog_spec_field(db: Session, business_id: int, field_id: int) -> bool:
	obj = db.get(BusinessCatalogSpecField, field_id)
	if not obj or obj.business_id != business_id:
		return False
	db.delete(obj)
	db.commit()
	return True


def search_catalog_spec_fields(db: Session, business_id: int, query: Dict[str, Any]) -> Dict[str, Any]:
	take = max(1, min(200, int(query.get("take", 20) or 20)))
	skip = max(0, int(query.get("skip", 0) or 0))
	search = (query.get("search") or "").strip() or None
	active_only = bool(query.get("active_only", False))
	return list_catalog_spec_fields(
		db,
		business_id,
		active_only=active_only,
		take=take,
		skip=skip,
		search=search,
	)
