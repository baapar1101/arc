"""API افزونه پخش مویرگی و ویزیتوری."""

from __future__ import annotations

from datetime import date, datetime
from typing import Any, Dict, Optional

from fastapi import APIRouter, Body, Depends, Path, Query, Request

from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.distribution_plugin_dependency import check_distribution_plugin_active
from app.core.i18n import locale_dependency
from app.core.permissions import require_business_access_dep, require_business_permission_dep
from app.core.responses import ApiError, success_response
from app.services import distribution_service as dist_svc
from sqlalchemy.orm import Session

router = APIRouter(prefix="/distribution", tags=["distribution"])


def _ensure_plugin(db: Session, business_id: int) -> None:
	if not check_distribution_plugin_active(db, business_id):
		raise ApiError(
			"DISTRIBUTION_PLUGIN_NOT_ACTIVE",
			"Distribution add-on is not active.",
			http_status=403,
			details={"plugin_code": "distribution"},
		)


def require_distribution_operate_dep(
	ctx: AuthContext = Depends(get_current_user),
) -> None:
	"""عملیات میدانی: operate یا manage."""
	if ctx.has_business_permission("distribution", "operate") or ctx.has_business_permission("distribution", "manage"):
		return
	raise ApiError("FORBIDDEN", "distribution.operate or distribution.manage required", http_status=403)


