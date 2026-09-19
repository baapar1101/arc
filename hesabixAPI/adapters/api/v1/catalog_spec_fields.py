from typing import Any, Dict

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.orm import Session

from adapters.api.v1.schemas import QueryInfo

from adapters.api.v1.schema_models.catalog_spec_field import (
	CatalogSpecFieldCreateRequest,
	CatalogSpecFieldUpdateRequest,
)
from adapters.db.models.business_catalog_spec_field import BusinessCatalogSpecField
from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.permissions import (
	require_business_access,
	require_business_permission_by_entity_dep,
	require_business_permission_dep,
)
from app.core.responses import ApiError, format_datetime_fields, success_response
from app.services.catalog_spec_field_service import (
	create_catalog_spec_field,
	delete_catalog_spec_field,
	get_catalog_spec_field,
	list_catalog_spec_fields,
	search_catalog_spec_fields,
	update_catalog_spec_field,
)

router = APIRouter(prefix="/catalog-spec-fields", tags=["catalog-spec-fields"])


@router.post("/business/{business_id}")
@require_business_access("business_id")
def create_business_catalog_spec_field(
	request: Request,
	business_id: int,
	payload: CatalogSpecFieldCreateRequest,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
	_: None = Depends(require_business_permission_dep("products", "edit")),
) -> Dict[str, Any]:
	result = create_catalog_spec_field(db, business_id, payload)
	return success_response(
		data=format_datetime_fields(result["data"], request),
		request=request,
		message=result.get("message"),
	)


@router.get("/business/{business_id}")
@require_business_access("business_id")
def list_business_catalog_spec_fields(
	request: Request,
	business_id: int,
	active_only: bool = Query(False),
	take: int = Query(100, ge=1, le=200),
	skip: int = Query(0, ge=0),
	search: str | None = Query(None),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
	_: None = Depends(require_business_permission_dep("products", "view")),
) -> Dict[str, Any]:
	result = list_catalog_spec_fields(
		db,
		business_id,
		active_only=active_only,
		take=take,
		skip=skip,
		search=search,
	)
	formatted = format_datetime_fields(result, request)
	return success_response(data=formatted, request=request)


@router.post("/business/{business_id}/search")
@require_business_access("business_id")
def search_business_catalog_spec_fields(
	request: Request,
	business_id: int,
	query: QueryInfo,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
	_: None = Depends(require_business_permission_dep("products", "view")),
) -> Dict[str, Any]:
	result = search_catalog_spec_fields(
		db,
		business_id,
		{
			"take": query.take,
			"skip": query.skip,
			"search": query.search,
		},
	)
	formatted = format_datetime_fields(result, request)
	return success_response(data=formatted, request=request)


@router.get("/business/{business_id}/{field_id}")
@require_business_access("business_id")
def get_business_catalog_spec_field(
	request: Request,
	business_id: int,
	field_id: int,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
	_: None = Depends(
		require_business_permission_by_entity_dep(
			"products",
			"view",
			BusinessCatalogSpecField,
			"field_id",
		)
	),
) -> Dict[str, Any]:
	data = get_catalog_spec_field(db, business_id, field_id)
	if not data:
		raise ApiError("NOT_FOUND", "فیلد مشخصات یافت نشد", http_status=404)
	return success_response(data=format_datetime_fields(data, request), request=request)


@router.put("/business/{business_id}/{field_id}")
@require_business_access("business_id")
def update_business_catalog_spec_field(
	request: Request,
	business_id: int,
	field_id: int,
	payload: CatalogSpecFieldUpdateRequest,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
	_: None = Depends(
		require_business_permission_by_entity_dep(
			"products",
			"edit",
			BusinessCatalogSpecField,
			"field_id",
		)
	),
) -> Dict[str, Any]:
	result = update_catalog_spec_field(db, business_id, field_id, payload)
	if not result:
		raise ApiError("NOT_FOUND", "فیلد مشخصات یافت نشد", http_status=404)
	return success_response(
		data=format_datetime_fields(result["data"], request),
		request=request,
		message=result.get("message"),
	)


@router.delete("/business/{business_id}/{field_id}")
@require_business_access("business_id")
def delete_business_catalog_spec_field(
	request: Request,
	business_id: int,
	field_id: int,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
	_: None = Depends(
		require_business_permission_by_entity_dep(
			"products",
			"edit",
			BusinessCatalogSpecField,
			"field_id",
		)
	),
) -> Dict[str, Any]:
	ok = delete_catalog_spec_field(db, business_id, field_id)
	if not ok:
		raise ApiError("NOT_FOUND", "فیلد مشخصات یافت نشد", http_status=404)
	return success_response(data={"deleted": True}, request=request, message="فیلد مشخصات حذف شد")
