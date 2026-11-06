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
from app.services import office_automation_extended_service as ext
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


@router.get(
	"/business/{business_id}/settings",
	summary="تنظیمات اتوماسیون اداری",
	description="ابزار MCP: `get_oa_settings`.",
)
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


@router.put(
	"/business/{business_id}/settings",
	summary="ویرایش تنظیمات اتوماسیون اداری",
	description="ابزار MCP: `update_oa_settings` (نیازمند تأیید).",
)
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


@router.get(
	"/business/{business_id}/dashboard",
	summary="داشبورد کارتابل اتوماسیون",
	description="ابزار MCP: `get_oa_dashboard`.",
)
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


@router.get(
	"/business/{business_id}/org-units",
	summary="واحدهای سازمانی اتوماسیون",
	description="ابزار MCP: `list_oa_org_units`.",
)
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


@router.post(
	"/business/{business_id}/org-units",
	summary="ایجاد واحد سازمانی",
	description="ابزار MCP: `create_oa_org_unit` (نیازمند تأیید).",
)
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


@router.put(
	"/business/{business_id}/org-units/{unit_id}",
	summary="ویرایش واحد سازمانی",
	description="ابزار MCP: `update_oa_org_unit` (نیازمند تأیید).",
)
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


@router.get(
	"/business/{business_id}/positions",
	summary="سمت‌های سازمانی اتوماسیون",
	description="ابزار MCP: `list_oa_positions`.",
)
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


@router.post(
	"/business/{business_id}/positions",
	summary="ایجاد سمت سازمانی",
	description="ابزار MCP: `create_oa_position` (نیازمند تأیید).",
)
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


@router.put(
	"/business/{business_id}/positions/{position_id}",
	summary="ویرایش سمت سازمانی",
	description="ابزار MCP: `update_oa_position` (نیازمند تأیید).",
)
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


@router.get(
	"/business/{business_id}/my-positions",
	summary="سمت‌های فعال کاربر جاری",
	description="ابزار MCP: `list_my_oa_positions`.",
)
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


@router.get(
	"/business/{business_id}/holders",
	summary="فهرست تصدی سمت‌ها",
	description="ابزار MCP: `list_oa_position_holders`.",
)
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


@router.post(
	"/business/{business_id}/holders",
	summary="واگذاری سمت",
	description="ابزار MCP: `assign_oa_position_holder` (نیازمند تأیید).",
)
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


@router.post(
	"/business/{business_id}/holders/{holder_id}/end",
	summary="پایان تصدی سمت",
	description="ابزار MCP: `end_oa_position_holder` (نیازمند تأیید).",
)
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


@router.get(
	"/business/{business_id}/delegations",
	summary="فهرست جانشینی سمت‌ها",
	description="ابزار MCP: `list_oa_delegations`.",
)
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


@router.post(
	"/business/{business_id}/delegations",
	summary="تعیین جانشین سمت",
	description="ابزار MCP: `create_oa_delegation` (نیازمند تأیید).",
)
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


@router.post(
	"/business/{business_id}/delegations/{delegation_id}/end",
	summary="پایان جانشینی",
	description="ابزار MCP: `end_oa_delegation` (نیازمند تأیید).",
)
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


@router.get(
	"/business/{business_id}/cartable",
	summary="کارتابل سمت فعال",
	description="ابزار MCP: `list_oa_cartable`.",
)
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


@router.get(
	"/business/{business_id}/formats",
	summary="فرمت‌های کاغذ نامه",
	description="ابزار MCP: `list_oa_letter_formats`.",
)
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


@router.post(
	"/business/{business_id}/formats",
	summary="ایجاد فرمت نامه",
	description="ابزار MCP: `create_oa_letter_format` (نیازمند تأیید).",
)
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


@router.put(
	"/business/{business_id}/formats/{format_id}",
	summary="ویرایش فرمت نامه",
	description="ابزار MCP: `update_oa_letter_format` (نیازمند تأیید).",
)
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


