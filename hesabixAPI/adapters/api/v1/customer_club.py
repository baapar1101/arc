from __future__ import annotations

from decimal import Decimal
from typing import Any, Dict, Optional

from fastapi import APIRouter, Depends, Query, Request, Body
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.customer_club_plugin_dependency import check_customer_club_plugin_active
from app.core.i18n import locale_dependency
from app.core.permissions import require_business_access_dep, require_business_permission_dep
from app.core.responses import ApiError, format_datetime_fields, success_response
from app.services import customer_club_analytics_service as analytics_svc
from app.services import customer_club_service as svc
from app.services import customer_club_program_service as program_svc

router = APIRouter(prefix="/customer-club", tags=["customer-club"])


def _ensure_plugin(db: Session, business_id: int) -> None:
	if not check_customer_club_plugin_active(db, business_id):
		raise ApiError(
			"CUSTOMER_CLUB_PLUGIN_NOT_ACTIVE",
			"Customer club add-on is not active for this business.",
			http_status=403,
			details={"plugin_code": "customer_club"},
		)


@router.get("/business/{business_id}/settings")
def get_settings_endpoint(
	request: Request,
	business_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("customer_club", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_ensure_plugin(db, business_id)
	data = svc.get_settings(db, business_id)
	return success_response(data, request)


@router.put("/business/{business_id}/settings")
def update_settings_endpoint(
	request: Request,
	business_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("customer_club", "manage")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_ensure_plugin(db, business_id)
	try:
		data = svc.update_settings(db, business_id, payload)
	except ApiError:
		raise
	except ValueError as e:
		raise ApiError("VALIDATION_ERROR", str(e), http_status=400)
	return success_response(data, request)


@router.get("/business/{business_id}/persons/{person_id}/balance")
def get_balance_endpoint(
	request: Request,
	business_id: int,
	person_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("customer_club", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_ensure_plugin(db, business_id)
	data = svc.get_person_balance(db, business_id, person_id)
	return success_response(data, request)


@router.get("/business/{business_id}/ledger")
def list_ledger_endpoint(
	request: Request,
	business_id: int,
	person_id: Optional[int] = Query(None),
	limit: int = Query(50, ge=1, le=200),
	skip: int = Query(0, ge=0),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("customer_club", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_ensure_plugin(db, business_id)
	items, total = svc.list_ledger(db, business_id, person_id=person_id, limit=limit, skip=skip)
	return success_response({"items": items, "total": total}, request)


@router.post("/business/{business_id}/adjustments")
def adjustment_endpoint(
	request: Request,
	business_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("customer_club", "adjust")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_ensure_plugin(db, business_id)
	pid = payload.get("person_id")
	delta = payload.get("delta_points")
	desc = str(payload.get("description") or "").strip()
	if pid is None:
		raise ApiError(
			"CUSTOMER_CLUB_ADJUSTMENT_PERSON_REQUIRED",
			"person_id is required.",
			http_status=400,
		)
	if delta is None:
		raise ApiError(
			"CUSTOMER_CLUB_ADJUSTMENT_DELTA_REQUIRED",
			"delta_points is required.",
			http_status=400,
		)
	if not desc:
		raise ApiError(
			"CUSTOMER_CLUB_ADJUSTMENT_DESCRIPTION_REQUIRED",
			"description is required.",
			http_status=400,
		)
	try:
		data = svc.manual_adjustment(
			db,
			business_id,
			ctx.get_user_id(),
			int(pid),
			Decimal(str(delta)),
			desc,
		)
	except ApiError:
		raise
	except ValueError as e:
		raise ApiError("VALIDATION_ERROR", str(e), http_status=400)
	return success_response(format_datetime_fields(data, request), request)


@router.get("/business/{business_id}/tiers")
def list_tiers_endpoint(
	request: Request,
	business_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("customer_club", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_ensure_plugin(db, business_id)
	items = svc.list_tiers(db, business_id)
	return success_response({"items": items}, request)


@router.put("/business/{business_id}/tiers")
def replace_tiers_endpoint(
	request: Request,
	business_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("customer_club", "manage")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_ensure_plugin(db, business_id)
	raw = payload.get("tiers") or payload.get("items") or payload
	if not isinstance(raw, list):
		raise ApiError(
			"CUSTOMER_CLUB_TIERS_LIST_REQUIRED",
			"A list of tiers is required.",
			http_status=400,
		)
	try:
		items = svc.replace_tiers(db, business_id, raw)
	except ApiError:
		raise
	except ValueError as e:
		raise ApiError("VALIDATION_ERROR", str(e), http_status=400)
	return success_response({"items": items}, request)


@router.get("/business/{business_id}/analytics/rfm/summary")
def rfm_summary_endpoint(
	request: Request,
	business_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("customer_club", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_ensure_plugin(db, business_id)
	data = analytics_svc.get_rfm_summary(db, business_id)
	return success_response(data, request)


@router.get("/business/{business_id}/analytics/rfm/person-ids")
def rfm_person_ids_endpoint(
	request: Request,
	business_id: int,
	segment_label: Optional[str] = Query(None),
	q: Optional[str] = Query(None, description="Search in person name/code"),
	limit: int = Query(5000, ge=1, le=10000),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("customer_club", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_ensure_plugin(db, business_id)
	data = analytics_svc.list_rfm_person_ids(
		db,
		business_id,
		segment_label=segment_label,
		search=q,
		limit=limit,
	)
	return success_response(data, request)


@router.get("/business/{business_id}/analytics/rfm/persons")
def rfm_persons_endpoint(
	request: Request,
	business_id: int,
	skip: int = Query(0, ge=0),
	limit: int = Query(50, ge=1, le=200),
	segment_label: Optional[str] = Query(None),
	q: Optional[str] = Query(None, description="Search in person name/code"),
	sort: str = Query("monetary_total"),
	sort_dir: str = Query("desc"),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("customer_club", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_ensure_plugin(db, business_id)
	if sort not in (
		"monetary_total",
		"recency_days",
		"frequency_count",
		"clv_estimate",
		"segment_label",
		"composite_score",
	):
		raise ApiError("INVALID_SORT", "Invalid sort field.", http_status=400)
	if sort_dir not in ("asc", "desc"):
		raise ApiError("INVALID_SORT_DIR", "sort_dir must be asc or desc.", http_status=400)
	items, total = analytics_svc.list_rfm_persons(
		db,
		business_id,
		skip=skip,
		limit=limit,
		segment_label=segment_label,
		search=q,
		sort=sort,
		sort_dir=sort_dir,
	)
	return success_response({"items": items, "total": total}, request)


@router.post("/business/{business_id}/analytics/rfm/recalculate")
def rfm_recalculate_endpoint(
	request: Request,
	business_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("customer_club", "manage")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_ensure_plugin(db, business_id)
	try:
		data = analytics_svc.recalculate_rfm_snapshots(db, business_id)
	except ApiError:
		raise
	return success_response(data, request)


@router.get("/business/{business_id}/rewards")
def list_rewards_endpoint(request: Request, business_id: int,
	_: None = Depends(locale_dependency), __: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("customer_club", "view")),
	db: Session = Depends(get_db), _ctx: AuthContext = Depends(get_current_user)) -> dict:
	_ensure_plugin(db, business_id)
	return success_response({"items": program_svc.list_rewards(db, business_id)}, request)


@router.post("/business/{business_id}/rewards")
def create_reward_endpoint(request: Request, business_id: int, payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency), __: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("customer_club", "manage")),
	db: Session = Depends(get_db), _ctx: AuthContext = Depends(get_current_user)) -> dict:
	_ensure_plugin(db, business_id)
	return success_response(program_svc.save_reward(db, business_id, payload), request)


@router.put("/business/{business_id}/rewards/{reward_id}")
def update_reward_endpoint(request: Request, business_id: int, reward_id: int, payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency), __: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("customer_club", "manage")),
	db: Session = Depends(get_db), _ctx: AuthContext = Depends(get_current_user)) -> dict:
	_ensure_plugin(db, business_id)
	return success_response(program_svc.save_reward(db, business_id, payload, reward_id), request)


@router.post("/business/{business_id}/persons/{person_id}/rewards/{reward_id}/redeem")
def redeem_reward_endpoint(request: Request, business_id: int, person_id: int, reward_id: int,
	_: None = Depends(locale_dependency), __: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("customer_club", "redeem")),
	db: Session = Depends(get_db), _ctx: AuthContext = Depends(get_current_user)) -> dict:
	_ensure_plugin(db, business_id)
	return success_response(program_svc.redeem_reward(db, business_id, person_id, reward_id), request)


@router.get("/business/{business_id}/vouchers")
def list_vouchers_endpoint(request: Request, business_id: int, person_id: Optional[int] = Query(None),
	_: None = Depends(locale_dependency), __: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("customer_club", "view")),
	db: Session = Depends(get_db), _ctx: AuthContext = Depends(get_current_user)) -> dict:
	_ensure_plugin(db, business_id)
	return success_response({"items": program_svc.list_vouchers(db, business_id, person_id)}, request)


@router.post("/business/{business_id}/persons/{person_id}/consent")
def update_member_consent_endpoint(request: Request, business_id: int, person_id: int, payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency), __: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("customer_club", "manage")),
	db: Session = Depends(get_db), _ctx: AuthContext = Depends(get_current_user)) -> dict:
	_ensure_plugin(db, business_id)
	return success_response(program_svc.set_member_consent(db, business_id, person_id, payload), request)


@router.post("/business/{business_id}/persons/{person_id}/surveys")
def survey_response_endpoint(request: Request, business_id: int, person_id: int, payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency), __: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("customer_club", "manage")),
	db: Session = Depends(get_db), _ctx: AuthContext = Depends(get_current_user)) -> dict:
	_ensure_plugin(db, business_id)
	return success_response(program_svc.submit_survey_response(db, business_id, person_id, payload), request)


@router.get("/business/{business_id}/persons/{person_id}/profile")
def member_profile_endpoint(request: Request, business_id: int, person_id: int,
	_: None = Depends(locale_dependency), __: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("customer_club", "view")),
	db: Session = Depends(get_db), _ctx: AuthContext = Depends(get_current_user)) -> dict:
	_ensure_plugin(db, business_id)
	return success_response(program_svc.list_member_profile(db, business_id, person_id), request)


@router.post("/business/{business_id}/segments/preview")
def preview_segment_endpoint(request: Request, business_id: int, payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency), __: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("customer_club", "view")),
	db: Session = Depends(get_db), _ctx: AuthContext = Depends(get_current_user)) -> dict:
	_ensure_plugin(db, business_id)
	filters = payload.get("filters") or {}
	if not isinstance(filters, dict):
		raise ApiError("CUSTOMER_CLUB_SEGMENT_INVALID", "filters must be an object.", http_status=400)
	return success_response(program_svc.preview_segment(db, business_id, filters, payload.get("limit", 100)), request)


@router.get("/business/{business_id}/segments/export")
def export_segment_endpoint(request: Request, business_id: int, filters: str = Query("{}"),
	_: None = Depends(locale_dependency), __: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("customer_club", "view")),
	db: Session = Depends(get_db), _ctx: AuthContext = Depends(get_current_user)) -> dict:
	import json
	_ensure_plugin(db, business_id)
	try:
		data = json.loads(filters)
	except (TypeError, ValueError):
		raise ApiError("CUSTOMER_CLUB_SEGMENT_INVALID", "filters must be valid JSON.", http_status=400)
	if not isinstance(data, dict):
		raise ApiError("CUSTOMER_CLUB_SEGMENT_INVALID", "filters must be an object.", http_status=400)
	return success_response(program_svc.preview_segment(db, business_id, data, 10000), request)


@router.get("/business/{business_id}/campaigns")
def list_campaigns_endpoint(request: Request, business_id: int,
	_: None = Depends(locale_dependency), __: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("customer_club", "view")),
	db: Session = Depends(get_db), _ctx: AuthContext = Depends(get_current_user)) -> dict:
	_ensure_plugin(db, business_id)
	return success_response({"items": program_svc.list_campaigns(db, business_id)}, request)


@router.post("/business/{business_id}/campaigns")
def create_campaign_endpoint(request: Request, business_id: int, payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency), __: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("customer_club", "manage")),
	db: Session = Depends(get_db), ctx: AuthContext = Depends(get_current_user)) -> dict:
	_ensure_plugin(db, business_id)
	return success_response(program_svc.save_campaign(db, business_id, payload, ctx.get_user_id()), request)


