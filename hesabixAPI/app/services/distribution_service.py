"""منطق افزونه پخش مویرگی و ویزیتوری."""

from __future__ import annotations

from datetime import date, datetime
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy import func, or_
from sqlalchemy.orm import Session, joinedload

from adapters.db.models.distribution import (
	DistributionFieldVisit,
	DistributionReturnRequest,
	DistributionRoute,
	DistributionRouteAssignment,
	DistributionRouteStop,
	DistributionTerritory,
)
from adapters.db.models.person import Person
from app.core.auth_dependency import AuthContext
from app.core.distribution_plugin_dependency import check_distribution_plugin_active
from app.core.responses import ApiError


def _ensure_plugin(db: Session, business_id: int) -> None:
	if not check_distribution_plugin_active(db, business_id):
		raise ApiError(
			"DISTRIBUTION_PLUGIN_NOT_ACTIVE",
			"Distribution field sales add-on is not active for this business.",
			http_status=403,
			details={"plugin_code": "distribution", "required_action": "activate_plugin", "marketplace_url": "/marketplace"},
		)


def _scope_visit_user_id(ctx: AuthContext, business_id: int) -> Optional[int]:
	"""فیلتر بازدیدها: None = همه، وگرنه فقط این کاربر."""
	if ctx.is_superadmin():
		return None
	if ctx.db and ctx.is_business_owner(business_id):
		return None
	if ctx.has_business_permission("distribution", "manage") or ctx.has_business_permission("distribution", "reports_team"):
		return None
	return ctx.get_user_id()


def territory_to_dict(t: DistributionTerritory) -> Dict[str, Any]:
	return {
		"id": t.id,
		"code": t.code,
		"name": t.name,
		"description": t.description,
		"is_active": t.is_active,
		"created_at": t.created_at.isoformat() if t.created_at else None,
		"updated_at": t.updated_at.isoformat() if t.updated_at else None,
	}


def route_to_dict(r: DistributionRoute, territory_name: Optional[str] = None) -> Dict[str, Any]:
	return {
		"id": r.id,
		"code": r.code,
		"name": r.name,
		"description": r.description,
		"is_active": r.is_active,
		"territory_id": r.territory_id,
		"territory_name": territory_name,
		"created_at": r.created_at.isoformat() if r.created_at else None,
		"updated_at": r.updated_at.isoformat() if r.updated_at else None,
	}


def visit_to_dict(v: DistributionFieldVisit, person_name: Optional[str] = None) -> Dict[str, Any]:
	return {
		"id": v.id,
		"person_id": v.person_id,
		"person_name": person_name,
		"user_id": v.user_id,
		"route_id": v.route_id,
		"route_stop_id": v.route_stop_id,
		"status": v.status,
		"started_at": v.started_at.isoformat() if v.started_at else None,
		"ended_at": v.ended_at.isoformat() if v.ended_at else None,
		"outcome": v.outcome,
		"no_order_reason": v.no_order_reason,
		"document_id": v.document_id,
		"deal_id": v.deal_id,
		"crm_activity_id": v.crm_activity_id,
		"notes": v.notes,
	}


def get_summary(db: Session, business_id: int, ctx: AuthContext) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	scope_uid = _scope_visit_user_id(ctx, business_id)

	vq = db.query(DistributionFieldVisit).filter(DistributionFieldVisit.business_id == business_id)
	if scope_uid is not None:
		vq = vq.filter(DistributionFieldVisit.user_id == scope_uid)

	today = datetime.utcnow().date()
	start_today = datetime.combine(today, datetime.min.time())
	end_today = datetime.combine(today, datetime.max.time())
	visits_today = vq.filter(
		DistributionFieldVisit.started_at >= start_today,
		DistributionFieldVisit.started_at <= end_today,
	).count()

	completed_today = vq.filter(
		DistributionFieldVisit.started_at >= start_today,
		DistributionFieldVisit.started_at <= end_today,
		DistributionFieldVisit.status == "completed",
	).count()

	pending_returns = db.query(func.count(DistributionReturnRequest.id)).filter(
		DistributionReturnRequest.business_id == business_id,
		DistributionReturnRequest.status == "pending",
	).scalar()
	if scope_uid is not None:
		pending_returns = (
			db.query(func.count(DistributionReturnRequest.id))
			.filter(
				DistributionReturnRequest.business_id == business_id,
				DistributionReturnRequest.status == "pending",
				DistributionReturnRequest.created_by_user_id == scope_uid,
			)
			.scalar()
		)

	routes_active = (
		db.query(func.count(DistributionRoute.id))
		.filter(DistributionRoute.business_id == business_id, DistributionRoute.is_active == True)  # noqa: E712
		.scalar()
	)

	return {
		"visits_today": visits_today,
		"completed_visits_today": completed_today,
		"pending_return_requests": int(pending_returns or 0),
		"active_routes": int(routes_active or 0),
	}


