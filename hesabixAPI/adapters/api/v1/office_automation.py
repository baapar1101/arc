"""API اتوماسیون اداری سمت‌محور."""
from __future__ import annotations

from typing import Any, Optional

from fastapi import APIRouter, Body, Depends, File, Query, Request, UploadFile
from sqlalchemy.orm import Session

from adapters.db.models.office_automation import OaLetter
from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.i18n import locale_dependency, negotiate_locale
from app.core.office_automation_plugin_dependency import require_office_automation_plugin_active
from app.core.permissions import require_business_access_dep, require_business_permission_dep
from app.core.responses import ApiError, format_datetime_fields, success_response
from app.services import office_automation_service as svc
from app.services.file_storage_service import FileStorageService

router = APIRouter(prefix="/office-automation", tags=["office-automation"])

_PLUGIN = Depends(require_office_automation_plugin_active())
_ACCESS = Depends(require_business_access_dep)


def _lang(request: Request) -> str:
	return negotiate_locale(request.headers.get("Accept-Language"))


def _cal(request: Request) -> str:
	return getattr(request.state, "calendar_type", "jalali") or "jalali"


def _ok(data: Any, request: Request, **kwargs) -> dict:
	return success_response(format_datetime_fields(data, request), request, **kwargs)


def _optional_position_id(request: Request, as_position_id: Optional[int] = None) -> Optional[int]:
	if as_position_id:
		try:
			return int(as_position_id)
		except (TypeError, ValueError):
			return None
	header = request.headers.get("X-OA-Position-Id") or request.headers.get("x-oa-position-id")
	if header:
		try:
			return int(header)
		except (TypeError, ValueError):
			return None
	return None


def _position_id(request: Request, as_position_id: Optional[int] = None) -> int:
	pid = _optional_position_id(request, as_position_id)
	if pid:
		return pid
	raise ApiError("OA_POSITION_REQUIRED", "Active position is required (X-OA-Position-Id).", http_status=400)


def _is_admin(ctx: AuthContext, business_id: int) -> bool:
	try:
		return bool(ctx.has_business_permission("office_automation", "admin") or ctx.is_business_owner(business_id))
	except Exception:
		return False


@router.get("/business/{business_id}/settings")
def get_settings(
	request: Request,
	business_id: int,
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "view")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _ok(svc.get_settings(db, business_id), request)


@router.put("/business/{business_id}/settings")
def update_settings(
	request: Request,
	business_id: int,
	payload: dict = Body(...),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "admin")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _ok(svc.update_settings(db, business_id, payload, ctx.get_user_id()), request)


@router.get("/business/{business_id}/dashboard")
def dashboard(
	request: Request,
	business_id: int,
	as_position_id: Optional[int] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "view")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	pid = _optional_position_id(request, as_position_id)
	return _ok(svc.get_dashboard(db, business_id, ctx.get_user_id(), pid, lang=_lang(request)), request)


@router.get("/business/{business_id}/org-units")
def list_org_units(
	request: Request,
	business_id: int,
	include_inactive: bool = Query(False),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "view")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
) -> dict:
	return _ok({"items": svc.list_org_units(db, business_id, include_inactive=include_inactive, lang=_lang(request))}, request)


@router.post("/business/{business_id}/org-units")
def create_org_unit(
	request: Request,
	business_id: int,
	payload: dict = Body(...),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "admin")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _ok(svc.create_org_unit(db, business_id, payload, ctx.get_user_id(), lang=_lang(request)), request)


@router.put("/business/{business_id}/org-units/{unit_id}")
def update_org_unit(
	request: Request,
	business_id: int,
	unit_id: int,
	payload: dict = Body(...),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "admin")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _ok(svc.update_org_unit(db, business_id, unit_id, payload, ctx.get_user_id(), lang=_lang(request)), request)


@router.get("/business/{business_id}/positions")
def list_positions(
	request: Request,
	business_id: int,
	include_inactive: bool = Query(False),
	q: Optional[str] = Query(None),
	limit: Optional[int] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "view")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
) -> dict:
	return _ok(
		{"items": svc.list_positions(db, business_id, include_inactive=include_inactive, lang=_lang(request), q=q, limit=limit)},
		request,
	)


@router.post("/business/{business_id}/positions")
def create_position(
	request: Request,
	business_id: int,
	payload: dict = Body(...),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "admin")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _ok(svc.create_position(db, business_id, payload, ctx.get_user_id(), lang=_lang(request)), request)


