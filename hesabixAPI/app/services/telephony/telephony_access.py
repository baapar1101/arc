"""محدوده دسترسی تلفن: اپراتور / سرپرست تیم / مدیر."""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, FrozenSet, Iterable, Optional

from sqlalchemy import or_
from sqlalchemy.orm import Session, joinedload

from adapters.db.models.business import Business
from adapters.db.models.telephony import (
	TelephonyAuditLog,
	TelephonyCall,
	TelephonyExtension,
	TelephonyTeamSupervisor,
	TelephonyUserExtension,
)
from adapters.db.models.user import User
from adapters.db.repositories.business_permission_repo import BusinessPermissionRepository
from app.core.business_membership import membership_is_active
from app.core.permissions import has_business_permission_for_business
from app.core.responses import ApiError


def _now() -> datetime:
	return datetime.utcnow()


def user_display_name(user: Optional[User]) -> str:
	if not user:
		return ""
	name = f"{user.first_name or ''} {user.last_name or ''}".strip()
	return name or user.email or user.mobile or f"#{user.id}"


def has_telephony_perm(auth_ctx, db: Session, business_id: int, action: str) -> bool:
	if auth_ctx is None:
		return False
	return has_business_permission_for_business(auth_ctx, db, business_id, "telephony", action)


def is_business_member(db: Session, business_id: int, user_id: int) -> bool:
	business = db.get(Business, business_id)
	if business and int(business.owner_id) == int(user_id):
		return True
	membership = BusinessPermissionRepository(db).get_by_user_and_business(int(user_id), business_id)
	return bool(membership and membership_is_active(membership))


def require_business_member(db: Session, business_id: int, user_id: int) -> User:
	user = db.get(User, user_id)
	if not user:
		raise ApiError("TELEPHONY_USER_NOT_FOUND", "TELEPHONY_USER_NOT_FOUND", http_status=404)
	if not is_business_member(db, business_id, user_id):
		raise ApiError("USER_NOT_ACTIVE_MEMBER", "USER_NOT_ACTIVE_MEMBER", http_status=400)
	return user


@dataclass(frozen=True)
class TelephonyScope:
	user_id: int
	view_all: bool
	can_manage: bool
	can_supervise: bool
	extensions: FrozenSet[str] = field(default_factory=frozenset)
	team_codes: FrozenSet[str] = field(default_factory=frozenset)
	extension_ids: FrozenSet[int] = field(default_factory=frozenset)

	@property
	def is_operator_only(self) -> bool:
		return not self.view_all and not self.can_supervise

	def allows_call(self, call: Any) -> bool:
		if self.view_all:
			return True
		assigned = getattr(call, "assigned_user_id", None)
		if assigned is not None and int(assigned) == int(self.user_id):
			return True
		ext = str(getattr(call, "extension", None) or "").strip()
		if ext and ext in self.extensions:
			return True
		queue = str(getattr(call, "queue_code", None) or "").strip()
		if queue and queue in self.team_codes:
			return True
		return False

	def allows_extension(self, extension: Optional[str]) -> bool:
		if self.view_all:
			return True
		ext = str(extension or "").strip()
		return bool(ext) and ext in self.extensions

	def allows_queue(self, queue_code: Optional[str]) -> bool:
		if self.view_all:
			return True
		code = str(queue_code or "").strip()
		return bool(code) and code in self.team_codes

	def apply_call_filter(self, query):
		if self.view_all:
			return query
		clauses = [TelephonyCall.assigned_user_id == self.user_id]
		if self.extensions:
			clauses.append(TelephonyCall.extension.in_(list(self.extensions)))
		if self.team_codes:
			clauses.append(TelephonyCall.queue_code.in_(list(self.team_codes)))
		return query.filter(or_(*clauses))

	def to_dict(self) -> dict:
		return {
			"user_id": self.user_id,
			"view_all": self.view_all,
			"can_manage": self.can_manage,
			"can_supervise": self.can_supervise,
			"extensions": sorted(self.extensions),
			"team_codes": sorted(self.team_codes),
		}