@router.delete(
	"/business/{business_id}/formats/{format_id}",
	summary="حذف فرمت نامه",
	description="ابزار MCP: `delete_oa_letter_format` (نیازمند تأیید).",
)
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


@router.get(
	"/business/{business_id}/templates",
	summary="قالب‌های نامه",
	description="ابزار MCP: `list_oa_letter_templates`.",
)
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


@router.post(
	"/business/{business_id}/templates",
	summary="ایجاد قالب نامه",
	description="ابزار MCP: `create_oa_letter_template` (نیازمند تأیید).",
)
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


@router.put(
	"/business/{business_id}/templates/{template_id}",
	summary="ویرایش قالب نامه",
	description="ابزار MCP: `update_oa_letter_template` (نیازمند تأیید).",
)
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


@router.delete(
	"/business/{business_id}/templates/{template_id}",
	summary="حذف قالب نامه",
	description="ابزار MCP: `delete_oa_letter_template` (نیازمند تأیید).",
)
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


@router.get(
	"/business/{business_id}/letters/search",
	summary="جستجوی نامه‌ها",
	description="ابزار MCP: `search_oa_letters`.",
)
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


@router.post(
	"/business/{business_id}/letters",
	summary="ایجاد پیش‌نویس نامه",
	description="ابزار MCP: `create_oa_letter_draft` (نیازمند تأیید).",
)
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


@router.get(
	"/business/{business_id}/letters/{letter_id}",
	summary="جزئیات نامه",
	description="ابزار MCP: `get_oa_letter`. چاپ باینری جداست.",
)
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


@router.get(
	"/business/{business_id}/letters/{letter_id}/print",
	summary="نسخه چاپی نامه",
	description="JSON چاپ. ابزار MCP: `get_oa_letter_print`. PDF باینری در MCP نیست.",
)
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


@router.put(
	"/business/{business_id}/letters/{letter_id}",
	summary="ویرایش پیش‌نویس نامه",
	description="ابزار MCP: `update_oa_letter_draft` (نیازمند تأیید).",
)
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


@router.delete(
	"/business/{business_id}/letters/{letter_id}",
	summary="حذف پیش‌نویس نامه",
	description="ابزار MCP: `delete_oa_letter_draft` (نیازمند تأیید).",
)
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


@router.post(
	"/business/{business_id}/letters/{letter_id}/register",
	summary="ثبت و شماره‌گذاری نامه",
	description="ابزار MCP: `register_oa_letter` (نیازمند تأیید).",
)
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


@router.post(
	"/business/{business_id}/letters/{letter_id}/refer",
	summary="ارجاع نامه",
	description="ابزار MCP: `refer_oa_letter` (نیازمند تأیید).",
)
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


@router.post(
	"/business/{business_id}/referrals/{referral_id}/complete",
	summary="بستن ارجاع کارتابل",
	description="ابزار MCP: `complete_oa_referral` (نیازمند تأیید).",
)
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


@router.post(
	"/business/{business_id}/referrals/{referral_id}/return",
	summary="عودت ارجاع",
	description="ابزار MCP: `return_oa_referral` (نیازمند تأیید).",
)
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


@router.post(
	"/business/{business_id}/letters/{letter_id}/paraphs",
	summary="ثبت پاراف نامه",
	description="ابزار MCP: `add_oa_paraph` (نیازمند تأیید).",
)
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


@router.post(
	"/business/{business_id}/letters/{letter_id}/attachments",
	summary="پیوست فایل موجود به نامه",
	description="آپلود باینری در MCP نیست. ابزار MCP: `add_oa_letter_attachment` (نیازمند تأیید).",
)
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


@router.post(
	"/business/{business_id}/letters/{letter_id}/attachments/upload",
	summary="آپلود پیوست نامه",
	description="باینری است؛ در MCP نیست. پیوست فایل موجود: `add_oa_letter_attachment`.",
)
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


@router.delete(
	"/business/{business_id}/attachments/{attachment_id}",
	summary="حذف پیوست نامه",
	description="ابزار MCP: `remove_oa_letter_attachment` (نیازمند تأیید).",
)
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