@router.get("/business/{business_id}/summary")
def get_summary(
	request: Request,
	business_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = dist_svc.get_summary(db, business_id, ctx)
	return success_response(data, request)


@router.get("/business/{business_id}/territories")
def list_territories(
	request: Request,
	business_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	return success_response({"items": dist_svc.list_territories(db, business_id, ctx)}, request)


@router.post("/business/{business_id}/territories")
def create_territory(
	request: Request,
	business_id: int = Path(..., gt=0),
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = dist_svc.create_territory(db, business_id, payload)
	return success_response(data, request)


@router.put("/business/{business_id}/territories/{territory_id}")
def update_territory(
	request: Request,
	business_id: int = Path(..., gt=0),
	territory_id: int = Path(..., gt=0),
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = dist_svc.update_territory(db, business_id, territory_id, payload)
	return success_response(data, request)


@router.delete("/business/{business_id}/territories/{territory_id}")
def delete_territory(
	request: Request,
	business_id: int = Path(..., gt=0),
	territory_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	dist_svc.delete_territory(db, business_id, territory_id)
	return success_response({"ok": True}, request)


@router.get("/business/{business_id}/routes")
def list_routes(
	request: Request,
	business_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	return success_response({"items": dist_svc.list_routes(db, business_id, ctx)}, request)


@router.post("/business/{business_id}/routes")
def create_route(
	request: Request,
	business_id: int = Path(..., gt=0),
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = dist_svc.create_route(db, business_id, payload)
	return success_response(data, request)


@router.put("/business/{business_id}/routes/{route_id}")
def update_route(
	request: Request,
	business_id: int = Path(..., gt=0),
	route_id: int = Path(..., gt=0),
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = dist_svc.update_route(db, business_id, route_id, payload)
	return success_response(data, request)


@router.get("/business/{business_id}/routes/{route_id}/stops")
def list_stops(
	request: Request,
	business_id: int = Path(..., gt=0),
	route_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = dist_svc.list_route_stops(db, business_id, route_id, ctx)
	return success_response({"items": data}, request)


@router.post("/business/{business_id}/routes/{route_id}/stops")
def upsert_stop(
	request: Request,
	business_id: int = Path(..., gt=0),
	route_id: int = Path(..., gt=0),
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = dist_svc.upsert_route_stop(db, business_id, route_id, payload)
	return success_response(data, request)


@router.delete("/business/{business_id}/routes/{route_id}/stops/{stop_id}")
def delete_stop(
	request: Request,
	business_id: int = Path(..., gt=0),
	route_id: int = Path(..., gt=0),
	stop_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	dist_svc.delete_route_stop(db, business_id, route_id, stop_id)
	return success_response({"ok": True}, request)


@router.get("/business/{business_id}/assignments")
def list_assignments(
	request: Request,
	business_id: int = Path(..., gt=0),
	route_id: Optional[int] = Query(None),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = dist_svc.list_assignments(db, business_id, route_id, ctx)
	return success_response({"items": data}, request)


@router.post("/business/{business_id}/assignments")
def create_assignment(
	request: Request,
	business_id: int = Path(..., gt=0),
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = dist_svc.create_assignment(db, business_id, payload)
	return success_response(data, request)


@router.delete("/business/{business_id}/assignments/{assignment_id}")
def delete_assignment(
	request: Request,
	business_id: int = Path(..., gt=0),
	assignment_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	dist_svc.delete_assignment(db, business_id, assignment_id)
	return success_response({"ok": True}, request)


@router.get("/business/{business_id}/daily-plan")
def daily_plan(
	request: Request,
	business_id: int = Path(..., gt=0),
	plan_date: Optional[str] = Query(None, description="YYYY-MM-DD"),
	target_user_id: Optional[int] = Query(None, description="برای سرپرست — ویزیتور دیگر"),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	uid = ctx.get_user_id()
	if uid is None:
		raise ApiError("UNAUTHORIZED", "No user id", http_status=401)
	can_team = ctx.has_business_permission("distribution", "manage") or ctx.has_business_permission(
		"distribution", "reports_team"
	)
	can_field = ctx.has_business_permission("distribution", "operate") or ctx.has_business_permission(
		"distribution", "manage"
	)
	if target_user_id is not None:
		if not can_team:
			raise ApiError("FORBIDDEN", "Only managers can load another user's plan", http_status=403)
		uid = int(target_user_id)
	elif not can_field and not ctx.has_business_permission("distribution", "reports_team"):
		raise ApiError(
			"FORBIDDEN",
			"distribution.operate or distribution.manage or distribution.reports_team required for daily plan",
			http_status=403,
		)
	d = date.fromisoformat(plan_date[:10]) if plan_date else datetime.utcnow().date()
	data = dist_svc.get_daily_plan(db, business_id, uid, d)
	return success_response(data, request)


@router.post("/business/{business_id}/visits/start")
def start_visit(
	request: Request,
	business_id: int = Path(..., gt=0),
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_distribution_operate_dep),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	uid = ctx.get_user_id()
	if uid is None:
		raise ApiError("UNAUTHORIZED", "", http_status=401)
	data = dist_svc.start_visit(db, business_id, uid, payload)
	return success_response(data, request)


@router.post("/business/{business_id}/visits/{visit_id}/complete")
def complete_visit(
	request: Request,
	business_id: int = Path(..., gt=0),
	visit_id: int = Path(..., gt=0),
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_distribution_operate_dep),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	uid = ctx.get_user_id()
	if uid is None:
		raise ApiError("UNAUTHORIZED", "", http_status=401)
	override = ctx.has_business_permission("distribution", "manage")
	data = dist_svc.complete_visit(db, business_id, uid, visit_id, payload, allow_manage_override=override)
	return success_response(data, request)


@router.post("/business/{business_id}/visits/{visit_id}/cancel")
def cancel_visit(
	request: Request,
	business_id: int = Path(..., gt=0),
	visit_id: int = Path(..., gt=0),
	payload: Dict[str, Any] = Body(default={}),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_distribution_operate_dep),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	uid = ctx.get_user_id()
	if uid is None:
		raise ApiError("UNAUTHORIZED", "", http_status=401)
	reason = (payload or {}).get("reason")
	override = ctx.has_business_permission("distribution", "manage")
	data = dist_svc.cancel_visit(
		db,
		business_id,
		uid,
		visit_id,
		str(reason) if reason else None,
		allow_manage_override=override,
	)
	return success_response(data, request)


@router.get("/business/{business_id}/visits")
def list_visits(
	request: Request,
	business_id: int = Path(..., gt=0),
	from_date: Optional[str] = Query(None),
	to_date: Optional[str] = Query(None),
	limit: int = Query(50, ge=1, le=200),
	skip: int = Query(0, ge=0),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	fd = date.fromisoformat(from_date) if from_date else None
	td = date.fromisoformat(to_date) if to_date else None
	items, total = dist_svc.list_visits(db, business_id, ctx, fd, td, limit, skip)
	return success_response({"items": items, "total": total, "skip": skip, "limit": limit}, request)


@router.post("/business/{business_id}/return-requests")
def create_return(
	request: Request,
	business_id: int = Path(..., gt=0),
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_distribution_operate_dep),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	uid = ctx.get_user_id()
	if uid is None:
		raise ApiError("UNAUTHORIZED", "", http_status=401)
	data = dist_svc.create_return_request(db, business_id, uid, payload)
	return success_response(data, request)


@router.get("/business/{business_id}/return-requests")
def list_returns(
	request: Request,
	business_id: int = Path(..., gt=0),
	status: Optional[str] = Query(None),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = dist_svc.list_return_requests(db, business_id, ctx, status)
	return success_response({"items": data}, request)


@router.post("/business/{business_id}/return-requests/{request_id}/resolve")
def resolve_return(
	request: Request,
	business_id: int = Path(..., gt=0),
	request_id: int = Path(..., gt=0),
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	uid = ctx.get_user_id()
	if uid is None:
		raise ApiError("UNAUTHORIZED", "", http_status=401)
	data = dist_svc.resolve_return_request(db, business_id, uid, request_id, payload)
	return success_response(data, request)


@router.get("/business/{business_id}/settings")
def get_distribution_settings(
	request: Request,
	business_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = dist_svc.settings_to_dict(dist_svc.get_or_create_distribution_settings(db, business_id))
	return success_response(data, request)


@router.put("/business/{business_id}/settings")
def put_distribution_settings(
	request: Request,
	business_id: int = Path(..., gt=0),
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = dist_svc.update_distribution_settings(db, business_id, payload)
	return success_response(data, request)


@router.get("/business/{business_id}/reports/dashboard")
def distribution_reports_dashboard(
	request: Request,
	business_id: int = Path(..., gt=0),
	from_date: str = Query(..., description="YYYY-MM-DD"),
	to_date: str = Query(..., description="YYYY-MM-DD"),
	target_user_id: Optional[int] = Query(None),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	fd = date.fromisoformat(from_date[:10])
	td = date.fromisoformat(to_date[:10])
	data = dist_svc.get_distribution_reports_dashboard(db, business_id, ctx, fd, td, target_user_id)
	return success_response(data, request)
