"""API افزونه اتصال به استریسک و ایزابل."""
from __future__ import annotations

from typing import Any, Dict, Optional

from fastapi import APIRouter, Body, Depends, Header, Query, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.i18n import locale_dependency
from app.core.permissions import require_business_access_dep, require_business_permission_dep
from app.core.responses import ApiError, format_datetime_fields, success_response
from app.core.telephony_plugin_dependency import (
	require_telephony_any,
	require_telephony_click_or_view,
	require_telephony_plugin_active,
)
from app.services.telephony import telephony_service as svc
from app.services.telephony.telephony_access import list_assignable_users, list_team_supervisors, resolve_scope

router = APIRouter(prefix="/telephony", tags=["telephony"])


def _resp(data: Any, request: Request, **kwargs) -> dict:
	return success_response(format_datetime_fields(data, request), request, **kwargs)


def _bearer_token(authorization: Optional[str]) -> str:
	if not authorization:
		raise ApiError("MISSING_AUTHORIZATION", "MISSING_AUTHORIZATION", http_status=401)
	parts = authorization.split()
	if len(parts) == 2 and parts[0].lower() == "bearer":
		return parts[1].strip()
	raise ApiError("INVALID_AUTHORIZATION", "INVALID_AUTHORIZATION", http_status=401)


# ─── Settings / context ─────────────────────────────────────────────────────