@router.post(
	"/business/{business_id}/letters/{letter_id}/archive",
	summary="بایگانی نامه",
	description="ابزار MCP: `archive_oa_letter` (نیازمند تأیید).",
)
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


@router.post(
	"/business/{business_id}/letters/{letter_id}/follow-up",
	summary="تاریخ پیگیری نامه",
	description="ابزار MCP: `set_oa_follow_up` (نیازمند تأیید).",
)
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


@router.post(
	"/business/{business_id}/letters/{letter_id}/links",
	summary="پیوند نامه‌ها",
	description="ابزار MCP: `link_oa_letters` (نیازمند تأیید).",
)
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


@router.get(
	"/public/track/{token}",
	summary="رهگیری عمومی نامه",
	description="عمومی و بدون احراز هویت؛ در MCP نیست.",
)
def public_track_letter(
	request: Request,
	token: str,
	_: None = Depends(locale_dependency),
	db: Session = Depends(get_db),
) -> dict:
	return _ok(ext.public_track(db, token), request)


@router.get(
	"/business/{business_id}/secretariats",
	summary="فهرست دبیرخانه‌ها",
	description="ابزار MCP: `list_oa_secretariats`.",
)
def list_secretariats(
	request: Request,
	business_id: int,
	include_inactive: bool = Query(False),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "view")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
) -> dict:
	return _ok({"items": ext.list_secretariats(db, business_id, include_inactive=include_inactive, lang=_lang(request))}, request)


@router.post(
	"/business/{business_id}/secretariats",
	summary="ایجاد دبیرخانه",
	description="ابزار MCP: `create_oa_secretariat` (نیازمند تأیید).",
)
def create_secretariat(
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
	return _ok(ext.create_secretariat(db, business_id, payload, ctx.get_user_id(), lang=_lang(request)), request)


@router.put("/business/{business_id}/secretariats/{secretariat_id}", summary="ویرایش دبیرخانه", description="ابزار MCP: update_oa_secretariat.")
def update_secretariat(
	request: Request,
	business_id: int,
	secretariat_id: int,
	payload: dict = Body(...),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "admin")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _ok(ext.update_secretariat(db, business_id, secretariat_id, payload, ctx.get_user_id(), lang=_lang(request)), request)


@router.get(
	"/business/{business_id}/external-orgs",
	summary="سازمان‌های خارجی مکاتبات",
	description="ابزار MCP: `list_oa_external_orgs`.",
)
def list_external_orgs(
	request: Request,
	business_id: int,
	q: Optional[str] = Query(None),
	include_inactive: bool = Query(False),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "view")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
) -> dict:
	return _ok({"items": ext.list_external_orgs(db, business_id, q=q, include_inactive=include_inactive, lang=_lang(request))}, request)


@router.post(
	"/business/{business_id}/external-orgs",
	summary="ثبت سازمان خارجی",
	description="ابزار MCP: `create_oa_external_org` (نیازمند تأیید).",
)
def create_external_org(
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
	return _ok(ext.create_external_org(db, business_id, payload, ctx.get_user_id(), lang=_lang(request)), request)


@router.put("/business/{business_id}/external-orgs/{org_id}", summary="ویرایش سازمان خارجی", description="ابزار MCP: update_oa_external_org.")
def update_external_org(
	request: Request,
	business_id: int,
	org_id: int,
	payload: dict = Body(...),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "admin")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _ok(ext.update_external_org(db, business_id, org_id, payload, ctx.get_user_id(), lang=_lang(request)), request)


@router.get("/business/{business_id}/signatures", summary="امضاهای کاربر جاری", description="متادیتا بدون بایت تصویر. ابزار MCP: list_oa_signatures.")
def list_signatures(
	request: Request,
	business_id: int,
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "view")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _ok({"items": ext.list_signatures(db, business_id, ctx.get_user_id())}, request)


@router.post("/business/{business_id}/signatures", summary="ذخیره امضای کاربر", description="شناسه فایل موجود؛ آپلود باینری جداست. ابزار MCP: upsert_oa_signature.")
def upsert_signature(
	request: Request,
	business_id: int,
	payload: dict = Body(...),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "view")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _ok(ext.upsert_signature(db, business_id, ctx.get_user_id(), payload), request)


@router.get("/business/{business_id}/sign-paths", summary="قالب‌های مسیر امضا", description="ابزار MCP: list_oa_sign_paths.")
def list_sign_paths(
	request: Request,
	business_id: int,
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "view")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
) -> dict:
	return _ok({"items": ext.list_sign_path_templates(db, business_id, lang=_lang(request))}, request)


