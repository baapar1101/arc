from __future__ import annotations

from typing import Any, Dict, Optional

from fastapi import APIRouter, Body, Depends, Query, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.i18n import locale_dependency
from app.core.permissions import require_business_access_dep, require_business_permission_dep
from app.core.responses import format_datetime_fields, success_response
from app.services import fixed_asset_reports as reports_svc
from app.services import fixed_asset_service as svc

router = APIRouter(prefix="/fixed-assets", tags=["fixed_assets"])


def _fa_response(data: Any, request: Request, **kwargs) -> dict:
	return success_response(format_datetime_fields(data, request), request, **kwargs)


@router.get("/business/{business_id}/settings")
def get_settings_endpoint(
	request: Request,
	business_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("fixed_assets", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _fa_response(svc.get_settings(db, business_id), request)


@router.put("/business/{business_id}/settings")
def update_settings_endpoint(
	request: Request,
	business_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("fixed_assets", "manage")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _fa_response(svc.update_settings(db, business_id, payload, user_id=ctx.get_user_id()), request)


@router.get("/business/{business_id}/dashboard")
def dashboard_endpoint(
	request: Request,
	business_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("fixed_assets", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _fa_response(svc.get_dashboard(db, business_id), request)


@router.get("/business/{business_id}/classes")
def list_classes_endpoint(
	request: Request,
	business_id: int,
	include_inactive: bool = Query(False),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("fixed_assets", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	items = svc.list_classes(db, business_id, include_inactive=include_inactive)
	return _fa_response({"items": items}, request)


@router.put("/business/{business_id}/classes/{class_id}")
def update_class_endpoint(
	request: Request,
	business_id: int,
	class_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("fixed_assets", "manage")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _fa_response(svc.update_class(db, business_id, class_id, payload, user_id=ctx.get_user_id()), request)


@router.get("/business/{business_id}/locations")
def list_locations_endpoint(
	request: Request,
	business_id: int,
	include_inactive: bool = Query(False),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("fixed_assets", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	items = svc.list_locations(db, business_id, include_inactive=include_inactive)
	return _fa_response({"items": items}, request)


@router.post("/business/{business_id}/locations")
def create_location_endpoint(
	request: Request,
	business_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("fixed_assets", "manage")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _fa_response(svc.create_location(db, business_id, payload, user_id=ctx.get_user_id()), request)


@router.put("/business/{business_id}/locations/{location_id}")
def update_location_endpoint(
	request: Request,
	business_id: int,
	location_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("fixed_assets", "manage")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _fa_response(
		svc.update_location(db, business_id, location_id, payload, user_id=ctx.get_user_id()),
		request,
	)


@router.get("/business/{business_id}/assets")
def list_assets_endpoint(
	request: Request,
	business_id: int,
	status: Optional[str] = Query(None),
	class_id: Optional[int] = Query(None),
	search: Optional[str] = Query(None),
	invoice_id: Optional[int] = Query(None),
	limit: int = Query(100, ge=1, le=500),
	skip: int = Query(0, ge=0),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("fixed_assets", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _fa_response(
		svc.list_assets(
			db,
			business_id,
			status=status,
			class_id=class_id,
			search=search,
			invoice_id=invoice_id,
			limit=limit,
			skip=skip,
		),
		request,
	)


@router.post("/business/{business_id}/assets")
def create_asset_endpoint(
	request: Request,
	business_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("fixed_assets", "operate")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _fa_response(svc.create_asset(db, business_id, payload, user_id=ctx.get_user_id()), request)


@router.get("/business/{business_id}/assets/{asset_id}")
def get_asset_endpoint(
	request: Request,
	business_id: int,
	asset_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("fixed_assets", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _fa_response(svc.get_asset(db, business_id, asset_id), request)


@router.put("/business/{business_id}/assets/{asset_id}")
def update_asset_endpoint(
	request: Request,
	business_id: int,
	asset_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("fixed_assets", "operate")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _fa_response(svc.update_asset(db, business_id, asset_id, payload, user_id=ctx.get_user_id()), request)


@router.delete("/business/{business_id}/assets/{asset_id}")
def delete_asset_endpoint(
	request: Request,
	business_id: int,
	asset_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("fixed_assets", "operate")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _fa_response(svc.delete_asset(db, business_id, asset_id), request)


@router.post("/business/{business_id}/assets/{asset_id}/capitalize")
def capitalize_asset_endpoint(
	request: Request,
	business_id: int,
	asset_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("fixed_assets", "post")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _fa_response(
		svc.capitalize_asset(db, business_id, asset_id, payload, user_id=ctx.get_user_id()),
		request,
	)


@router.post("/business/{business_id}/assets/{asset_id}/idle")
def set_idle_endpoint(
	request: Request,
	business_id: int,
	asset_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("fixed_assets", "operate")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _fa_response(
		svc.set_asset_idle(db, business_id, asset_id, payload, user_id=ctx.get_user_id()),
		request,
	)


@router.post("/business/{business_id}/assets/{asset_id}/resume")
def resume_asset_endpoint(
	request: Request,
	business_id: int,
	asset_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("fixed_assets", "operate")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _fa_response(svc.resume_asset(db, business_id, asset_id, user_id=ctx.get_user_id()), request)


@router.post("/business/{business_id}/assets/{asset_id}/dispose")
def dispose_asset_endpoint(
	request: Request,
	business_id: int,
	asset_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("fixed_assets", "post")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _fa_response(
		svc.dispose_asset(db, business_id, asset_id, payload, user_id=ctx.get_user_id()),
		request,
	)


@router.post("/business/{business_id}/assets/{asset_id}/subsequent-expenditure")
def subsequent_expenditure_endpoint(
	request: Request,
	business_id: int,
	asset_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("fixed_assets", "post")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _fa_response(
		svc.post_subsequent_expenditure(db, business_id, asset_id, payload, user_id=ctx.get_user_id()),
		request,
	)


@router.post("/business/{business_id}/assets/{asset_id}/estimate-change")
def estimate_change_endpoint(
	request: Request,
	business_id: int,
	asset_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("fixed_assets", "manage")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _fa_response(
		svc.change_asset_estimate(db, business_id, asset_id, payload, user_id=ctx.get_user_id()),
		request,
	)


@router.get("/business/{business_id}/depreciation-runs")
def list_runs_endpoint(
	request: Request,
	business_id: int,
	limit: int = Query(50, ge=1, le=200),
	skip: int = Query(0, ge=0),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("fixed_assets", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _fa_response(svc.list_depreciation_runs(db, business_id, limit=limit, skip=skip), request)


@router.post("/business/{business_id}/depreciation-runs")
def create_run_endpoint(
	request: Request,
	business_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("fixed_assets", "operate")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _fa_response(svc.create_depreciation_run(db, business_id, payload, user_id=ctx.get_user_id()), request)


@router.get("/business/{business_id}/depreciation-runs/{run_id}")
def get_run_endpoint(
	request: Request,
	business_id: int,
	run_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("fixed_assets", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _fa_response(svc.get_depreciation_run(db, business_id, run_id), request)


@router.post("/business/{business_id}/depreciation-runs/{run_id}/post")
def post_run_endpoint(
	request: Request,
	business_id: int,
	run_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("fixed_assets", "post")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _fa_response(svc.post_depreciation_run(db, business_id, run_id, user_id=ctx.get_user_id()), request)


@router.delete("/business/{business_id}/depreciation-runs/{run_id}")
def delete_run_endpoint(
	request: Request,
	business_id: int,
	run_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("fixed_assets", "operate")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _fa_response(svc.delete_depreciation_run(db, business_id, run_id), request)


@router.get("/business/{business_id}/reports/{kind}")
def fixed_asset_report_endpoint(
	request: Request,
	business_id: int,
	kind: str,
	from_date: Optional[str] = Query(None),
	to_date: Optional[str] = Query(None),
	class_id: Optional[int] = Query(None),
	status: Optional[str] = Query(None),
	location_id: Optional[int] = Query(None),
	limit: int = Query(500, ge=1, le=2000),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("fixed_assets", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _fa_response(
		reports_svc.get_fixed_asset_report(
			db,
			business_id,
			kind,
			from_date=from_date,
			to_date=to_date,
			class_id=class_id,
			status=status,
			location_id=location_id,
			limit=limit,
		),
		request,
	)
