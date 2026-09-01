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
from adapters.api.v1.schema_models.distribution import (
	AssignmentCreatePayload,
	ReturnRequestCreatePayload,
	ReturnResolvePayload,
	RouteCreatePayload,
	RouteStopPayload,
	RouteUpdatePayload,
	TerritoryCreatePayload,
	TerritoryUpdatePayload,
	VisitCancelPayload,
	VisitCompletePayload,
	VisitHeartbeatPayload,
	VisitStartPayload,
	DistributionSettingsPayload,
	VanCreatePayload,
	VanLoadPayload,
	VanUnloadPayload,
	VanUpdatePayload,
	PersonLocationPayload,
	OfflineSyncPayload,
	SalesTargetPayload,
	SettlementUpsertPayload,
	SettlementConfirmPayload,
)
from app.core.business_calendar import business_today
from app.services import distribution_service as dist_svc
from app.services import distribution_phase3_service as dist_p3
from app.services import distribution_phase4_service as dist_p4
from sqlalchemy.orm import Session

router = APIRouter(prefix="/distribution", tags=["distribution"])


def _parse_iso_date(value: Optional[str], field_name: str) -> Optional[date]:
	if value is None or str(value).strip() == "":
		return None
	try:
		return date.fromisoformat(str(value).strip()[:10])
	except ValueError:
		raise ApiError("VALIDATION_ERROR", f"Invalid {field_name}; use YYYY-MM-DD", http_status=400) from None


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


def require_distribution_settle_dep(
	ctx: AuthContext = Depends(get_current_user),
) -> None:
	"""تأیید تسویه: settle یا manage."""
	if (
		ctx.has_business_permission("distribution", "settle")
		or ctx.has_business_permission("distribution", "manage")
	):
		return
	raise ApiError("FORBIDDEN", "distribution.settle or distribution.manage required", http_status=403)


def require_distribution_approve_returns_dep(
	ctx: AuthContext = Depends(get_current_user),
) -> None:
	"""تأیید مرجوعی: approve_returns یا manage."""
	if (
		ctx.has_business_permission("distribution", "approve_returns")
		or ctx.has_business_permission("distribution", "manage")
	):
		return
	raise ApiError("FORBIDDEN", "distribution.approve_returns or distribution.manage required", http_status=403)


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
	body: TerritoryCreatePayload = Body(...),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = dist_svc.create_territory(db, business_id, body.model_dump(exclude_none=True))
	return success_response(data, request)