def resolve_scope(db: Session, auth_ctx, business_id: int) -> TelephonyScope:
	uid = int(auth_ctx.get_user_id())
	can_manage = has_telephony_perm(auth_ctx, db, business_id, "manage")
	view_all = can_manage or has_telephony_perm(auth_ctx, db, business_id, "view_all_calls")
	can_supervise = view_all or has_telephony_perm(auth_ctx, db, business_id, "supervise")

	links = (
		db.query(TelephonyUserExtension)
		.options(joinedload(TelephonyUserExtension.extension_row))
		.filter(
			TelephonyUserExtension.business_id == business_id,
			TelephonyUserExtension.user_id == uid,
		)
		.all()
	)
	extensions = {lnk.extension_row.extension for lnk in links if lnk.extension_row}
	extension_ids = {int(lnk.extension_id) for lnk in links}
	team_codes: set[str] = set()
	if can_supervise and not view_all:
		rows = (
			db.query(TelephonyTeamSupervisor)
			.filter(
				TelephonyTeamSupervisor.business_id == business_id,
				TelephonyTeamSupervisor.user_id == uid,
			)
			.all()
		)
		team_codes = {str(r.team_code).strip() for r in rows if r.team_code}
		if team_codes:
			team_exts = (
				db.query(TelephonyExtension)
				.filter(
					TelephonyExtension.business_id == business_id,
					TelephonyExtension.team_code.in_(list(team_codes)),
				)
				.all()
			)
			extensions |= {e.extension for e in team_exts if e.extension}
			extension_ids |= {int(e.id) for e in team_exts}

	return TelephonyScope(
		user_id=uid,
		view_all=bool(view_all),
		can_manage=bool(can_manage),
		can_supervise=bool(can_supervise),
		extensions=frozenset(extensions),
		team_codes=frozenset(team_codes),
		extension_ids=frozenset(extension_ids),
	)


def require_call_in_scope(
	db: Session,
	auth_ctx,
	business_id: int,
	call_id: int,
	*,
	scope: Optional[TelephonyScope] = None,
) -> TelephonyCall:
	call = (
		db.query(TelephonyCall)
		.filter(TelephonyCall.id == call_id, TelephonyCall.business_id == business_id)
		.first()
	)
	if not call:
		raise ApiError("CALL_NOT_FOUND", "CALL_NOT_FOUND", http_status=404)
	resolved = scope or resolve_scope(db, auth_ctx, business_id)
	if not resolved.allows_call(call):
		raise ApiError("CALL_NOT_FOUND", "CALL_NOT_FOUND", http_status=404)
	return call


def can_listen_recording(
	auth_ctx,
	db: Session,
	business_id: int,
	call: TelephonyCall,
	*,
	scope: Optional[TelephonyScope] = None,
) -> bool:
	from adapters.db.models.telephony import TelephonySettings

	resolved = scope or resolve_scope(db, auth_ctx, business_id)
	if not resolved.allows_call(call):
		return False
	settings = db.query(TelephonySettings).filter(TelephonySettings.business_id == business_id).first()
	mode = (settings.recording_access_mode if settings else None) or "permission_based"
	is_owner = call.assigned_user_id is not None and int(call.assigned_user_id) == int(resolved.user_id)
	if mode == "all_operators":
		return True
	if mode == "owner_and_managers":
		return bool(is_owner or resolved.view_all or resolved.can_supervise)
	return has_telephony_perm(auth_ctx, db, business_id, "listen_recordings")


def write_audit(
	db: Session,
	*,
	business_id: int,
	user_id: Optional[int],
	action: str,
	call_id: Optional[int] = None,
	target: Optional[str] = None,
	extra: Optional[dict] = None,
) -> None:
	db.add(
		TelephonyAuditLog(
			business_id=business_id,
			user_id=user_id,
			action=action[:40],
			call_id=call_id,
			target=(target or None),
			extra_info=extra,
			created_at=_now(),
		)
	)