@router.post("/business/{business_id}/sign-paths", summary="ذخیره قالب مسیر امضا", description="ابزار MCP: save_oa_sign_path.")
def save_sign_path(
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
	return _ok(ext.save_sign_path_template(db, business_id, payload, ctx.get_user_id(), lang=_lang(request)), request)


@router.post(
	"/business/{business_id}/letters/{letter_id}/sign-path",
	summary="شروع مسیر امضای نامه",
	description="ابزار MCP: `start_oa_sign_path` (نیازمند تأیید).",
)
def start_sign_path(
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
	return _ok(ext.start_sign_path(db, business_id, letter_id, payload, ctx.get_user_id(), pid, lang=_lang(request)), request)


@router.post(
	"/business/{business_id}/letters/{letter_id}/sign",
	summary="امضای مرحله جاری نامه",
	description="ابزار MCP: `sign_oa_letter` (نیازمند تأیید).",
)
def sign_letter(
	request: Request,
	business_id: int,
	letter_id: int,
	payload: dict = Body(default={}),
	as_position_id: Optional[int] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "refer")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	pid = _position_id(request, as_position_id or (payload or {}).get("as_position_id"))
	return _ok(ext.sign_letter_step(db, business_id, letter_id, payload or {}, ctx.get_user_id(), pid, lang=_lang(request)), request)


@router.post("/business/{business_id}/letters/{letter_id}/sign/reject", summary="رد امضای نامه", description="ابزار MCP: reject_oa_letter_sign.")
def reject_sign(
	request: Request,
	business_id: int,
	letter_id: int,
	payload: dict = Body(default={}),
	as_position_id: Optional[int] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "refer")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	pid = _position_id(request, as_position_id or (payload or {}).get("as_position_id"))
	return _ok(ext.reject_sign_step(db, business_id, letter_id, payload or {}, ctx.get_user_id(), pid, lang=_lang(request)), request)


@router.post(
	"/business/{business_id}/letters/{letter_id}/dispatch",
	summary="ابلاغ نامه",
	description="ابزار MCP: `dispatch_oa_letter` (نیازمند تأیید).",
)
def dispatch_letter(
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
	return _ok(
		ext.dispatch_letter(db, business_id, letter_id, payload, ctx.get_user_id(), pid, lang=_lang(request), calendar_type=_cal(request)),
		request,
	)


@router.post("/business/{business_id}/dispatches/{dispatch_id}/acknowledge", summary="رسید ابلاغ نامه", description="ابزار MCP: acknowledge_oa_dispatch.")
def acknowledge_dispatch(
	request: Request,
	business_id: int,
	dispatch_id: int,
	as_position_id: Optional[int] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "refer")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	pid = _position_id(request, as_position_id)
	return _ok(ext.acknowledge_dispatch(db, business_id, dispatch_id, ctx.get_user_id(), pid, lang=_lang(request)), request)


@router.post("/business/{business_id}/referrals/{referral_id}/cancel", summary="لغو ارجاع نامه", description="ابزار MCP: cancel_oa_referral.")
def cancel_referral(
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
	return _ok(ext.cancel_referral(db, business_id, referral_id, payload or {}, ctx.get_user_id(), pid, lang=_lang(request)), request)


@router.post("/business/{business_id}/letters/{letter_id}/unarchive", summary="خروج نامه از بایگانی", description="ابزار MCP: unarchive_oa_letter.")
def unarchive_letter(
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
	return _ok(ext.unarchive_letter(db, business_id, letter_id, ctx.get_user_id(), pid, lang=_lang(request)), request)


@router.get("/business/{business_id}/letters/{letter_id}/versions", summary="نسخه‌های نامه", description="ابزار MCP: list_oa_letter_versions.")
def list_letter_versions(
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
		{"items": ext.list_letter_versions(db, business_id, letter_id, ctx.get_user_id(), pid, lang=_lang(request), is_admin=_is_admin(ctx, business_id))},
		request,
	)


@router.post(
	"/business/{business_id}/letters/{letter_id}/ece/export",
	summary="صدور XML پروتکل ECE",
	description="ابزار MCP: `export_oa_ece`.",
)
def export_ece(
	request: Request,
	business_id: int,
	letter_id: int,
	as_position_id: Optional[int] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "secretariat")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	pid = _position_id(request, as_position_id)
	return _ok(ext.export_ece(db, business_id, letter_id, ctx.get_user_id(), pid, lang=_lang(request), calendar_type=_cal(request)), request)


@router.post(
	"/business/{business_id}/letters/{letter_id}/ece/send",
	summary="ارسال ECE از طریق ایمیل",
	description="ابزار MCP: `send_oa_ece` (نیازمند تأیید).",
)
def send_ece(
	request: Request,
	business_id: int,
	letter_id: int,
	payload: dict = Body(default={}),
	as_position_id: Optional[int] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "secretariat")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	pid = _position_id(request, as_position_id or (payload or {}).get("as_position_id"))
	return _ok(ext.send_ece(db, business_id, letter_id, payload or {}, ctx.get_user_id(), pid, lang=_lang(request), calendar_type=_cal(request)), request)


@router.post(
	"/business/{business_id}/ece/import",
	summary="ورود نامه از ECE",
	description="ابزار MCP: `import_oa_ece` (نیازمند تأیید).",
)
def import_ece(
	request: Request,
	business_id: int,
	payload: dict = Body(...),
	as_position_id: Optional[int] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "secretariat")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	pid = _position_id(request, as_position_id or payload.get("as_position_id"))
	return _ok(ext.import_ece(db, business_id, payload, ctx.get_user_id(), pid, lang=_lang(request), calendar_type=_cal(request)), request)


@router.get("/business/{business_id}/ece", summary="فهرست پیام‌های ECE", description="بدون الزام XML کامل در MCP. ابزار MCP: list_oa_ece_messages.")
def list_ece(
	request: Request,
	business_id: int,
	direction: Optional[str] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "view")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
) -> dict:
	return _ok({"items": ext.list_ece_messages(db, business_id, direction=direction)}, request)


@router.get("/business/{business_id}/cartable-rules", summary="قوانین کارتابل", description="ابزار MCP: list_oa_cartable_rules.")
def list_cartable_rules(
	request: Request,
	business_id: int,
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "admin")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
) -> dict:
	return _ok({"items": ext.list_cartable_rules(db, business_id)}, request)


@router.post("/business/{business_id}/cartable-rules", summary="ذخیره قانون کارتابل", description="ابزار MCP: save_oa_cartable_rule.")
def save_cartable_rule(
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
	return _ok(ext.save_cartable_rule(db, business_id, payload, ctx.get_user_id()), request)


@router.delete("/business/{business_id}/cartable-rules/{rule_id}", summary="حذف قانون کارتابل", description="ابزار MCP: delete_oa_cartable_rule.")
def delete_cartable_rule(
	request: Request,
	business_id: int,
	rule_id: int,
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "admin")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _ok(ext.delete_cartable_rule(db, business_id, rule_id, ctx.get_user_id()), request)


@router.get(
	"/business/{business_id}/archive-folders",
	summary="پوشه‌های بایگانی",
	description="ابزار MCP: `list_oa_archive_folders`.",
)
def list_archive_folders(
	request: Request,
	business_id: int,
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "view")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
) -> dict:
	return _ok({"items": ext.list_archive_folders(db, business_id, lang=_lang(request))}, request)


@router.post("/business/{business_id}/archive-folders", summary="ذخیره پوشه بایگانی", description="ابزار MCP: save_oa_archive_folder.")
def save_archive_folder(
	request: Request,
	business_id: int,
	payload: dict = Body(...),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "archive")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _ok(ext.save_archive_folder(db, business_id, payload, ctx.get_user_id(), lang=_lang(request)), request)


@router.post("/business/{business_id}/letters/{letter_id}/archive-to-folder", summary="بایگانی نامه در پوشه", description="ابزار MCP: archive_oa_letter_to_folder.")
def archive_to_folder(
	request: Request,
	business_id: int,
	letter_id: int,
	payload: dict = Body(...),
	as_position_id: Optional[int] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "archive")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	pid = _position_id(request, as_position_id or payload.get("as_position_id"))
	return _ok(ext.archive_to_folder(db, business_id, letter_id, payload, ctx.get_user_id(), pid, lang=_lang(request)), request)


@router.get(
	"/business/{business_id}/reports/delay",
	summary="گزارش تأخیر کارتابل",
	description="ابزار MCP: `get_oa_delay_report`.",
)
def delay_report(
	request: Request,
	business_id: int,
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "view")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
) -> dict:
	return _ok(ext.delay_report(db, business_id, lang=_lang(request)), request)


@router.get("/business/{business_id}/reports/volume", summary="گزارش حجم مکاتبات", description="ابزار MCP: get_oa_volume_report.")
def volume_report(
	request: Request,
	business_id: int,
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "view")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
) -> dict:
	return _ok(ext.volume_report(db, business_id), request)


@router.get("/business/{business_id}/reports/performance", summary="گزارش عملکرد کارتابل", description="ابزار MCP: get_oa_performance_report.")
def performance_report(
	request: Request,
	business_id: int,
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "view")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
) -> dict:
	return _ok(ext.performance_report(db, business_id, lang=_lang(request)), request)