@router.put("/business/{business_id}/positions/{position_id}")
def update_position(
	request: Request,
	business_id: int,
	position_id: int,
	payload: dict = Body(...),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "admin")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _ok(svc.update_position(db, business_id, position_id, payload, ctx.get_user_id(), lang=_lang(request)), request)


@router.get("/business/{business_id}/my-positions")
def my_positions(
	request: Request,
	business_id: int,
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "view")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _ok({"items": svc.list_my_positions(db, business_id, ctx.get_user_id(), lang=_lang(request))}, request)


@router.get("/business/{business_id}/holders")
def list_holders(
	request: Request,
	business_id: int,
	position_id: Optional[int] = Query(None),
	user_id: Optional[int] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "admin")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
) -> dict:
	return _ok({"items": svc.list_position_holders(db, business_id, position_id=position_id, user_id=user_id, lang=_lang(request))}, request)


@router.post("/business/{business_id}/holders")
def assign_holder(
	request: Request,
	business_id: int,
	payload: dict = Body(...),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "admin")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _ok(svc.assign_position_holder(db, business_id, payload, ctx.get_user_id(), lang=_lang(request), calendar_type=_cal(request)), request)


@router.post("/business/{business_id}/holders/{holder_id}/end")
def end_holder(
	request: Request,
	business_id: int,
	holder_id: int,
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "admin")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _ok(svc.end_position_holder(db, business_id, holder_id, ctx.get_user_id()), request)


@router.get("/business/{business_id}/delegations")
def list_delegations(
	request: Request,
	business_id: int,
	position_id: Optional[int] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "admin")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
) -> dict:
	return _ok({"items": svc.list_delegations(db, business_id, position_id=position_id, lang=_lang(request))}, request)


@router.post("/business/{business_id}/delegations")
def create_delegation(
	request: Request,
	business_id: int,
	payload: dict = Body(...),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "admin")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _ok(svc.create_delegation(db, business_id, payload, ctx.get_user_id(), lang=_lang(request), calendar_type=_cal(request)), request)


@router.post("/business/{business_id}/delegations/{delegation_id}/end")
def end_delegation(
	request: Request,
	business_id: int,
	delegation_id: int,
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "admin")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _ok(svc.end_delegation(db, business_id, delegation_id, ctx.get_user_id()), request)


@router.get("/business/{business_id}/cartable")
def cartable(
	request: Request,
	business_id: int,
	folder: str = Query("inbox"),
	q: Optional[str] = Query(None),
	as_position_id: Optional[int] = Query(None),
	date_from: Optional[str] = Query(None),
	date_to: Optional[str] = Query(None),
	limit: int = Query(50),
	skip: int = Query(0),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "view")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	pid = _position_id(request, as_position_id)
	return _ok(
		svc.list_cartable(
			db, business_id, ctx.get_user_id(), pid,
			folder=folder, q=q, limit=limit, skip=skip, lang=_lang(request),
			calendar_type=_cal(request), date_from=date_from, date_to=date_to,
		),
		request,
	)


@router.get("/business/{business_id}/formats")
def list_formats(
	request: Request,
	business_id: int,
	include_inactive: bool = Query(False),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "view")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
) -> dict:
	return _ok({"items": svc.list_letter_formats(db, business_id, include_inactive=include_inactive)}, request)


@router.post("/business/{business_id}/formats")
def create_format(
	request: Request,
	business_id: int,
	payload: dict = Body(...),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "admin")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _ok(svc.create_letter_format(db, business_id, payload, ctx.get_user_id()), request)


@router.put("/business/{business_id}/formats/{format_id}")
def update_format(
	request: Request,
	business_id: int,
	format_id: int,
	payload: dict = Body(...),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "admin")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _ok(svc.update_letter_format(db, business_id, format_id, payload, ctx.get_user_id()), request)


@router.delete("/business/{business_id}/formats/{format_id}")
def delete_format(
	request: Request,
	business_id: int,
	format_id: int,
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "admin")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _ok(svc.delete_letter_format(db, business_id, format_id, ctx.get_user_id()), request)


@router.get("/business/{business_id}/templates")
def list_templates(
	request: Request,
	business_id: int,
	include_inactive: bool = Query(False),
	letter_kind: Optional[str] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "view")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
) -> dict:
	return _ok(
		{"items": svc.list_letter_templates(db, business_id, include_inactive=include_inactive, letter_kind=letter_kind)},
		request,
	)


@router.post("/business/{business_id}/templates")
def create_template(
	request: Request,
	business_id: int,
	payload: dict = Body(...),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "admin")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _ok(svc.create_letter_template(db, business_id, payload, ctx.get_user_id()), request)