def list_assignable_users(db: Session, business_id: int) -> list[dict]:
	business = db.get(Business, business_id)
	user_ids: set[int] = set()
	if business:
		user_ids.add(int(business.owner_id))
	for membership in BusinessPermissionRepository(db).get_business_users(business_id):
		if membership_is_active(membership):
			user_ids.add(int(membership.user_id))
	if not user_ids:
		return []
	users = db.query(User).filter(User.id.in_(list(user_ids))).order_by(User.id.asc()).all()
	return [
		{
			"id": u.id,
			"name": user_display_name(u),
			"email": u.email,
			"mobile": u.mobile,
		}
		for u in users
	]


def upsert_team_supervisor(
	db: Session, business_id: int, user_id: int, team_code: str, *, enabled: bool
) -> None:
	code = (team_code or "").strip()
	if not code:
		return
	require_business_member(db, business_id, user_id)
	row = (
		db.query(TelephonyTeamSupervisor)
		.filter(
			TelephonyTeamSupervisor.business_id == business_id,
			TelephonyTeamSupervisor.user_id == user_id,
			TelephonyTeamSupervisor.team_code == code,
		)
		.first()
	)
	if enabled and not row:
		db.add(
			TelephonyTeamSupervisor(
				business_id=business_id,
				user_id=user_id,
				team_code=code,
				created_at=_now(),
				updated_at=_now(),
			)
		)
	elif not enabled and row:
		db.delete(row)


def list_team_supervisors(db: Session, business_id: int) -> list[dict]:
	rows = (
		db.query(TelephonyTeamSupervisor)
		.filter(TelephonyTeamSupervisor.business_id == business_id)
		.order_by(TelephonyTeamSupervisor.team_code.asc(), TelephonyTeamSupervisor.user_id.asc())
		.all()
	)
	user_ids = {r.user_id for r in rows}
	users = {u.id: u for u in db.query(User).filter(User.id.in_(list(user_ids))).all()} if user_ids else {}
	return [
		{
			"id": r.id,
			"user_id": r.user_id,
			"user_name": user_display_name(users.get(r.user_id)),
			"team_code": r.team_code,
		}
		for r in rows
	]


def visible_telephony_call_ids_subquery(db: Session, scope: TelephonyScope, business_id: int):
	q = db.query(TelephonyCall.id).filter(TelephonyCall.business_id == business_id)
	return scope.apply_call_filter(q)


def filter_crm_activities_for_telephony(query, db: Session, auth_ctx, business_id: int):
	"""فعالیت‌های ساخته‌شده از تماس، همان scope تلفن را رعایت می‌کنند."""
	from adapters.db.models.crm import CrmActivity
	from app.core.telephony_plugin_dependency import check_telephony_plugin_active

	if auth_ctx is None or not check_telephony_plugin_active(db, business_id):
		return query
	try:
		scope = resolve_scope(db, auth_ctx, business_id)
	except Exception:
		return query
	if scope.view_all:
		return query
	visible = visible_telephony_call_ids_subquery(db, scope, business_id)
	return query.filter(
		or_(
			CrmActivity.telephony_call_id.is_(None),
			CrmActivity.telephony_call_id.in_(visible),
		)
	)


def exclusive_extension_taken(
	db: Session, *, business_id: int, extension_id: int, user_id: int, allow_shared: bool
) -> Iterable[TelephonyUserExtension]:
	if allow_shared:
		return []
	return (
		db.query(TelephonyUserExtension)
		.filter(
			TelephonyUserExtension.business_id == business_id,
			TelephonyUserExtension.extension_id == extension_id,
			TelephonyUserExtension.user_id != user_id,
		)
		.all()
	)