@router.put("/business/{business_id}/territories/{territory_id}")
def update_territory(
	request: Request,
	business_id: int = Path(..., gt=0),
	territory_id: int = Path(..., gt=0),
	body: TerritoryUpdatePayload = Body(...),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = dist_svc.update_territory(db, business_id, territory_id, body.model_dump(exclude_none=True))
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
	body: RouteCreatePayload = Body(...),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = dist_svc.create_route(db, business_id, body.model_dump(exclude_none=True))
	return success_response(data, request)


@router.put("/business/{business_id}/routes/{route_id}")
def update_route(
	request: Request,
	business_id: int = Path(..., gt=0),
	route_id: int = Path(..., gt=0),
	body: RouteUpdatePayload = Body(...),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = dist_svc.update_route(db, business_id, route_id, body.model_dump(exclude_none=True))
	return success_response(data, request)


@router.delete("/business/{business_id}/routes/{route_id}")
def delete_route(
	request: Request,
	business_id: int = Path(..., gt=0),
	route_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	dist_svc.delete_route(db, business_id, route_id)
	return success_response({"ok": True}, request)


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
	body: RouteStopPayload = Body(...),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = dist_svc.upsert_route_stop(db, business_id, route_id, body.model_dump(exclude_none=True))
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
	body: AssignmentCreatePayload = Body(...),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = dist_svc.create_assignment(db, business_id, body.model_dump())
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
	d = _parse_iso_date(plan_date, "plan_date") if plan_date else business_today(business_id)
	data = dist_svc.get_daily_plan(db, business_id, uid, d)
	return success_response(data, request)


@router.post("/business/{business_id}/visits/start")
def start_visit(
	request: Request,
	business_id: int = Path(..., gt=0),
	body: VisitStartPayload = Body(...),
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
	data = dist_svc.start_visit(db, business_id, uid, body.model_dump(exclude_none=True), ctx=ctx)
	return success_response(data, request)


@router.post("/business/{business_id}/visits/{visit_id}/complete")
def complete_visit(
	request: Request,
	business_id: int = Path(..., gt=0),
	visit_id: int = Path(..., gt=0),
	body: VisitCompletePayload = Body(...),
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
	data = dist_svc.complete_visit(
		db, business_id, uid, visit_id, body.model_dump(exclude_none=True), allow_manage_override=override
	)
	return success_response(data, request)


@router.post("/business/{business_id}/visits/{visit_id}/cancel")
def cancel_visit(
	request: Request,
	business_id: int = Path(..., gt=0),
	visit_id: int = Path(..., gt=0),
	body: VisitCancelPayload = Body(default_factory=VisitCancelPayload),
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
	data = dist_svc.cancel_visit(
		db,
		business_id,
		uid,
		visit_id,
		body.reason,
		allow_manage_override=override,
	)
	return success_response(data, request)


@router.post("/business/{business_id}/visits/{visit_id}/heartbeat")
def visit_heartbeat(
	request: Request,
	business_id: int = Path(..., gt=0),
	visit_id: int = Path(..., gt=0),
	body: VisitHeartbeatPayload = Body(...),
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
	data = dist_svc.heartbeat_visit(db, business_id, uid, visit_id, body.latitude, body.longitude)
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
	fd = _parse_iso_date(from_date, "from_date") if from_date else None
	td = _parse_iso_date(to_date, "to_date") if to_date else None
	items, total = dist_svc.list_visits(db, business_id, ctx, fd, td, limit, skip)
	return success_response({"items": items, "total": total, "skip": skip, "limit": limit}, request)


@router.post("/business/{business_id}/return-requests")
def create_return(
	request: Request,
	business_id: int = Path(..., gt=0),
	body: ReturnRequestCreatePayload = Body(...),
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
	payload = body.model_dump()
	payload["lines"] = [ln.model_dump(exclude_none=True) for ln in body.lines]
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
	body: ReturnResolvePayload = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_distribution_approve_returns_dep),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	uid = ctx.get_user_id()
	if uid is None:
		raise ApiError("UNAUTHORIZED", "", http_status=401)
	data = dist_svc.resolve_return_request(db, business_id, uid, request_id, body.model_dump(exclude_none=True))
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
	body: DistributionSettingsPayload = Body(...),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = dist_svc.update_distribution_settings(db, business_id, body.model_dump(exclude_none=True))
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
	fd = _parse_iso_date(from_date, "from_date")
	td = _parse_iso_date(to_date, "to_date")
	if fd is None or td is None:
		raise ApiError("VALIDATION_ERROR", "from_date and to_date are required", http_status=400)
	data = dist_svc.get_distribution_reports_dashboard(db, business_id, ctx, fd, td, target_user_id)
	return success_response(data, request)


@router.get("/business/{business_id}/vans")
def list_vans(
	request: Request,
	business_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	return success_response({"items": dist_p3.list_vans(db, business_id, ctx)}, request)


@router.post("/business/{business_id}/vans")
def create_van(
	request: Request,
	business_id: int = Path(..., gt=0),
	body: VanCreatePayload = Body(...),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = dist_p3.create_van(db, business_id, body.model_dump(exclude_none=True))
	return success_response(data, request)


@router.put("/business/{business_id}/vans/{van_id}")
def update_van(
	request: Request,
	business_id: int = Path(..., gt=0),
	van_id: int = Path(..., gt=0),
	body: VanUpdatePayload = Body(...),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = dist_p3.update_van(db, business_id, van_id, body.model_dump(exclude_none=True))
	return success_response(data, request)


@router.get("/business/{business_id}/vans/{van_id}/stock")
def van_stock(
	request: Request,
	business_id: int = Path(..., gt=0),
	van_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	return success_response(dist_p3.get_van_stock(db, business_id, van_id), request)


@router.post("/business/{business_id}/vans/{van_id}/load")
def load_van(
	request: Request,
	business_id: int = Path(..., gt=0),
	van_id: int = Path(..., gt=0),
	body: VanLoadPayload = Body(...),
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
	lines = [ln.model_dump(exclude_none=True) for ln in body.lines]
	data = dist_p3.load_van(db, business_id, uid, van_id, lines, body.source_warehouse_id)
	return success_response(data, request)


@router.post("/business/{business_id}/vans/{van_id}/unload")
def unload_van(
	request: Request,
	business_id: int = Path(..., gt=0),
	van_id: int = Path(..., gt=0),
	body: VanUnloadPayload = Body(...),
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
	lines = [ln.model_dump(exclude_none=True) for ln in body.lines]
	data = dist_p3.unload_van(db, business_id, uid, van_id, lines, body.dest_warehouse_id)
	return success_response(data, request)


@router.get("/business/{business_id}/vans/my-stock")
def my_van_stock(
	request: Request,
	business_id: int = Path(..., gt=0),
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
	van = dist_p3.get_van_for_user(db, business_id, uid)
	if not van:
		return success_response({"van_id": None, "items": []}, request)
	return success_response(dist_p3.get_van_stock(db, business_id, van.id), request)


@router.put("/business/{business_id}/persons/{person_id}/location")
def set_person_location(
	request: Request,
	business_id: int = Path(..., gt=0),
	person_id: int = Path(..., gt=0),
	body: PersonLocationPayload = Body(...),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = dist_p3.update_person_location(db, business_id, person_id, body.latitude, body.longitude)
	return success_response(data, request)


@router.get("/business/{business_id}/routes/{route_id}/optimize")
def optimize_route(
	request: Request,
	business_id: int = Path(..., gt=0),
	route_id: int = Path(..., gt=0),
	plan_date: Optional[str] = Query(None),
	start_latitude: Optional[float] = Query(None),
	start_longitude: Optional[float] = Query(None),
	persist: bool = Query(False),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	d = _parse_iso_date(plan_date, "plan_date") if plan_date else business_today(business_id)
	if persist:
		data = dist_p3.apply_route_optimize(db, business_id, route_id, d, start_latitude, start_longitude)
	else:
		data = dist_p3.optimize_route_plan(db, business_id, route_id, d, start_latitude, start_longitude)
	return success_response(data, request)


@router.get("/business/{business_id}/reports/team-map")
def team_map(
	request: Request,
	business_id: int = Path(..., gt=0),
	plan_date: Optional[str] = Query(None),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	d = _parse_iso_date(plan_date, "plan_date") if plan_date else None
	data = dist_p3.get_team_map(db, business_id, ctx, d)
	return success_response(data, request)


@router.post("/business/{business_id}/sync-offline")
def sync_offline(
	request: Request,
	business_id: int = Path(..., gt=0),
	body: OfflineSyncPayload = Body(...),
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
	data = dist_p3.process_offline_sync(
		db,
		business_id,
		uid,
		body.client_batch_id or "",
		body.actions,
		ctx,
	)
	return success_response(data, request)


# ─── فاز ۴: هدف فروش، تسویه، چاپ ─────────────────────────────────────────────


@router.get("/business/{business_id}/targets")
def list_targets(
	request: Request,
	business_id: int = Path(..., gt=0),
	user_id: Optional[int] = Query(None),
	period_type: Optional[str] = Query(None),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	items = dist_p4.list_sales_targets(db, business_id, ctx, user_id=user_id, period_type=period_type)
	return success_response({"items": items}, request)


@router.post("/business/{business_id}/targets")
def upsert_target(
	request: Request,
	business_id: int = Path(..., gt=0),
	body: SalesTargetPayload = Body(...),
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
	data = dist_p4.upsert_sales_target(db, business_id, uid, body.model_dump(exclude_none=True))
	return success_response(data, request)


@router.delete("/business/{business_id}/targets/{target_id}")
def delete_target(
	request: Request,
	business_id: int = Path(..., gt=0),
	target_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	dist_p4.delete_sales_target(db, business_id, target_id)
	return success_response({"ok": True}, request)


@router.get("/business/{business_id}/settlements/preview")
def settlement_preview(
	request: Request,
	business_id: int = Path(..., gt=0),
	settlement_date: Optional[str] = Query(None),
	target_user_id: Optional[int] = Query(None),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_distribution_operate_dep),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	uid = target_user_id or ctx.get_user_id()
	if uid is None:
		raise ApiError("UNAUTHORIZED", "", http_status=401)
	d = _parse_iso_date(settlement_date, "settlement_date") if settlement_date else business_today(business_id)
	data = dist_p4.preview_settlement(db, business_id, ctx, int(uid), d)
	return success_response(data, request)


@router.get("/business/{business_id}/settlements")
def list_settlements(
	request: Request,
	business_id: int = Path(..., gt=0),
	from_date: Optional[str] = Query(None),
	to_date: Optional[str] = Query(None),
	target_user_id: Optional[int] = Query(None),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	fd = _parse_iso_date(from_date, "from_date") if from_date else None
	td = _parse_iso_date(to_date, "to_date") if to_date else None
	items = dist_p4.list_settlements(db, business_id, ctx, from_date=fd, to_date=td, user_id=target_user_id)
	return success_response({"items": items}, request)


@router.post("/business/{business_id}/settlements")
def upsert_settlement(
	request: Request,
	business_id: int = Path(..., gt=0),
	body: SettlementUpsertPayload = Body(...),
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
	data = dist_p4.upsert_settlement(db, business_id, uid, ctx, body.model_dump(exclude_none=True))
	return success_response(data, request)


@router.post("/business/{business_id}/settlements/{settlement_id}/confirm")
def confirm_settlement(
	request: Request,
	business_id: int = Path(..., gt=0),
	settlement_id: int = Path(..., gt=0),
	body: Optional[SettlementConfirmPayload] = Body(None),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_distribution_settle_dep),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	uid = ctx.get_user_id()
	if uid is None:
		raise ApiError("UNAUTHORIZED", "", http_status=401)
	payload = body.model_dump(exclude_none=True) if body else {}
	data = dist_p4.confirm_settlement(db, business_id, uid, ctx, settlement_id, payload)
	return success_response(data, request)


@router.get("/business/{business_id}/persons/{person_id}/invoices")
def list_person_distribution_invoices(
	request: Request,
	business_id: int = Path(..., gt=0),
	person_id: int = Path(..., gt=0),
	limit: int = Query(20, ge=1, le=50),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	from app.services.distribution_documents import list_person_open_invoices

	items = list_person_open_invoices(db, business_id, person_id, limit=limit)
	return success_response({"items": items}, request)


@router.get("/business/{business_id}/persons/{person_id}/credit-summary")
def person_credit_summary(
	request: Request,
	business_id: int = Path(..., gt=0),
	person_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	data = dist_svc.get_person_credit_summary(db, business_id, person_id)
	return success_response(data, request)


@router.get("/business/{business_id}/daily-plan/pdf")
def daily_plan_pdf(
	request: Request,
	business_id: int = Path(..., gt=0),
	plan_date: Optional[str] = Query(None),
	target_user_id: Optional[int] = Query(None),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "view")),
):
	_ensure_plugin(db, business_id)
	uid = target_user_id or ctx.get_user_id()
	if uid is None:
		raise ApiError("UNAUTHORIZED", "", http_status=401)
	scope = dist_svc._scope_visit_user_id(ctx, business_id)
	if scope is not None and int(uid) != int(scope):
		raise ApiError("FORBIDDEN", "Cannot print another visitor plan", http_status=403)
	d = _parse_iso_date(plan_date, "plan_date") if plan_date else business_today(business_id)
	return dist_p4.export_daily_plan_pdf(db, request, business_id, int(uid), d)


@router.get("/business/{business_id}/vans/{van_id}/loading-list/pdf")
def van_loading_list_pdf(
	request: Request,
	business_id: int = Path(..., gt=0),
	van_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "view")),
):
	_ensure_plugin(db, business_id)
	return dist_p4.export_van_loading_list_pdf(db, request, business_id, van_id)


@router.get("/business/{business_id}/settlements/{settlement_id}/pdf")
def settlement_pdf(
	request: Request,
	business_id: int = Path(..., gt=0),
	settlement_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "view")),
):
	_ensure_plugin(db, business_id)
	return dist_p4.export_settlement_pdf(db, request, business_id, settlement_id)


# ---------------------------------------------------------------------------
# Commercial ops (pre-sell, promo, delivery, load, commission, KPI, assets)
# ---------------------------------------------------------------------------

from adapters.api.v1.schema_models.distribution import (  # noqa: E402
	VisitOrderCreatePayload,
	VisitOrderStatusPayload,
	PromotionUpsertPayload,
	DeliveryTripCreatePayload,
	DeliveryStopCompletePayload,
	LoadPlanCreatePayload,
	CommissionRulePayload,
	CommissionRunPayload,
	ShelfAuditPayload,
	CustomerAssetPayload,
)
from app.services import distribution_commercial_service as dist_c  # noqa: E402


@router.get("/business/{business_id}/orders")
def list_orders(
	request: Request,
	business_id: int = Path(..., gt=0),
	status: Optional[str] = Query(None),
	person_id: Optional[int] = Query(None, gt=0),
	from_date: Optional[str] = Query(None),
	to_date: Optional[str] = Query(None),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	fd = _parse_iso_date(from_date, "from_date") if from_date else None
	td = _parse_iso_date(to_date, "to_date") if to_date else None
	data = dist_c.list_visit_orders(db, business_id, ctx, status=status, from_date=fd, to_date=td, person_id=person_id)
	return success_response(data, request)


@router.post("/business/{business_id}/orders")
def create_order(
	request: Request,
	business_id: int = Path(..., gt=0),
	body: VisitOrderCreatePayload = Body(...),
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
	data = dist_c.create_visit_order(db, business_id, int(uid), body.model_dump(exclude_none=True))
	return success_response(data, request)


@router.post("/business/{business_id}/orders/{order_id}/confirm")
def confirm_order(
	request: Request,
	business_id: int = Path(..., gt=0),
	order_id: int = Path(..., gt=0),
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
	return success_response(dist_c.confirm_visit_order(db, business_id, int(uid), order_id), request)


@router.post("/business/{business_id}/orders/{order_id}/status")
def set_order_status(
	request: Request,
	business_id: int = Path(..., gt=0),
	order_id: int = Path(..., gt=0),
	body: VisitOrderStatusPayload = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	uid = ctx.get_user_id() or 0
	return success_response(
		dist_c.update_order_status(db, business_id, order_id, body.status, actor_user_id=int(uid)),
		request,
	)


@router.get("/business/{business_id}/persons/{person_id}/suggested-order")
def suggested_order(
	request: Request,
	business_id: int = Path(..., gt=0),
	person_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	return success_response(dist_c.suggested_order_for_person(db, business_id, person_id), request)


@router.get("/business/{business_id}/promotions")
def list_promos(
	request: Request,
	business_id: int = Path(..., gt=0),
	all: bool = Query(False),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	return success_response(dist_c.list_promotions(db, business_id, active_only=not all), request)


@router.post("/business/{business_id}/promotions")
def create_promo(
	request: Request,
	business_id: int = Path(..., gt=0),
	body: PromotionUpsertPayload = Body(...),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	return success_response(dist_c.upsert_promotion(db, business_id, body.model_dump(exclude_none=True)), request)


@router.put("/business/{business_id}/promotions/{promo_id}")
def update_promo(
	request: Request,
	business_id: int = Path(..., gt=0),
	promo_id: int = Path(..., gt=0),
	body: PromotionUpsertPayload = Body(...),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	return success_response(
		dist_c.upsert_promotion(db, business_id, body.model_dump(exclude_none=True), promo_id=promo_id),
		request,
	)


@router.delete("/business/{business_id}/promotions/{promo_id}")
def delete_promo(
	request: Request,
	business_id: int = Path(..., gt=0),
	promo_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	dist_c.delete_promotion(db, business_id, promo_id)
	return success_response({"ok": True}, request)


@router.get("/business/{business_id}/delivery-trips")
def list_trips(
	request: Request,
	business_id: int = Path(..., gt=0),
	trip_date: Optional[str] = Query(None),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	d = _parse_iso_date(trip_date, "trip_date") if trip_date else None
	return success_response(dist_c.list_delivery_trips(db, business_id, ctx, trip_date=d), request)


@router.post("/business/{business_id}/delivery-trips")
def create_trip(
	request: Request,
	business_id: int = Path(..., gt=0),
	body: DeliveryTripCreatePayload = Body(...),
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
	return success_response(
		dist_c.create_delivery_trip(db, business_id, int(uid), body.model_dump(exclude_none=True)),
		request,
	)


@router.post("/business/{business_id}/delivery-trips/{trip_id}/start")
def start_trip(
	request: Request,
	business_id: int = Path(..., gt=0),
	trip_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_distribution_operate_dep),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	uid = ctx.get_user_id() or 0
	allow_manage = ctx.has_business_permission("distribution", "manage")
	return success_response(
		dist_c.start_delivery_trip(db, business_id, trip_id, int(uid), allow_manage=allow_manage),
		request,
	)


@router.post("/business/{business_id}/delivery-stops/{stop_id}/complete")
def complete_stop(
	request: Request,
	business_id: int = Path(..., gt=0),
	stop_id: int = Path(..., gt=0),
	body: DeliveryStopCompletePayload = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_distribution_operate_dep),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	uid = ctx.get_user_id() or 0
	return success_response(
		dist_c.complete_delivery_stop(db, business_id, stop_id, int(uid), body.model_dump(exclude_none=True)),
		request,
	)


@router.get("/business/{business_id}/load-plans")
def list_load_plans(
	request: Request,
	business_id: int = Path(..., gt=0),
	plan_date: Optional[str] = Query(None),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	d = _parse_iso_date(plan_date, "plan_date") if plan_date else None
	return success_response(dist_c.list_load_plans(db, business_id, plan_date=d), request)


@router.post("/business/{business_id}/load-plans")
def create_load_plan(
	request: Request,
	business_id: int = Path(..., gt=0),
	body: LoadPlanCreatePayload = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	uid = ctx.get_user_id() or 0
	return success_response(
		dist_c.build_load_plan_from_orders(db, business_id, int(uid), body.model_dump(exclude_none=True)),
		request,
	)


@router.post("/business/{business_id}/load-plans/{plan_id}/confirm")
def confirm_load_plan(
	request: Request,
	business_id: int = Path(..., gt=0),
	plan_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	uid = ctx.get_user_id() or 0
	return success_response(dist_c.confirm_load_plan(db, business_id, plan_id, int(uid)), request)


@router.get("/business/{business_id}/visits/{visit_id}/trail")
def visit_trail(
	request: Request,
	business_id: int = Path(..., gt=0),
	visit_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	return success_response(dist_c.get_visit_trail(db, business_id, visit_id), request)


@router.get("/business/{business_id}/users/{user_id}/day-trail")
def user_day_trail(
	request: Request,
	business_id: int = Path(..., gt=0),
	user_id: int = Path(..., gt=0),
	day: Optional[str] = Query(None),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "reports_team")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	d = _parse_iso_date(day, "day") if day else business_today(business_id)
	return success_response(dist_c.get_user_day_trail(db, business_id, user_id, d), request)


@router.get("/business/{business_id}/commission-rules")
def list_comm_rules(
	request: Request,
	business_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	return success_response(dist_c.list_commission_rules(db, business_id), request)


@router.post("/business/{business_id}/commission-rules")
def create_comm_rule(
	request: Request,
	business_id: int = Path(..., gt=0),
	body: CommissionRulePayload = Body(...),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	return success_response(dist_c.upsert_commission_rule(db, business_id, body.model_dump(exclude_none=True)), request)


@router.post("/business/{business_id}/commission-runs")
def create_comm_run(
	request: Request,
	business_id: int = Path(..., gt=0),
	body: CommissionRunPayload = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	uid = ctx.get_user_id() or 0
	return success_response(
		dist_c.compute_commission_run(db, business_id, int(uid), body.model_dump(exclude_none=True)),
		request,
	)


@router.get("/business/{business_id}/commission-runs")
def list_comm_runs(
	request: Request,
	business_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	return success_response(dist_c.list_commission_runs(db, business_id), request)


@router.post("/business/{business_id}/shelf-audits")
def create_shelf_audit(
	request: Request,
	business_id: int = Path(..., gt=0),
	body: ShelfAuditPayload = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_distribution_operate_dep),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	uid = ctx.get_user_id() or 0
	return success_response(
		dist_c.create_shelf_audit(db, business_id, int(uid), body.model_dump(exclude_none=True)),
		request,
	)


@router.get("/business/{business_id}/shelf-audits")
def list_shelf_audits(
	request: Request,
	business_id: int = Path(..., gt=0),
	person_id: Optional[int] = Query(None, gt=0),
	visit_id: Optional[int] = Query(None, gt=0),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	return success_response(
		dist_c.list_shelf_audits(db, business_id, person_id=person_id, visit_id=visit_id),
		request,
	)


@router.get("/business/{business_id}/customer-assets")
def list_assets(
	request: Request,
	business_id: int = Path(..., gt=0),
	person_id: Optional[int] = Query(None, gt=0),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	return success_response(dist_c.list_customer_assets(db, business_id, person_id), request)


@router.post("/business/{business_id}/customer-assets")
def create_asset(
	request: Request,
	business_id: int = Path(..., gt=0),
	body: CustomerAssetPayload = Body(...),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "manage")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	return success_response(dist_c.upsert_customer_asset(db, business_id, body.model_dump(exclude_none=True)), request)


@router.put("/business/{business_id}/customer-assets/{asset_id}")
def update_asset(
	request: Request,
	business_id: int = Path(..., gt=0),
	asset_id: int = Path(..., gt=0),
	body: CustomerAssetPayload = Body(...),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_distribution_operate_dep),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	return success_response(
		dist_c.upsert_customer_asset(db, business_id, body.model_dump(exclude_none=True), asset_id=asset_id),
		request,
	)


@router.get("/business/{business_id}/reports/commercial-kpi")
def commercial_kpi(
	request: Request,
	business_id: int = Path(..., gt=0),
	from_date: str = Query(...),
	to_date: str = Query(...),
	target_user_id: Optional[int] = Query(None, gt=0),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("distribution", "view")),
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	fd = _parse_iso_date(from_date, "from_date")
	td = _parse_iso_date(to_date, "to_date")
	assert fd and td
	return success_response(
		dist_c.get_commercial_kpi_pack(db, business_id, ctx, fd, td, target_user_id),
		request,
	)