def list_territories(db: Session, business_id: int) -> List[Dict[str, Any]]:
	_ensure_plugin(db, business_id)
	rows = (
		db.query(DistributionTerritory)
		.filter(DistributionTerritory.business_id == business_id)
		.order_by(DistributionTerritory.code.asc())
		.all()
	)
	return [territory_to_dict(t) for t in rows]


def create_territory(db: Session, business_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	code = str(payload.get("code") or "").strip()
	name = str(payload.get("name") or "").strip()
	if not code or not name:
		raise ApiError("VALIDATION_ERROR", "code and name are required", http_status=400)
	exists = (
		db.query(DistributionTerritory)
		.filter(DistributionTerritory.business_id == business_id, DistributionTerritory.code == code)
		.first()
	)
	if exists:
		raise ApiError("DUPLICATE", "Territory code already exists", http_status=400)
	row = DistributionTerritory(
		business_id=business_id,
		code=code[:50],
		name=name[:255],
		description=(payload.get("description") or None),
		is_active=bool(payload.get("is_active", True)),
	)
	db.add(row)
	db.commit()
	db.refresh(row)
	return territory_to_dict(row)


def update_territory(db: Session, business_id: int, territory_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	row = (
		db.query(DistributionTerritory)
		.filter(DistributionTerritory.id == territory_id, DistributionTerritory.business_id == business_id)
		.first()
	)
	if not row:
		raise ApiError("NOT_FOUND", "Territory not found", http_status=404)
	if "name" in payload:
		row.name = str(payload["name"])[:255]
	if "description" in payload:
		row.description = payload.get("description")
	if "is_active" in payload:
		row.is_active = bool(payload["is_active"])
	row.updated_at = datetime.utcnow()
	db.commit()
	db.refresh(row)
	return territory_to_dict(row)


def delete_territory(db: Session, business_id: int, territory_id: int) -> None:
	_ensure_plugin(db, business_id)
	row = (
		db.query(DistributionTerritory)
		.filter(DistributionTerritory.id == territory_id, DistributionTerritory.business_id == business_id)
		.first()
	)
	if not row:
		raise ApiError("NOT_FOUND", "Territory not found", http_status=404)
	db.query(DistributionRoute).filter(DistributionRoute.territory_id == territory_id).update({"territory_id": None})
	db.delete(row)
	db.commit()


def list_routes(db: Session, business_id: int) -> List[Dict[str, Any]]:
	_ensure_plugin(db, business_id)
	rows = (
		db.query(DistributionRoute)
		.options(joinedload(DistributionRoute.territory))
		.filter(DistributionRoute.business_id == business_id)
		.order_by(DistributionRoute.code.asc())
		.all()
	)
	out = []
	for r in rows:
		tname = r.territory.name if r.territory else None
		out.append(route_to_dict(r, tname))
	return out


def create_route(db: Session, business_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	code = str(payload.get("code") or "").strip()
	name = str(payload.get("name") or "").strip()
	if not code or not name:
		raise ApiError("VALIDATION_ERROR", "code and name are required", http_status=400)
	if (
		db.query(DistributionRoute)
		.filter(DistributionRoute.business_id == business_id, DistributionRoute.code == code)
		.first()
	):
		raise ApiError("DUPLICATE", "Route code already exists", http_status=400)
	tid = payload.get("territory_id")
	if tid is not None:
		tid = int(tid)
		check = db.query(DistributionTerritory).filter(DistributionTerritory.id == tid, DistributionTerritory.business_id == business_id).first()
		if not check:
			raise ApiError("VALIDATION_ERROR", "Invalid territory_id", http_status=400)
	row = DistributionRoute(
		business_id=business_id,
		territory_id=tid,
		code=code[:50],
		name=name[:255],
		description=(payload.get("description") or None),
		is_active=bool(payload.get("is_active", True)),
	)
	db.add(row)
	db.commit()
	db.refresh(row)
	tname = None
	if row.territory_id:
		tr = db.query(DistributionTerritory).filter(DistributionTerritory.id == row.territory_id).first()
		tname = tr.name if tr else None
	return route_to_dict(row, tname)


def update_route(db: Session, business_id: int, route_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	row = db.query(DistributionRoute).filter(DistributionRoute.id == route_id, DistributionRoute.business_id == business_id).first()
	if not row:
		raise ApiError("NOT_FOUND", "Route not found", http_status=404)
	if "name" in payload:
		row.name = str(payload["name"])[:255]
	if "description" in payload:
		row.description = payload.get("description")
	if "is_active" in payload:
		row.is_active = bool(payload["is_active"])
	if "territory_id" in payload:
		tid = payload.get("territory_id")
		if tid is None:
			row.territory_id = None
		else:
			check = db.query(DistributionTerritory).filter(DistributionTerritory.id == int(tid), DistributionTerritory.business_id == business_id).first()
			if not check:
				raise ApiError("VALIDATION_ERROR", "Invalid territory_id", http_status=400)
			row.territory_id = int(tid)
	row.updated_at = datetime.utcnow()
	db.commit()
	db.refresh(row)
	tname = None
	if row.territory_id:
		t = db.query(DistributionTerritory).filter(DistributionTerritory.id == row.territory_id).first()
		tname = t.name if t else None
	return route_to_dict(row, tname)


def list_route_stops(db: Session, business_id: int, route_id: int) -> List[Dict[str, Any]]:
	_ensure_plugin(db, business_id)
	rt = db.query(DistributionRoute).filter(DistributionRoute.id == route_id, DistributionRoute.business_id == business_id).first()
	if not rt:
		raise ApiError("NOT_FOUND", "Route not found", http_status=404)
	stops = (
		db.query(DistributionRouteStop)
		.filter(DistributionRouteStop.route_id == route_id)
		.order_by(DistributionRouteStop.sort_order.asc(), DistributionRouteStop.id.asc())
		.all()
	)
	person_ids = [s.person_id for s in stops]
	persons = {}
	if person_ids:
		for p in db.query(Person).filter(Person.id.in_(person_ids)).all():
			persons[p.id] = (p.alias_name or "").strip() or str(p.id)
	out = []
	for s in stops:
		out.append(
			{
				"id": s.id,
				"person_id": s.person_id,
				"person_name": persons.get(s.person_id),
				"sort_order": s.sort_order,
				"weekday": s.weekday,
				"notes": s.notes,
			}
		)
	return out


def upsert_route_stop(db: Session, business_id: int, route_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	rt = db.query(DistributionRoute).filter(DistributionRoute.id == route_id, DistributionRoute.business_id == business_id).first()
	if not rt:
		raise ApiError("NOT_FOUND", "Route not found", http_status=404)
	person_id = int(payload.get("person_id") or 0)
	if person_id <= 0:
		raise ApiError("VALIDATION_ERROR", "person_id required", http_status=400)
	person = db.query(Person).filter(Person.id == person_id, Person.business_id == business_id).first()
	if not person:
		raise ApiError("NOT_FOUND", "Person not found in this business", http_status=404)
	stop_id = payload.get("id")
	weekday = payload.get("weekday")
	if weekday is not None and weekday != "":
		weekday = int(weekday)
		if weekday < 0 or weekday > 6:
			raise ApiError("VALIDATION_ERROR", "weekday must be 0-6 or null", http_status=400)
	else:
		weekday = None
	sort_order = int(payload.get("sort_order") or 0)
	if stop_id:
		row = db.query(DistributionRouteStop).filter(DistributionRouteStop.id == int(stop_id), DistributionRouteStop.route_id == route_id).first()
		if not row:
			raise ApiError("NOT_FOUND", "Stop not found", http_status=404)
		row.person_id = person_id
		row.sort_order = sort_order
		row.weekday = weekday
		row.notes = payload.get("notes")
		row.updated_at = datetime.utcnow()
	else:
		row = DistributionRouteStop(
			route_id=route_id,
			person_id=person_id,
			sort_order=sort_order,
			weekday=weekday,
			notes=payload.get("notes"),
		)
		db.add(row)
	db.commit()
	db.refresh(row)
	pname = (person.alias_name or "").strip() or str(person.id)
	return {
		"id": row.id,
		"person_id": row.person_id,
		"person_name": pname,
		"sort_order": row.sort_order,
		"weekday": row.weekday,
		"notes": row.notes,
	}


def delete_route_stop(db: Session, business_id: int, route_id: int, stop_id: int) -> None:
	_ensure_plugin(db, business_id)
	rt = db.query(DistributionRoute).filter(DistributionRoute.id == route_id, DistributionRoute.business_id == business_id).first()
	if not rt:
		raise ApiError("NOT_FOUND", "Route not found", http_status=404)
	row = db.query(DistributionRouteStop).filter(DistributionRouteStop.id == stop_id, DistributionRouteStop.route_id == route_id).first()
	if not row:
		raise ApiError("NOT_FOUND", "Stop not found", http_status=404)
	db.delete(row)
	db.commit()


def list_assignments(db: Session, business_id: int, route_id: Optional[int]) -> List[Dict[str, Any]]:
	_ensure_plugin(db, business_id)
	q = db.query(DistributionRouteAssignment).filter(DistributionRouteAssignment.business_id == business_id)
	if route_id:
		q = q.filter(DistributionRouteAssignment.route_id == route_id)
	rows = q.order_by(DistributionRouteAssignment.valid_from.desc()).all()
	out = []
	for a in rows:
		out.append(
			{
				"id": a.id,
				"route_id": a.route_id,
				"user_id": a.user_id,
				"valid_from": a.valid_from.isoformat() if a.valid_from else None,
				"valid_to": a.valid_to.isoformat() if a.valid_to else None,
				"created_at": a.created_at.isoformat() if a.created_at else None,
			}
		)
	return out


def create_assignment(db: Session, business_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	route_id = int(payload.get("route_id") or 0)
	user_id = int(payload.get("user_id") or 0)
	if route_id <= 0 or user_id <= 0:
		raise ApiError("VALIDATION_ERROR", "route_id and user_id required", http_status=400)
	rt = db.query(DistributionRoute).filter(DistributionRoute.id == route_id, DistributionRoute.business_id == business_id).first()
	if not rt:
		raise ApiError("NOT_FOUND", "Route not found", http_status=404)
	vf = payload.get("valid_from")
	if not vf:
		raise ApiError("VALIDATION_ERROR", "valid_from required (YYYY-MM-DD)", http_status=400)
	valid_from = date.fromisoformat(str(vf)[:10])
	valid_to = None
	if payload.get("valid_to"):
		valid_to = date.fromisoformat(str(payload["valid_to"])[:10])
	row = DistributionRouteAssignment(
		business_id=business_id,
		route_id=route_id,
		user_id=user_id,
		valid_from=valid_from,
		valid_to=valid_to,
	)
	db.add(row)
	db.commit()
	db.refresh(row)
	return {
		"id": row.id,
		"route_id": row.route_id,
		"user_id": row.user_id,
		"valid_from": row.valid_from.isoformat(),
		"valid_to": row.valid_to.isoformat() if row.valid_to else None,
	}


def delete_assignment(db: Session, business_id: int, assignment_id: int) -> None:
	_ensure_plugin(db, business_id)
	row = (
		db.query(DistributionRouteAssignment)
		.filter(DistributionRouteAssignment.id == assignment_id, DistributionRouteAssignment.business_id == business_id)
		.first()
	)
	if not row:
		raise ApiError("NOT_FOUND", "Assignment not found", http_status=404)
	db.delete(row)
	db.commit()


def _weekday_matches(plan_date: date, weekday: Optional[int]) -> bool:
	if weekday is None:
		return True
	return int(weekday) == int(plan_date.weekday())


def get_daily_plan(db: Session, business_id: int, target_user_id: int, plan_date: date) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	assignments = (
		db.query(DistributionRouteAssignment)
		.options(joinedload(DistributionRouteAssignment.route))
		.filter(
			DistributionRouteAssignment.business_id == business_id,
			DistributionRouteAssignment.user_id == target_user_id,
			DistributionRouteAssignment.valid_from <= plan_date,
			or_(DistributionRouteAssignment.valid_to.is_(None), DistributionRouteAssignment.valid_to >= plan_date),
		)
		.all()
	)
	items: List[Dict[str, Any]] = []
	for asn in assignments:
		route = asn.route
		if not route or not route.is_active:
			continue
		stops = (
			db.query(DistributionRouteStop)
			.filter(DistributionRouteStop.route_id == route.id)
			.order_by(DistributionRouteStop.sort_order.asc())
			.all()
		)
		for s in stops:
			if not _weekday_matches(plan_date, s.weekday):
				continue
			person = db.query(Person).filter(Person.id == s.person_id).first()
			pname = (person.alias_name or "").strip() if person else None
			items.append(
				{
					"route_id": route.id,
					"route_code": route.code,
					"route_name": route.name,
					"stop_id": s.id,
					"sort_order": s.sort_order,
					"person_id": s.person_id,
					"person_name": pname or str(s.person_id),
					"weekday": s.weekday,
				}
			)
	items.sort(key=lambda x: (x["route_code"], x["sort_order"], x["person_id"]))
	return {"plan_date": plan_date.isoformat(), "user_id": target_user_id, "items": items}


def _active_visit(db: Session, business_id: int, user_id: int) -> Optional[DistributionFieldVisit]:
	return (
		db.query(DistributionFieldVisit)
		.filter(
			DistributionFieldVisit.business_id == business_id,
			DistributionFieldVisit.user_id == user_id,
			DistributionFieldVisit.status == "in_progress",
		)
		.order_by(DistributionFieldVisit.started_at.desc())
		.first()
	)


def start_visit(
	db: Session,
	business_id: int,
	user_id: int,
	payload: Dict[str, Any],
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	if _active_visit(db, business_id, user_id):
		raise ApiError("CONFLICT", "یک ویزیت باز دارید؛ ابتدا آن را تکمیل کنید.", http_status=409)
	person_id = int(payload.get("person_id") or 0)
	if person_id <= 0:
		raise ApiError("VALIDATION_ERROR", "person_id required", http_status=400)
	person = db.query(Person).filter(Person.id == person_id, Person.business_id == business_id).first()
	if not person:
		raise ApiError("NOT_FOUND", "Person not found", http_status=404)
	route_id = payload.get("route_id")
	route_stop_id = payload.get("route_stop_id")
	v = DistributionFieldVisit(
		business_id=business_id,
		person_id=person_id,
		user_id=user_id,
		route_id=int(route_id) if route_id else None,
		route_stop_id=int(route_stop_id) if route_stop_id else None,
		status="in_progress",
		started_at=datetime.utcnow(),
		notes=payload.get("notes"),
	)
	db.add(v)
	db.commit()
	db.refresh(v)
	pname = (person.alias_name or "").strip()
	return visit_to_dict(v, pname)


def complete_visit(
	db: Session,
	business_id: int,
	user_id: int,
	visit_id: int,
	payload: Dict[str, Any],
	allow_manage_override: bool = False,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	v = db.query(DistributionFieldVisit).filter(DistributionFieldVisit.id == visit_id, DistributionFieldVisit.business_id == business_id).first()
	if not v:
		raise ApiError("NOT_FOUND", "Visit not found", http_status=404)
	if v.user_id != user_id and not allow_manage_override:
		raise ApiError("FORBIDDEN", "Only the assigned visitor can complete this visit", http_status=403)
	if v.status != "in_progress":
		raise ApiError("VALIDATION_ERROR", "Visit is not in progress", http_status=400)
	outcome = str(payload.get("outcome") or "").strip()
	if outcome not in ("order", "no_order", "cancelled"):
		raise ApiError("VALIDATION_ERROR", "outcome must be order | no_order | cancelled", http_status=400)
	v.status = "completed"
	v.ended_at = datetime.utcnow()
	v.outcome = outcome
	v.no_order_reason = (payload.get("no_order_reason") or None)
	if payload.get("document_id"):
		v.document_id = int(payload["document_id"])
	if payload.get("deal_id"):
		v.deal_id = int(payload["deal_id"])
	if payload.get("notes"):
		v.notes = str(payload["notes"])
	v.updated_at = datetime.utcnow()

	summary_parts = [f"ویزیت میدانی — نتیجه: {outcome}"]
	if v.notes:
		summary_parts.append(str(v.notes))
	summary = "\n".join(summary_parts)

	crm_activity_id = _create_visit_crm_activity(db, business_id, v, user_id, summary)
	if crm_activity_id:
		v.crm_activity_id = crm_activity_id

	db.commit()
	db.refresh(v)

	try:
		from app.services.workflow.workflow_trigger_service import trigger_distribution_visit_completed

		trigger_distribution_visit_completed(db, business_id, v.id, user_id)
	except Exception:
		import logging

		logging.getLogger(__name__).warning("distribution workflow trigger failed", exc_info=True)

	person = db.query(Person).filter(Person.id == v.person_id).first()
	pname = (person.alias_name or "").strip() if person else None
	return visit_to_dict(v, pname)


def _create_visit_crm_activity(db: Session, business_id: int, visit: DistributionFieldVisit, user_id: int, summary: str) -> Optional[int]:
	import logging

	logger = logging.getLogger(__name__)
	try:
		from adapters.db.models.crm import CrmActivity
		from app.services.document_numbering_service import generate_document_code
		from app.services.workflow.workflow_trigger_service import trigger_crm_activity_created

		code = generate_document_code(db, business_id, "crm_activity", date.today())
		act = CrmActivity(
			business_id=business_id,
			person_id=visit.person_id,
			lead_id=None,
			code=code,
			activity_type="note",
			subject="ویزیت میدانی / پخش مویرگی",
			description=summary[:8000] if summary else None,
			activity_date=datetime.utcnow(),
			deal_id=visit.deal_id,
			created_by_user_id=user_id,
			extra_info={"distribution_visit_id": visit.id},
		)
		db.add(act)
		db.flush()
		trigger_crm_activity_created(db, business_id, act.id, user_id)
		return int(act.id)
	except Exception as e:
		logger.warning("CRM activity for distribution visit skipped: %s", e)
		return None


def cancel_visit(
	db: Session,
	business_id: int,
	user_id: int,
	visit_id: int,
	reason: Optional[str],
	allow_manage_override: bool = False,
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	v = db.query(DistributionFieldVisit).filter(DistributionFieldVisit.id == visit_id, DistributionFieldVisit.business_id == business_id).first()
	if not v:
		raise ApiError("NOT_FOUND", "Visit not found", http_status=404)
	if v.user_id != user_id and not allow_manage_override:
		raise ApiError("FORBIDDEN", "Only the visitor can cancel", http_status=403)
	if v.status != "in_progress":
		raise ApiError("VALIDATION_ERROR", "Visit is not in progress", http_status=400)
	v.status = "cancelled"
	v.ended_at = datetime.utcnow()
	v.outcome = "cancelled"
	v.no_order_reason = reason
	v.updated_at = datetime.utcnow()
	db.commit()
	db.refresh(v)
	person = db.query(Person).filter(Person.id == v.person_id).first()
	pname = (person.alias_name or "").strip() if person else None
	return visit_to_dict(v, pname)


def list_visits(
	db: Session,
	business_id: int,
	ctx: AuthContext,
	from_date: Optional[date],
	to_date: Optional[date],
	limit: int,
	skip: int,
) -> Tuple[List[Dict[str, Any]], int]:
	_ensure_plugin(db, business_id)
	q = db.query(DistributionFieldVisit).filter(DistributionFieldVisit.business_id == business_id)
	uid = _scope_visit_user_id(ctx, business_id)
	if uid is not None:
		q = q.filter(DistributionFieldVisit.user_id == uid)
	if from_date:
		q = q.filter(func.date(DistributionFieldVisit.started_at) >= from_date)
	if to_date:
		q = q.filter(func.date(DistributionFieldVisit.started_at) <= to_date)
	total = q.count()
	rows = q.order_by(DistributionFieldVisit.started_at.desc()).offset(skip).limit(limit).all()
	pids = [r.person_id for r in rows]
	pmap = {}
	if pids:
		for p in db.query(Person).filter(Person.id.in_(pids)).all():
			pmap[p.id] = (p.alias_name or "").strip()
	return [visit_to_dict(r, pmap.get(r.person_id)) for r in rows], total


def create_return_request(db: Session, business_id: int, user_id: int, payload: Dict[str, Any]) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	person_id = int(payload.get("person_id") or 0)
	if person_id <= 0:
		raise ApiError("VALIDATION_ERROR", "person_id required", http_status=400)
	person = db.query(Person).filter(Person.id == person_id, Person.business_id == business_id).first()
	if not person:
		raise ApiError("NOT_FOUND", "Person not found", http_status=404)
	lines = payload.get("lines") or []
	if not isinstance(lines, list) or not lines:
		raise ApiError("VALIDATION_ERROR", "lines must be a non-empty list", http_status=400)
	vid = payload.get("visit_id")
	row = DistributionReturnRequest(
		business_id=business_id,
		person_id=person_id,
		visit_id=int(vid) if vid else None,
		status="pending",
		lines=lines,
		notes=payload.get("notes"),
		created_by_user_id=user_id,
	)
	db.add(row)
	db.commit()
	db.refresh(row)
	return {
		"id": row.id,
		"person_id": row.person_id,
		"visit_id": row.visit_id,
		"status": row.status,
		"lines": row.lines,
		"notes": row.notes,
		"created_at": row.created_at.isoformat() if row.created_at else None,
	}


def list_return_requests(db: Session, business_id: int, ctx: AuthContext, status: Optional[str]) -> List[Dict[str, Any]]:
	_ensure_plugin(db, business_id)
	q = db.query(DistributionReturnRequest).filter(DistributionReturnRequest.business_id == business_id)
	uid = _scope_visit_user_id(ctx, business_id)
	if uid is not None:
		q = q.filter(DistributionReturnRequest.created_by_user_id == uid)
	if status:
		q = q.filter(DistributionReturnRequest.status == status)
	rows = q.order_by(DistributionReturnRequest.created_at.desc()).limit(500).all()
	out = []
	for r in rows:
		out.append(
			{
				"id": r.id,
				"person_id": r.person_id,
				"visit_id": r.visit_id,
				"status": r.status,
				"lines": r.lines,
				"notes": r.notes,
				"resolved_document_id": r.resolved_document_id,
				"created_by_user_id": r.created_by_user_id,
				"created_at": r.created_at.isoformat() if r.created_at else None,
			}
		)
	return out


def resolve_return_request(
	db: Session,
	business_id: int,
	resolver_user_id: int,
	request_id: int,
	payload: Dict[str, Any],
) -> Dict[str, Any]:
	_ensure_plugin(db, business_id)
	row = (
		db.query(DistributionReturnRequest)
		.filter(DistributionReturnRequest.id == request_id, DistributionReturnRequest.business_id == business_id)
		.first()
	)
	if not row:
		raise ApiError("NOT_FOUND", "Return request not found", http_status=404)
	new_status = str(payload.get("status") or "").strip()
	if new_status not in ("approved", "rejected"):
		raise ApiError("VALIDATION_ERROR", "status must be approved or rejected", http_status=400)
	row.status = new_status
	row.resolved_by_user_id = resolver_user_id
	row.resolved_at = datetime.utcnow()
	if payload.get("resolved_document_id"):
		row.resolved_document_id = int(payload["resolved_document_id"])
	row.updated_at = datetime.utcnow()
	db.commit()
	db.refresh(row)
	return {
		"id": row.id,
		"status": row.status,
		"resolved_document_id": row.resolved_document_id,
		"resolved_at": row.resolved_at.isoformat() if row.resolved_at else None,
	}