@router.put("/business/{business_id}/templates/{template_id}")
def update_template(
	request: Request,
	business_id: int,
	template_id: int,
	payload: dict = Body(...),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "admin")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _ok(svc.update_letter_template(db, business_id, template_id, payload, ctx.get_user_id()), request)


@router.delete("/business/{business_id}/templates/{template_id}")
def delete_template(
	request: Request,
	business_id: int,
	template_id: int,
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "admin")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _ok(svc.delete_letter_template(db, business_id, template_id, ctx.get_user_id()), request)


@router.get("/business/{business_id}/letters/search")
def search_letters(
	request: Request,
	business_id: int,
	q: Optional[str] = Query(None),
	limit: int = Query(20),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "view")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _ok(
		{
			"items": svc.search_letters(
				db, business_id, ctx.get_user_id(), q=q, limit=limit, lang=_lang(request), is_admin=_is_admin(ctx, business_id)
			)
		},
		request,
	)


@router.post("/business/{business_id}/letters")
def create_draft(
	request: Request,
	business_id: int,
	payload: dict = Body(...),
	as_position_id: Optional[int] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "compose")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	pid = _position_id(request, as_position_id or payload.get("as_position_id"))
	return _ok(svc.create_letter_draft(db, business_id, payload, ctx.get_user_id(), pid, lang=_lang(request), calendar_type=_cal(request)), request)


@router.get("/business/{business_id}/letters/{letter_id}")
def get_letter(
	request: Request,
	business_id: int,
	letter_id: int,
	as_position_id: Optional[int] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "view")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	pid = _optional_position_id(request, as_position_id)
	return _ok(
		svc.get_letter(
			db, business_id, letter_id, ctx.get_user_id(), pid,
			lang=_lang(request), is_admin=_is_admin(ctx, business_id),
		),
		request,
	)


@router.get("/business/{business_id}/letters/{letter_id}/print")
def print_letter(
	request: Request,
	business_id: int,
	letter_id: int,
	as_position_id: Optional[int] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "view")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	pid = _optional_position_id(request, as_position_id)
	return _ok(
		svc.get_letter_print(
			db, business_id, letter_id, ctx.get_user_id(), pid,
			lang=_lang(request), is_admin=_is_admin(ctx, business_id),
		),
		request,
	)


@router.put("/business/{business_id}/letters/{letter_id}")
def update_draft(
	request: Request,
	business_id: int,
	letter_id: int,
	payload: dict = Body(...),
	as_position_id: Optional[int] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "compose")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	pid = _position_id(request, as_position_id or payload.get("as_position_id"))
	return _ok(svc.update_letter_draft(db, business_id, letter_id, payload, ctx.get_user_id(), pid, lang=_lang(request), calendar_type=_cal(request)), request)


@router.delete("/business/{business_id}/letters/{letter_id}")
def delete_draft(
	request: Request,
	business_id: int,
	letter_id: int,
	as_position_id: Optional[int] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "compose")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	pid = _position_id(request, as_position_id)
	return _ok(svc.delete_letter_draft(db, business_id, letter_id, ctx.get_user_id(), pid), request)


@router.post("/business/{business_id}/letters/{letter_id}/register")
def register_letter(
	request: Request,
	business_id: int,
	letter_id: int,
	payload: dict = Body(default={}),
	as_position_id: Optional[int] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "compose")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	pid = _position_id(request, as_position_id or (payload or {}).get("as_position_id"))
	kind = str((payload or {}).get("letter_kind") or "")
	if kind not in {"incoming", "outgoing"}:
		letter = db.query(OaLetter).filter(OaLetter.id == letter_id, OaLetter.business_id == business_id).first()
		kind = getattr(letter, "letter_kind", "") or kind
	if kind in {"incoming", "outgoing"}:
		if not ctx.has_business_permission("office_automation", "secretariat") and not _is_admin(ctx, business_id):
			raise ApiError("FORBIDDEN", "Missing business permission: office_automation.secretariat", http_status=403)
	return _ok(svc.register_letter(db, business_id, letter_id, payload or {}, ctx.get_user_id(), pid, lang=_lang(request), calendar_type=_cal(request)), request)


@router.post("/business/{business_id}/letters/{letter_id}/refer")
def refer_letter(
	request: Request,
	business_id: int,
	letter_id: int,
	payload: dict = Body(...),
	as_position_id: Optional[int] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "refer")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	pid = _position_id(request, as_position_id or payload.get("as_position_id"))
	return _ok(svc.refer_letter(db, business_id, letter_id, payload, ctx.get_user_id(), pid, lang=_lang(request), calendar_type=_cal(request)), request)