@router.post(
	"/business/{business_id}/mailbox/import",
	summary="ورود ایمیل به‌عنوان نامه",
	description="ابزار MCP: `import_oa_email_letter` (نیازمند تأیید).",
)
def import_email(
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
	return _ok(ext.import_email_as_letter(db, business_id, payload, ctx.get_user_id(), pid, lang=_lang(request), calendar_type=_cal(request)), request)


@router.post(
	"/business/{business_id}/letters/{letter_id}/email",
	summary="ارسال نامه با ایمیل",
	description="ابزار MCP: `send_oa_email_letter` (نیازمند تأیید).",
)
def send_letter_email(
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
	return _ok(ext.send_letter_email(db, business_id, letter_id, payload, ctx.get_user_id(), pid, lang=_lang(request)), request)


@router.post(
	"/business/{business_id}/letters/{letter_id}/ocr",
	summary="OCR پیوست نامه",
	description="ابزار MCP: `ocr_oa_letter`.",
)
def ocr_letter(
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
	return _ok(ext.ocr_letter_attachments(db, business_id, letter_id, ctx.get_user_id(), pid, lang=_lang(request)), request)


@router.post(
	"/business/{business_id}/letters/{letter_id}/ai-summary",
	summary="خلاصه هوشمند نامه",
	description="ابزار MCP: `summarize_oa_letter`.",
)
def summarize_letter(
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
	pid = _position_id(request, as_position_id)
	return _ok(ext.summarize_letter(db, business_id, letter_id, ctx.get_user_id(), pid, lang=_lang(request)), request)


@router.post("/business/{business_id}/follow-ups/notify", summary="اعلان پیگیری‌های سررسید", description="ابزار MCP: notify_oa_due_followups.")
def notify_followups(
	request: Request,
	business_id: int,
	_: None = Depends(locale_dependency),
	__: None = _ACCESS,
	___: None = Depends(require_business_permission_dep("office_automation", "admin")),
	____: None = _PLUGIN,
	db: Session = Depends(get_db),
) -> dict:
	return _ok(ext.notify_due_followups(db, business_id), request)