@router.get(
	"/business/{business_id}/settings",
	summary="تنظیمات تلفن",
	description="بدون توکن کانکتور. ابزار MCP: `get_telephony_settings`.",
)
def get_settings(
	request: Request,
	business_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(require_business_permission_dep("telephony", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	row = svc.get_or_create_settings(db, business_id)
	return _resp(svc.settings_to_dict(row), request)


@router.put(
	"/business/{business_id}/settings",
	summary="ویرایش تنظیمات تلفن",
	description="توکن کانکتور از MCP نیست. ابزار MCP: `update_telephony_settings` (نیازمند تأیید).",
)
def put_settings(
	request: Request,
	business_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(require_business_permission_dep("telephony", "manage")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _resp(svc.update_settings(db, business_id, payload), request)


@router.get("/business/{business_id}/me/context", summary="زمینه تلفن کاربر جاری", description="داخلی و وضعیت کاربر بدون توکن کانکتور. ابزار MCP: `get_telephony_my_context`.")
def my_context(
	request: Request,
	business_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(require_business_permission_dep("telephony", "view")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _resp(svc.get_my_extension_context(db, business_id, ctx.get_user_id(), auth_ctx=ctx), request)


@router.get(
	"/business/{business_id}/dashboard",
	summary="داشبورد تلفن",
	description="بدون افشای توکن. ابزار MCP: `get_telephony_dashboard`.",
)
def dashboard(
	request: Request,
	business_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(require_business_permission_dep("telephony", "view")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _resp(svc.dashboard_summary(db, business_id, user_id=ctx.get_user_id(), auth_ctx=ctx), request)


# ─── PBX ────────────────────────────────────────────────────────────────────


@router.get(
	"/business/{business_id}/pbx",
	summary="فهرست مراکز تلفن",
	description="توکن کانکتور برنمی‌گردد. ابزار MCP: `list_telephony_pbx`.",
)
def list_pbx(
	request: Request,
	business_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(require_business_permission_dep("telephony", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	scope = resolve_scope(db, _ctx, business_id)
	return _resp({"items": svc.list_pbx(db, business_id, include_token_hint=scope.can_manage)}, request)


@router.post(
	"/business/{business_id}/pbx",
	summary="ایجاد مرکز تلفن",
	description="ممکن است توکن برگرداند؛ در MCP نیست. ویرایش بدون توکن: `update_telephony_pbx`.",
)
def create_pbx(
	request: Request,
	business_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(require_business_permission_dep("telephony", "manage")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _resp(svc.create_pbx(db, business_id, payload), request)


@router.patch(
	"/business/{business_id}/pbx/{pbx_id}",
	summary="ویرایش مرکز تلفن",
	description="بدون چرخش توکن. ابزار MCP: `update_telephony_pbx` (نیازمند تأیید).",
)
def patch_pbx(
	request: Request,
	business_id: int,
	pbx_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(require_business_permission_dep("telephony", "manage")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _resp(svc.update_pbx(db, business_id, pbx_id, payload), request)


@router.post(
	"/business/{business_id}/pbx/{pbx_id}/rotate-token",
	summary="چرخش توکن کانکتور PBX",
	description="خروجی شامل توکن است؛ در MCP نیست.",
)
def rotate_token(
	request: Request,
	business_id: int,
	pbx_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(require_business_permission_dep("telephony", "manage")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _resp(svc.rotate_pbx_token(db, business_id, pbx_id), request)


# ─── Extensions ─────────────────────────────────────────────────────────────


@router.get(
	"/business/{business_id}/extensions",
	summary="فهرست داخلی‌ها",
	description="ابزار MCP: `list_telephony_extensions`.",
)
def list_extensions(
	request: Request,
	business_id: int,
	pbx_id: Optional[int] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(require_business_permission_dep("telephony", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	scope = resolve_scope(db, _ctx, business_id)
	return _resp({"items": svc.list_extensions(db, business_id, pbx_id=pbx_id, scope=scope)}, request)


@router.post(
	"/business/{business_id}/extensions",
	summary="ثبت داخلی سانترال",
	description="ابزار MCP: `upsert_telephony_extension` (نیازمند تأیید).",
)
def upsert_extension(
	request: Request,
	business_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(require_business_permission_dep("telephony", "manage")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _resp(svc.upsert_extension(db, business_id, payload), request)


@router.post("/business/{business_id}/extensions/sync", summary="همگام‌سازی داخلی‌های سانترال", description="upsert فهرست داخلی روی یک PBX ذخیره‌شده. ابزار MCP: `sync_telephony_extensions`.")
def sync_extensions(
	request: Request,
	business_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(require_business_permission_dep("telephony", "manage")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	pbx_id = int(payload.get("pbx_id") or 0)
	items = payload.get("items") or payload.get("extensions") or []
	if not pbx_id:
		raise ApiError("PBX_ID_REQUIRED", "PBX_ID_REQUIRED", http_status=400)
	return _resp(svc.sync_extensions(db, business_id, pbx_id, items), request)


@router.get("/business/{business_id}/assignable-users", summary="کاربران قابل اتصال به داخلی", description="اعضای کسب‌وکار برای اتصال به داخلی. ابزار MCP: `list_telephony_assignable_users`.")
def assignable_users(
	request: Request,
	business_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(require_business_permission_dep("telephony", "manage")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _resp({"items": list_assignable_users(db, business_id)}, request)


@router.get("/business/{business_id}/team-supervisors", summary="ناظران تیم تلفن", description="کاربران با نقش نظارت تیم. ابزار MCP: `list_telephony_team_supervisors`.")
def team_supervisors(
	request: Request,
	business_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(require_business_permission_dep("telephony", "manage")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _resp({"items": list_team_supervisors(db, business_id)}, request)


@router.get(
	"/business/{business_id}/user-extensions",
	summary="اتصال کاربران به داخلی",
	description="ابزار MCP: `list_telephony_user_extensions`.",
)
def list_user_extensions(
	request: Request,
	business_id: int,
	user_id: Optional[int] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(require_business_permission_dep("telephony", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	scope = resolve_scope(db, _ctx, business_id)
	return _resp({"items": svc.list_user_extensions(db, business_id, user_id=user_id, scope=scope)}, request)


@router.put(
	"/business/{business_id}/user-extensions",
	summary="اتصال کاربر به داخلی",
	description="ابزار MCP: `upsert_telephony_user_extension` (نیازمند تأیید).",
)
def upsert_user_extension(
	request: Request,
	business_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(require_business_permission_dep("telephony", "manage")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _resp(svc.upsert_user_extension(db, business_id, payload), request)


@router.delete(
	"/business/{business_id}/user-extensions/{link_id}",
	summary="حذف اتصال کاربر به داخلی",
	description="ابزار MCP: `delete_telephony_user_extension` (نیازمند تأیید).",
)
def delete_user_extension(
	request: Request,
	business_id: int,
	link_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(require_business_permission_dep("telephony", "manage")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	svc.delete_user_extension(db, business_id, link_id)
	return _resp({"ok": True}, request)


# ─── Calls ──────────────────────────────────────────────────────────────────


@router.get(
	"/business/{business_id}/calls",
	summary="فهرست تماس‌ها",
	description="ابزار MCP: `list_telephony_calls`. ضبط صوت در MCP نیست.",
)
def list_calls(
	request: Request,
	business_id: int,
	direction: Optional[str] = Query(None),
	status: Optional[str] = Query(None),
	assigned_user_id: Optional[int] = Query(None),
	person_id: Optional[int] = Query(None),
	q: Optional[str] = Query(None),
	limit: int = Query(50, ge=1, le=200),
	offset: int = Query(0, ge=0),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(require_business_permission_dep("telephony", "view")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _resp(
		svc.list_calls(
			db,
			business_id,
			direction=direction,
			status=status,
			assigned_user_id=assigned_user_id,
			person_id=person_id,
			q=q,
			limit=limit,
			offset=offset,
			auth_ctx=ctx,
		),
		request,
	)


@router.get(
	"/business/{business_id}/calls/{call_id}",
	summary="جزئیات تماس",
	description="ابزار MCP: `get_telephony_call`.",
)
def get_call(
	request: Request,
	business_id: int,
	call_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(require_business_permission_dep("telephony", "view")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _resp(svc.get_call(db, business_id, call_id, auth_ctx=ctx), request)


@router.patch(
	"/business/{business_id}/calls/{call_id}",
	summary="ویرایش تماس",
	description="ابزار MCP: `update_telephony_call` (نیازمند تأیید).",
)
def patch_call(
	request: Request,
	business_id: int,
	call_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(require_business_permission_dep("telephony", "view")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _resp(svc.patch_call(db, business_id, call_id, payload, auth_ctx=ctx), request)


@router.get("/business/{business_id}/calls/{call_id}/screen-pop-context", summary="زمینه پاپ‌آپ تماس", description="شخص/سرنخ مرتبط با تماس برای Screen-pop. ابزار MCP: `get_telephony_screen_pop`.")
def screen_pop(
	request: Request,
	business_id: int,
	call_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(require_business_permission_dep("telephony", "view")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _resp(svc.screen_pop_context(db, business_id, call_id, auth_ctx=ctx), request)


@router.post(
	"/business/{business_id}/calls/{call_id}/create-person",
	summary="ساخت شخص از تماس",
	description="ابزار MCP: `create_person_from_telephony_call` (نیازمند تأیید).",
)
def create_person(
	request: Request,
	business_id: int,
	call_id: int,
	payload: Dict[str, Any] = Body(default=None),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(require_business_permission_dep("telephony", "view")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _resp(svc.create_person_from_call(db, business_id, call_id, payload or {}, ctx.get_user_id(), auth_ctx=ctx), request)


@router.post(
	"/business/{business_id}/calls/{call_id}/create-lead",
	summary="ساخت سرنخ از تماس",
	description="ابزار MCP: `create_lead_from_telephony_call` (نیازمند تأیید).",
)
def create_lead(
	request: Request,
	business_id: int,
	call_id: int,
	payload: Dict[str, Any] = Body(default=None),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(require_business_permission_dep("telephony", "view")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _resp(svc.create_lead_from_call(db, business_id, call_id, payload or {}, ctx.get_user_id(), auth_ctx=ctx), request)


@router.post(
	"/business/{business_id}/click-to-call",
	summary="تماس خروجی Click-to-Call",
	description="ابزار MCP: `click_to_call` (نیازمند تأیید).",
)
def click_to_call(
	request: Request,
	business_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(require_telephony_click_or_view()),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _resp(svc.click_to_call(db, business_id, ctx.get_user_id(), payload), request)


@router.get(
	"/business/{business_id}/lookup-number",
	summary="تطبیق شماره با شخص یا سرنخ",
	description="ابزار MCP: `lookup_telephony_number`.",
)
def lookup_number(
	request: Request,
	business_id: int,
	number: str = Query(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(require_business_permission_dep("telephony", "view")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return _resp(svc.match_caller(db, business_id, number), request)


# ─── Connector endpoints ────────────────────────────────────────────────────


@router.post(
	"/connector/heartbeat",
	summary="heartbeat کانکتور PBX",
	description="کانکتور بدون احراز هویت کاربر کسب‌وکار؛ در MCP نیست.",
)
def connector_heartbeat(
	request: Request,
	payload: Dict[str, Any] = Body(...),
	authorization: Optional[str] = Header(None),
	x_hesabix_business_id: Optional[int] = Header(None, alias="X-Hesabix-Business-Id"),
	x_hesabix_pbx_id: Optional[int] = Header(None, alias="X-Hesabix-Pbx-Id"),
	db: Session = Depends(get_db),
) -> dict:
	token = _bearer_token(authorization)
	business_id = int(x_hesabix_business_id or payload.get("business_id") or 0)
	pbx_id = int(x_hesabix_pbx_id or payload.get("pbx_id") or 0)
	if not business_id or not pbx_id:
		raise ApiError("BUSINESS_AND_PBX_REQUIRED", "BUSINESS_AND_PBX_REQUIRED", http_status=400)
	pbx = svc.authenticate_connector(db, token=token, business_id=business_id, pbx_id=pbx_id)
	return _resp(svc.connector_heartbeat(db, pbx, payload), request)


@router.post(
	"/connector/events",
	summary="رویداد کانکتور PBX",
	description="مسیر کانکتور بدون نشست MCP است و در MCP ثبت نشده.",
)
def connector_events(
	request: Request,
	payload: Dict[str, Any] = Body(...),
	authorization: Optional[str] = Header(None),
	x_hesabix_business_id: Optional[int] = Header(None, alias="X-Hesabix-Business-Id"),
	x_hesabix_pbx_id: Optional[int] = Header(None, alias="X-Hesabix-Pbx-Id"),
	db: Session = Depends(get_db),
) -> dict:
	from app.services.telephony import recording_service as rec_svc

	token = _bearer_token(authorization)
	business_id = int(x_hesabix_business_id or payload.get("business_id") or 0)
	pbx_id = int(x_hesabix_pbx_id or payload.get("pbx_id") or 0)
	if not business_id or not pbx_id:
		raise ApiError("BUSINESS_AND_PBX_REQUIRED", "BUSINESS_AND_PBX_REQUIRED", http_status=400)
	pbx = svc.authenticate_connector(db, token=token, business_id=business_id, pbx_id=pbx_id)
	try:
		result = svc.process_connector_event(db, pbx, payload)
		return _resp(result, request)
	except ApiError:
		raise
	except Exception as e:
		try:
			rec_svc.push_dead_letter(
				db, business_id=business_id, pbx_id=pbx_id, payload=payload, error=str(e)
			)
			db.commit()
		except Exception:
			db.rollback()
		raise ApiError("EVENT_PROCESSING_FAILED", "EVENT_PROCESSING_FAILED", http_status=500)


@router.get(
	"/connector/commands/poll",
	summary="نظرسنجی فرمان کانکتور PBX",
	description="مسیر کانکتور است و در MCP ثبت نشده.",
)
def connector_poll(
	request: Request,
	authorization: Optional[str] = Header(None),
	x_hesabix_business_id: Optional[int] = Header(None, alias="X-Hesabix-Business-Id"),
	x_hesabix_pbx_id: Optional[int] = Header(None, alias="X-Hesabix-Pbx-Id"),
	limit: int = Query(10, ge=1, le=50),
	db: Session = Depends(get_db),
) -> dict:
	token = _bearer_token(authorization)
	business_id = int(x_hesabix_business_id or 0)
	pbx_id = int(x_hesabix_pbx_id or 0)
	if not business_id or not pbx_id:
		raise ApiError("BUSINESS_AND_PBX_REQUIRED", "BUSINESS_AND_PBX_REQUIRED", http_status=400)
	pbx = svc.authenticate_connector(db, token=token, business_id=business_id, pbx_id=pbx_id)
	return _resp({"items": svc.poll_commands(db, pbx, limit=limit)}, request)


@router.post(
	"/connector/commands/{command_id}/ack",
	summary="تأیید فرمان کانکتور PBX",
	description="مسیر کانکتور است و در MCP ثبت نشده.",
)
def connector_ack(
	request: Request,
	command_id: str,
	payload: Dict[str, Any] = Body(default=None),
	authorization: Optional[str] = Header(None),
	x_hesabix_business_id: Optional[int] = Header(None, alias="X-Hesabix-Business-Id"),
	x_hesabix_pbx_id: Optional[int] = Header(None, alias="X-Hesabix-Pbx-Id"),
	db: Session = Depends(get_db),
) -> dict:
	token = _bearer_token(authorization)
	business_id = int(x_hesabix_business_id or 0)
	pbx_id = int(x_hesabix_pbx_id or 0)
	if not business_id or not pbx_id:
		raise ApiError("BUSINESS_AND_PBX_REQUIRED", "BUSINESS_AND_PBX_REQUIRED", http_status=400)
	pbx = svc.authenticate_connector(db, token=token, business_id=business_id, pbx_id=pbx_id)
	return _resp(svc.ack_command(db, pbx, command_id, payload or {}), request)


@router.post(
	"/connector/recordings/meta",
	summary="متادیتای ضبط کانکتور",
	description="مسیر کانکتور/رسانه است و در MCP ثبت نشده.",
)
def connector_recording_meta(
	request: Request,
	payload: Dict[str, Any] = Body(...),
	authorization: Optional[str] = Header(None),
	x_hesabix_business_id: Optional[int] = Header(None, alias="X-Hesabix-Business-Id"),
	x_hesabix_pbx_id: Optional[int] = Header(None, alias="X-Hesabix-Pbx-Id"),
	db: Session = Depends(get_db),
) -> dict:
	from adapters.db.models.telephony import TelephonyCall
	from app.services.telephony.recording_service import apply_recording_meta, bump_metric

	token = _bearer_token(authorization)
	business_id = int(x_hesabix_business_id or payload.get("business_id") or 0)
	pbx_id = int(x_hesabix_pbx_id or payload.get("pbx_id") or 0)
	pbx = svc.authenticate_connector(db, token=token, business_id=business_id, pbx_id=pbx_id)
	uniqueid = str(payload.get("uniqueid") or "")
	call = (
		db.query(TelephonyCall)
		.filter(TelephonyCall.pbx_id == pbx.id, TelephonyCall.asterisk_uniqueid == uniqueid)
		.first()
	)
	if not call:
		raise ApiError("CALL_NOT_FOUND", "CALL_NOT_FOUND", http_status=404)
	apply_recording_meta(db, call, payload)
	bump_metric(db, business_id, "recordings_ready")
	db.commit()
	return _resp(svc.call_to_dict(call), request)


# ─── Phase 2 reports ────────────────────────────────────────────────────────


@router.get(
	"/business/{business_id}/reports/summary",
	summary="خلاصه گزارش تماس‌ها",
	description="ابزار MCP: `get_telephony_reports_summary`.",
)
def report_summary(
	request: Request,
	business_id: int,
	date_from: Optional[str] = Query(None),
	date_to: Optional[str] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(require_telephony_any("reports", "supervise", "manage")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	from app.services.telephony import reports_service as reports

	return _resp(reports.summary_report(db, business_id, date_from=date_from, date_to=date_to, auth_ctx=_ctx), request)


@router.get("/business/{business_id}/reports/operators", summary="گزارش اپراتورهای تلفن", description="آمار تماس به‌تفکیک اپراتور در بازه تاریخ. ابزار MCP: `get_telephony_operators_report`.")
def report_operators(
	request: Request,
	business_id: int,
	date_from: Optional[str] = Query(None),
	date_to: Optional[str] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(require_telephony_any("reports", "supervise", "manage")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	from app.services.telephony import reports_service as reports

	return _resp(reports.operators_report(db, business_id, date_from=date_from, date_to=date_to, auth_ctx=_ctx), request)


@router.get("/business/{business_id}/reports/by-person", summary="گزارش تماس به‌تفکیک شخص", description="ابزار MCP: `get_telephony_person_report`.")
def report_by_person(
	request: Request,
	business_id: int,
	date_from: Optional[str] = Query(None),
	date_to: Optional[str] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(require_telephony_any("reports", "supervise", "manage")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	from app.services.telephony import reports_service as reports

	return _resp(reports.by_person_report(db, business_id, date_from=date_from, date_to=date_to, auth_ctx=_ctx), request)


@router.get("/business/{business_id}/reports/by-extension", summary="گزارش تماس به‌تفکیک داخلی", description="ابزار MCP: `get_telephony_extension_report`.")
def report_by_extension(
	request: Request,
	business_id: int,
	date_from: Optional[str] = Query(None),
	date_to: Optional[str] = Query(None),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(require_telephony_any("reports", "supervise", "manage")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	from app.services.telephony import reports_service as reports

	return _resp(reports.by_extension_report(db, business_id, date_from=date_from, date_to=date_to, auth_ctx=_ctx), request)


# ─── Phase 2 recording / Phase 3 live / Phase 4 ops ──────────────────────────


@router.get(
	"/business/{business_id}/calls/{call_id}/recording",
	summary="دانلود ضبط تماس",
	description="باینری/رسانه است؛ در MCP نیست.",
)
def get_recording(
	request: Request,
	business_id: int,
	call_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(require_business_permission_dep("telephony", "view")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	from app.services.telephony import recording_service as rec_svc

	return _resp(rec_svc.recording_info(db, business_id, call_id, auth_ctx=ctx), request)


@router.get("/business/{business_id}/live/snapshot", summary="نمای زنده صف تماس", description="وضعیت زنده بدون استریم صوت. ابزار MCP: `get_telephony_live_snapshot`.")
def live_snapshot(
	request: Request,
	business_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(require_telephony_any("live_monitor", "supervise", "manage")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	from app.services.telephony import live_service as live

	return _resp(live.live_snapshot(db, business_id, auth_ctx=_ctx), request)


@router.post("/business/{business_id}/calls/{call_id}/control", summary="کنترل تماس سانترال", description="hangup/transfer/hold/resume. ابزار MCP: `control_telephony_call`.")
def control_call(
	request: Request,
	business_id: int,
	call_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(require_business_permission_dep("telephony", "control_calls")),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	from app.services.telephony import live_service as live

	return _resp(
		live.enqueue_control_command(
			db,
			business_id,
			ctx.get_user_id(),
			command_type=str(payload.get("action") or payload.get("type") or ""),
			auth_ctx=ctx,
			call_id=call_id,
			target=payload.get("target"),
			session_id=str(payload.get("session_id") or "") or None,
		),
		request,
	)


@router.get("/business/{business_id}/ops/metrics", summary="متریک عملیاتی تلفن", description="بدون فایل ضبط. ابزار MCP: `get_telephony_ops_metrics`.")
def ops_metrics(
	request: Request,
	business_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(require_business_permission_dep("telephony", "manage")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	from app.services.telephony import recording_service as rec_svc

	return _resp(rec_svc.metrics_summary(db, business_id), request)


@router.get("/business/{business_id}/ops/dead-letters", summary="صف مرده رویداد تلفن", description="ابزار MCP: `list_telephony_dead_letters`.")
def ops_dlq(
	request: Request,
	business_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(require_business_permission_dep("telephony", "manage")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	from app.services.telephony import recording_service as rec_svc

	return _resp({"items": rec_svc.list_dead_letters(db, business_id)}, request)


@router.post("/business/{business_id}/ops/dead-letters/{dlq_id}/resolve", summary="بستن آیتم صف مرده تلفن", description="ابزار MCP: `resolve_telephony_dead_letter`.")
def ops_dlq_resolve(
	request: Request,
	business_id: int,
	dlq_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(require_business_permission_dep("telephony", "manage")),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	from app.services.telephony import recording_service as rec_svc

	return _resp(rec_svc.resolve_dead_letter(db, business_id, dlq_id), request)


# ─── Softphone (Media Relay) ─────────────────────────────────────────────────


def _require_softphone_operator():
	"""softphone یا click_to_call یا view."""

	def _dep(
		business_id: int,
		ctx: AuthContext = Depends(get_current_user),
		db: Session = Depends(get_db),
	) -> None:
		from app.core.permissions import has_business_permission_for_business

		uid_ok = (
			has_business_permission_for_business(ctx, db, business_id, "telephony", "softphone")
			or has_business_permission_for_business(ctx, db, business_id, "telephony", "click_to_call")
			or has_business_permission_for_business(ctx, db, business_id, "telephony", "view")
		)
		if not uid_ok:
			raise ApiError("SOFTPHONE_FORBIDDEN", "SOFTPHONE_FORBIDDEN", http_status=403)

	return _dep


def _require_media_edge() -> None:
	"""Softphone media ops فقط روی Media Edge (workers=1)."""
	from app.services.telephony.media_edge import require_media_edge_process

	require_media_edge_process()


@router.get(
	"/internal/media-edge/snapshot",
	summary="نمای داخلی لبه رسانه",
	description="مسیر داخلی سامانه است و در MCP ثبت نشده.",
)
def media_edge_internal_snapshot(
	request: Request,
	pbx_id: Optional[int] = Query(default=None),
	x_hesabix_media_edge_token: Optional[str] = Header(default=None),
) -> dict:
	"""وضعیت media_hub برای API workers (فقط localhost یا token داخلی)."""
	from app.core.settings import get_settings
	from app.services.telephony.media_edge import is_media_edge_process, process_role
	from app.services.telephony.media_hub import media_hub

	client = request.client.host if request.client else ""
	settings = get_settings()
	expected = (settings.hesabix_media_edge_token or "").strip()
	token_ok = bool(expected) and (x_hesabix_media_edge_token or "").strip() == expected
	localhost_ok = client in ("127.0.0.1", "::1", "localhost")
	if not (localhost_ok or token_ok):
		raise ApiError("TELEPHONY_INTERNAL_ONLY", "TELEPHONY_INTERNAL_ONLY", http_status=403)
	if not is_media_edge_process():
		raise ApiError("SOFTPHONE_MEDIA_EDGE_REQUIRED", "SOFTPHONE_MEDIA_EDGE_REQUIRED", http_status=503)
	data: Dict[str, Any] = {
		"process_role": process_role(),
		"media_hub": media_hub.health(),
		"tunnel": media_hub.tunnel_snapshot(pbx_id) if pbx_id is not None else None,
	}
	if pbx_id is not None:
		data["tunnel_online"] = media_hub.tunnel_online(pbx_id)
	return _resp(data, request)


@router.get("/business/{business_id}/softphone/health", summary="سلامت سافت‌فون", description="بدون رمز SIP. ابزار MCP: `get_telephony_softphone_health`.")
def softphone_health(
	request: Request,
	business_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(_require_softphone_operator()),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	from app.services.telephony import softphone_service as soft_svc

	return _resp(soft_svc.softphone_health(db, business_id, ctx.get_user_id()), request)


@router.get(
	"/business/{business_id}/softphone/devices-config",
	summary="پیکربندی دستگاه سافت‌فون",
	description="ممکن است رمز SIP برگرداند؛ در MCP نیست. سلامت: `get_telephony_softphone_health`.",
)
def softphone_devices_config(
	request: Request,
	business_id: int,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(_require_softphone_operator()),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
) -> dict:
	from app.services.telephony import softphone_service as soft_svc

	return _resp(soft_svc.softphone_devices_config(db, business_id), request)


@router.post(
	"/business/{business_id}/softphone/sessions",
	summary="ایجاد نشست سافت‌فون",
	description="نشست SIP/رسانه است و در MCP ثبت نشده.",
)
def softphone_create_session(
	request: Request,
	business_id: int,
	payload: Dict[str, Any] = Body(default=None),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(_require_softphone_operator()),
	_____: None = Depends(_require_media_edge),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	from app.services.telephony import softphone_service as soft_svc

	return _resp(soft_svc.create_session(db, business_id, ctx.get_user_id(), payload or {}), request)


@router.post(
	"/business/{business_id}/softphone/sessions/{session_id}/heartbeat",
	summary="heartbeat نشست سافت‌فون",
	description="نشست SIP است و در MCP ثبت نشده.",
)
def softphone_session_heartbeat(
	request: Request,
	business_id: int,
	session_id: str,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(_require_softphone_operator()),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	from app.services.telephony import softphone_service as soft_svc

	return _resp(soft_svc.heartbeat_session(db, business_id, ctx.get_user_id(), session_id), request)


@router.delete(
	"/business/{business_id}/softphone/sessions/{session_id}",
	summary="پایان نشست سافت‌فون",
	description="نشست SIP است و در MCP ثبت نشده.",
)
def softphone_end_session(
	request: Request,
	business_id: int,
	session_id: str,
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(_require_softphone_operator()),
	_____: None = Depends(_require_media_edge),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	from app.services.telephony import softphone_service as soft_svc
	from app.services.telephony.media_hub import media_hub
	import asyncio

	data = soft_svc.end_session(db, business_id, ctx.get_user_id(), session_id, reason="api_delete")
	try:
		loop = asyncio.get_event_loop()
		if loop.is_running():
			asyncio.create_task(media_hub.unregister_client(session_id, reason="api_delete"))
		else:
			loop.run_until_complete(media_hub.unregister_client(session_id, reason="api_delete"))
	except Exception:
		pass
	return _resp(data, request)


@router.post(
	"/business/{business_id}/softphone/calls",
	summary="تماس خروجی سافت‌فون",
	description="رسانه/SIP است و در MCP ثبت نشده. JSON: `click_to_call`.",
)
async def softphone_outbound_call(
	request: Request,
	business_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(_require_softphone_operator()),
	_____: None = Depends(_require_media_edge),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	"""تماس خروجی Softphone — باید await start_bridge شود وگرنه Media Hub همه PCM را drop می‌کند."""
	import logging

	from app.services.telephony import softphone_service as soft_svc
	from app.services.telephony.media_hub import media_hub

	log = logging.getLogger("hesabix.telephony.api")
	result = soft_svc.start_outbound_relay_call(db, business_id, ctx.get_user_id(), payload or {})
	session_id = result.get("session_id")
	call = result.get("call") or {}
	as_uuid = result.get("audiosocket_uuid")
	if session_id:
		try:
			await media_hub.start_bridge(
				session_id=session_id,
				call_id=call.get("id"),
				direction="outbound",
				audiosocket_uuid=as_uuid,
			)
		except Exception as e:
			# Originate از طریق poll ادامه می‌یابد؛ ensure_bridge_active روی bridge.active کانکتور پل را می‌سازد.
			log.warning("start_bridge outbound deferred session=%s: %s", session_id, e)
	return _resp(result, request)


@router.post(
	"/business/{business_id}/softphone/calls/{call_id}/answer",
	summary="پاسخ تماس سافت‌فون",
	description="رسانه/SIP است و در MCP ثبت نشده. کنترل: `control_telephony_call`.",
)
async def softphone_answer_call(
	request: Request,
	business_id: int,
	call_id: int,
	payload: Dict[str, Any] = Body(default=None),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(_require_softphone_operator()),
	_____: None = Depends(_require_media_edge),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	import logging

	from app.services.telephony import softphone_service as soft_svc
	from app.services.telephony.media_hub import media_hub

	log = logging.getLogger("hesabix.telephony.api")
	result = soft_svc.enqueue_answer_inbound(db, business_id, ctx.get_user_id(), call_id, payload or {})
	session_id = result.get("session_id")
	as_uuid = result.get("audiosocket_uuid")
	if session_id:
		try:
			await media_hub.start_bridge(
				session_id=session_id,
				call_id=call_id,
				direction="inbound",
				audiosocket_uuid=as_uuid,
			)
		except Exception as e:
			log.warning("start_bridge inbound deferred session=%s: %s", session_id, e)
	return _resp(result, request)


@router.post(
	"/business/{business_id}/softphone/calls/{call_id}/dtmf",
	summary="ارسال DTMF سافت‌فون",
	description="رسانه/SIP است و در MCP ثبت نشده.",
)
def softphone_dtmf(
	request: Request,
	business_id: int,
	call_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_telephony_plugin_active()),
	____: None = Depends(_require_softphone_operator()),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	from app.services.telephony import softphone_service as soft_svc

	digit = str((payload or {}).get("digit") or "")
	session_id = (payload or {}).get("session_id")
	return _resp(
		soft_svc.enqueue_dtmf(db, business_id, ctx.get_user_id(), call_id, digit, session_id=session_id),
		request,
	)


@router.post(
	"/connector/media/events",
	summary="رویداد رسانه کانکتور",
	description="مسیر کانکتور/رسانه است و در MCP ثبت نشده.",
)
def connector_media_events(
	request: Request,
	payload: Dict[str, Any] = Body(...),
	authorization: Optional[str] = Header(default=None),
	x_hesabix_business_id: Optional[str] = Header(default=None),
	x_hesabix_pbx_id: Optional[str] = Header(default=None),
	_: None = Depends(_require_media_edge),
	db: Session = Depends(get_db),
) -> dict:
	"""رویدادهای کنترل رسانه از Connector (علاوه بر WSS)."""
	token = _bearer_token(authorization)
	business_id = int(x_hesabix_business_id or 0)
	pbx_id = int(x_hesabix_pbx_id or 0)
	pbx = svc.authenticate_connector(db, token=token, business_id=business_id, pbx_id=pbx_id)
	from app.services.telephony.media_hub import media_hub

	tunnel = media_hub.tunnel_snapshot(pbx.id)
	return _resp({"ok": True, "tunnel": tunnel, "received": payload.get("type")}, request)


@router.post(
	"/connector/media/quality",
	summary="کیفیت رسانه کانکتور",
	description="مسیر کانکتور/رسانه است و در MCP ثبت نشده.",
)
def connector_media_quality(
	request: Request,
	payload: Dict[str, Any] = Body(...),
	authorization: Optional[str] = Header(default=None),
	x_hesabix_business_id: Optional[str] = Header(default=None),
	x_hesabix_pbx_id: Optional[str] = Header(default=None),
	db: Session = Depends(get_db),
) -> dict:
	token = _bearer_token(authorization)
	business_id = int(x_hesabix_business_id or 0)
	pbx_id = int(x_hesabix_pbx_id or 0)
	svc.authenticate_connector(db, token=token, business_id=business_id, pbx_id=pbx_id)
	from app.services.telephony import softphone_service as soft_svc

	session_id = str(payload.get("session_id") or "")
	if session_id:
		soft_svc.mark_session_state(
			db,
			session_id,
			str(payload.get("state") or "in_call"),
			quality=payload.get("metrics") if isinstance(payload.get("metrics"), dict) else payload,
		)
	return _resp({"ok": True}, request)