@router.post("/business/{business_id}/referrals/{referral_id}/complete")
def complete_referral(
	request: Request,
	business_id: int,
	referral_id: int,
	payload: dict = Body(default={}),
	as_position_id: Optional[int] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "refer")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	pid = _position_id(request, as_position_id)
	return _ok(svc.complete_referral(db, business_id, referral_id, payload or {}, ctx.get_user_id(), pid, lang=_lang(request)), request)


@router.post("/business/{business_id}/referrals/{referral_id}/return")
def return_referral(
	request: Request,
	business_id: int,
	referral_id: int,
	payload: dict = Body(default={}),
	as_position_id: Optional[int] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "refer")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	pid = _position_id(request, as_position_id)
	return _ok(svc.return_referral(db, business_id, referral_id, payload or {}, ctx.get_user_id(), pid, lang=_lang(request)), request)


@router.post("/business/{business_id}/letters/{letter_id}/paraphs")
def add_paraph(
	request: Request,
	business_id: int,
	letter_id: int,
	payload: dict = Body(...),
	as_position_id: Optional[int] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "refer")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	pid = _position_id(request, as_position_id or payload.get("as_position_id"))
	return _ok(svc.add_paraph(db, business_id, letter_id, payload, ctx.get_user_id(), pid, lang=_lang(request)), request)


@router.post("/business/{business_id}/letters/{letter_id}/attachments")
def add_attachment(
	request: Request,
	business_id: int,
	letter_id: int,
	payload: dict = Body(...),
	as_position_id: Optional[int] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "compose")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	pid = _position_id(request, as_position_id or payload.get("as_position_id"))
	return _ok(svc.add_attachment(db, business_id, letter_id, payload, ctx.get_user_id(), pid), request)


@router.post("/business/{business_id}/letters/{letter_id}/attachments/upload")
async def upload_attachment(
	request: Request,
	business_id: int,
	letter_id: int,
	file: UploadFile = File(...),
	as_position_id: Optional[int] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "compose")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	pid = _position_id(request, as_position_id)
	storage = FileStorageService(db)
	saved = await storage.upload_file(
		file=file,
		user_id=ctx.get_user_id(),
		module_context="office_automation",
		context_id=str(letter_id),
		business_id=business_id,
	)
	file_id = saved.get("file_id") if isinstance(saved, dict) else None
	if not file_id:
		raise ApiError("FILE_NOT_FOUND", "Uploaded file was not stored.", http_status=500)
	data = svc.add_attachment(
		db, business_id, letter_id,
		{"file_storage_id": str(file_id), "title": file.filename},
		ctx.get_user_id(), pid,
	)
	return _ok(data, request)


@router.delete("/business/{business_id}/attachments/{attachment_id}")
def remove_attachment(
	request: Request,
	business_id: int,
	attachment_id: int,
	as_position_id: Optional[int] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "compose")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	pid = _position_id(request, as_position_id)
	return _ok(svc.remove_attachment(db, business_id, attachment_id, ctx.get_user_id(), pid), request)


@router.post("/business/{business_id}/letters/{letter_id}/archive")
def archive_letter(
	request: Request,
	business_id: int,
	letter_id: int,
	as_position_id: Optional[int] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "archive")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	pid = _position_id(request, as_position_id)
	return _ok(svc.archive_letter(db, business_id, letter_id, ctx.get_user_id(), pid, lang=_lang(request)), request)


@router.post("/business/{business_id}/letters/{letter_id}/follow-up")
def set_follow_up(
	request: Request,
	business_id: int,
	letter_id: int,
	payload: dict = Body(...),
	as_position_id: Optional[int] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "refer")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	pid = _position_id(request, as_position_id or payload.get("as_position_id"))
	return _ok(svc.set_follow_up(db, business_id, letter_id, payload, ctx.get_user_id(), pid, lang=_lang(request), calendar_type=_cal(request)), request)


@router.post("/business/{business_id}/letters/{letter_id}/links")
def link_letters(
	request: Request,
	business_id: int,
	letter_id: int,
	payload: dict = Body(...),
	as_position_id: Optional[int] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "refer")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	pid = _position_id(request, as_position_id or payload.get("as_position_id"))
	return _ok(svc.link_letters(db, business_id, letter_id, payload, ctx.get_user_id(), pid), request)