@router.put("/business/{business_id}/campaigns/{campaign_id}")
def update_campaign_endpoint(request: Request, business_id: int, campaign_id: int, payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency), __: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("customer_club", "manage")),
	db: Session = Depends(get_db), ctx: AuthContext = Depends(get_current_user)) -> dict:
	_ensure_plugin(db, business_id)
	return success_response(program_svc.save_campaign(db, business_id, payload, ctx.get_user_id(), campaign_id), request)


@router.post("/business/{business_id}/campaigns/{campaign_id}/run")
def run_campaign_endpoint(request: Request, business_id: int, campaign_id: int,
	_: None = Depends(locale_dependency), __: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("customer_club", "manage")),
	db: Session = Depends(get_db), _ctx: AuthContext = Depends(get_current_user)) -> dict:
	_ensure_plugin(db, business_id)
	return success_response(program_svc.run_campaign(db, business_id, campaign_id), request)


@router.get("/business/{business_id}/campaigns/{campaign_id}/stats")
def campaign_stats_endpoint(request: Request, business_id: int, campaign_id: int,
	_: None = Depends(locale_dependency), __: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("customer_club", "view")),
	db: Session = Depends(get_db), _ctx: AuthContext = Depends(get_current_user)) -> dict:
	_ensure_plugin(db, business_id)
	return success_response(program_svc.campaign_stats(db, business_id, campaign_id), request)
