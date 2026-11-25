"""API افزونه پرداخت اعتباری دیجی‌پی."""

from __future__ import annotations

import html
import json
from typing import Any, Dict, Optional

from fastapi import APIRouter, Body, Depends, Path, Query, Request
from fastapi.responses import HTMLResponse, JSONResponse
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.datetime_utils import resolve_calendar_type_for_request
from app.core.digipay_plugin_dependency import ensure_digipay_plugin_active
from app.core.i18n import get_request_translator, locale_dependency
from app.core.permissions import require_business_access_dep, require_business_permission_dep
from app.core.responses import ApiError, success_response
from app.services import digipay_service as svc

router = APIRouter(prefix="/digipay", tags=["digipay"])
public_router = APIRouter(prefix="/digipay", tags=["digipay-public"])


def _locale(request: Request) -> str:
	return get_request_translator(request).locale


def _cal(request: Request) -> str:
	try:
		return resolve_calendar_type_for_request(request)
	except Exception:
		return getattr(request.state, "calendar_type", None) or "jalali"


def _callback_url(request: Request, business_id: int) -> str:
	base = str(request.base_url).rstrip("/")
	return f"{base}/api/v1/digipay/callback/{int(business_id)}"


def _payload_from_callback(request: Request, body: Dict[str, Any] | None) -> Dict[str, Any]:
	data = dict(body or {})
	if request.query_params:
		for key, value in request.query_params.items():
			data.setdefault(key, value)
	return data


@router.get(
	"/business/{business_id}/settings",
	summary="تنظیمات دیجی‌پی کسب‌وکار",
	description="خواندن تنظیمات افزونه پرداخت اعتباری با فیلدهای محرمانه ماسک‌شده. افزونه digipay_credit باید فعال باشد. ابزار MCP: get_digipay_settings.",
)
def get_settings(
	request: Request,
	business_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("digipay", "view")),
) -> dict:
	ensure_digipay_plugin_active(db, business_id, locale=_locale(request))
	return success_response(svc.get_settings(db, business_id, locale=_locale(request)), request)


@router.put(
	"/business/{business_id}/settings",
	summary="ذخیره تنظیمات دیجی‌پی",
	description="به‌روزرسانی محیط sandbox/live، اعتبار درگاه، شخص تسویه، بانک، کارمزد و تحویل خودکار. رمز در پاسخ برنمی‌گردد. ابزار MCP (بدون رمز): update_digipay_settings.",
)
def put_settings(
	request: Request,
	business_id: int = Path(..., gt=0),
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("digipay", "manage")),
) -> dict:
	return success_response(svc.update_settings(db, business_id, payload or {}, locale=_locale(request)), request)


@router.post(
	"/business/{business_id}/settings/test",
	summary="آزمون اتصال دیجی‌پی",
	description="اتصال آزمایشی به API دیجی‌پی با اعتبار ذخیره‌شده. ابزار MCP: test_digipay_connection.",
)
def post_test_connection(
	request: Request,
	business_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("digipay", "manage")),
) -> dict:
	return success_response(svc.test_connection(db, business_id, locale=_locale(request)), request)


@router.post(
	"/business/{business_id}/tickets",
	summary="صدور تیکت پرداخت اعتباری دیجی‌پی",
	description="ایجاد تیکت و لینک هدایت مشتری. مبلغ و شماره موبایل الزامی است. callback از base_url ساخته می‌شود. ابزار MCP: create_digipay_ticket.",
)
def post_ticket(
	request: Request,
	business_id: int = Path(..., gt=0),
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("digipay", "operate")),
) -> dict:
	data = svc.create_ticket(
		db,
		business_id,
		int(ctx.get_user_id() or 0),
		payload or {},
		locale=_locale(request),
		callback_url=_callback_url(request, business_id),
		calendar_type=_cal(request),
	)
	return success_response(data, request)


@router.post(
	"/business/{business_id}/purchases/manual",
	summary="ثبت خرید دستی دیجی‌پی",
	description="ابزار MCP: `record_digipay_manual_purchase` (نیازمند تأیید).",
)
def post_manual_purchase(
	request: Request,
	business_id: int = Path(..., gt=0),
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("digipay", "operate")),
) -> dict:
	data = svc.record_manual_purchase(
		db,
		business_id,
		int(ctx.get_user_id() or 0),
		payload or {},
		locale=_locale(request),
		calendar_type=_cal(request),
	)
	return success_response(data, request)


@router.get(
	"/business/{business_id}/purchases",
	summary="لیست خریدهای دیجی‌پی",
	description="ابزار MCP: `list_digipay_purchases`.",
)
def get_purchases(
	request: Request,
	business_id: int = Path(..., gt=0),
	status: Optional[str] = Query(None),
	date_from: Optional[str] = Query(None),
	date_to: Optional[str] = Query(None),
	limit: int = Query(50, ge=1, le=200),
	offset: int = Query(0, ge=0),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("digipay", "view")),
) -> dict:
	return success_response(
		svc.list_purchases(
			db,
			business_id,
			locale=_locale(request),
			calendar_type=_cal(request),
			status=status,
			date_from=date_from,
			date_to=date_to,
			limit=limit,
			offset=offset,
		),
		request,
	)


@router.get(
	"/business/{business_id}/purchases/{purchase_id}",
	summary="جزئیات خرید دیجی‌پی",
	description="ابزار MCP: `get_digipay_purchase`.",
)
def get_purchase(
	request: Request,
	business_id: int = Path(..., gt=0),
	purchase_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("digipay", "view")),
) -> dict:
	return success_response(
		svc.get_purchase(db, business_id, purchase_id, locale=_locale(request), calendar_type=_cal(request)),
		request,
	)


@router.post(
	"/business/{business_id}/purchases/{purchase_id}/deliver",
	summary="تحویل خرید دیجی‌پی",
	description="ابزار MCP: `deliver_digipay_purchase` (نیازمند تأیید).",
)
def post_deliver(
	request: Request,
	business_id: int = Path(..., gt=0),
	purchase_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("digipay", "operate")),
) -> dict:
	return success_response(
		svc.deliver_purchase(
			db, business_id, purchase_id, locale=_locale(request), calendar_type=_cal(request)
		),
		request,
	)


@router.post(
	"/business/{business_id}/purchases/{purchase_id}/refund",
	summary="استرداد خرید دیجی‌پی",
	description="ابزار MCP: `refund_digipay_purchase` (نیازمند تأیید).",
)
def post_refund(
	request: Request,
	business_id: int = Path(..., gt=0),
	purchase_id: int = Path(..., gt=0),
	payload: Dict[str, Any] = Body(default={}),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("digipay", "operate")),
) -> dict:
	return success_response(
		svc.refund_purchase(
			db,
			business_id,
			purchase_id,
			payload or {},
			locale=_locale(request),
			calendar_type=_cal(request),
		),
		request,
	)


@router.post(
	"/business/{business_id}/purchases/{purchase_id}/attach-invoice",
	summary="اتصال خرید دیجی‌پی به فاکتور",
	description="invoice_id الزامی است. ابزار MCP: attach_digipay_purchase_invoice.",
)
def post_attach_invoice(
	request: Request,
	business_id: int = Path(..., gt=0),
	purchase_id: int = Path(..., gt=0),
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("digipay", "operate")),
) -> dict:
	invoice_id = int(payload.get("invoice_id") or 0)
	if invoice_id <= 0:
		raise ApiError("INVOICE_ID_REQUIRED", "invoice_id is required", http_status=400)
	receipt_id = payload.get("receipt_document_id")
	return success_response(
		svc.attach_purchase_to_invoice(
			db,
			business_id,
			purchase_id,
			invoice_id,
			int(receipt_id) if receipt_id else None,
			locale=_locale(request),
		),
		request,
	)


@router.post(
	"/business/{business_id}/settlements/preview",
	summary="پیش‌نمایش تسویه دیجی‌پی",
	description="ابزار MCP: `preview_digipay_settlement`.",
)
def post_settlement_preview(
	request: Request,
	business_id: int = Path(..., gt=0),
	payload: Dict[str, Any] = Body(default={}),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("digipay", "view")),
) -> dict:
	return success_response(svc.preview_settlement(db, business_id, payload or {}, locale=_locale(request)), request)


@router.post(
	"/business/{business_id}/settlements",
	summary="ثبت تسویه دیجی‌پی",
	description="ثبت سند تسویه خریدهای انتخاب‌شده. ابزار MCP: `register_digipay_settlement` (نیازمند تأیید).",
)
def post_settlement(
	request: Request,
	business_id: int = Path(..., gt=0),
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("digipay", "manage")),
) -> dict:
	return success_response(
		svc.register_settlement(
			db,
			business_id,
			int(ctx.get_user_id() or 0),
			payload or {},
			locale=_locale(request),
			calendar_type=_cal(request),
		),
		request,
	)


@router.get(
	"/business/{business_id}/settlements",
	summary="لیست تسویه‌های دیجی‌پی",
	description="تسویه‌های همین کسب‌وکار. ابزار MCP: list_digipay_settlements.",
)
def get_settlements(
	request: Request,
	business_id: int = Path(..., gt=0),
	limit: int = Query(50, ge=1, le=200),
	offset: int = Query(0, ge=0),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(locale_dependency),
	__: None = Depends(require_business_access_dep),
	___: None = Depends(require_business_permission_dep("digipay", "view")),
) -> dict:
	return success_response(
		svc.list_settlements(
			db,
			business_id,
			locale=_locale(request),
			calendar_type=_cal(request),
			limit=limit,
			offset=offset,
		),
		request,
	)


def _handle_public_callback(request: Request, business_id: int, db: Session, payload: Dict[str, Any]) -> Any:
	want_json = "application/json" in (request.headers.get("accept") or "").lower()
	locale = _locale(request)
	is_fa = locale.startswith("fa")
	try:
		purchase = svc.handle_callback(db, business_id, payload, locale=locale)
	except ApiError as exc:
		if want_json:
			raise
		return HTMLResponse(
			f"<html><body><h1>DigiPay</h1><p>{exc.message}</p></body></html>",
			status_code=exc.status_code,
		)
	ok = purchase.status in {"verified", "delivered", "paid"}
	if want_json:
		return JSONResponse({"success": ok, "status": purchase.status, "provider_id": purchase.provider_id})
	status_label = "success" if ok else "failed"
	title = ("پرداخت موفق" if ok else "پرداخت ناموفق") if is_fa else ("Payment successful" if ok else "Payment failed")
	tracking = ("کد پیگیری" if is_fa else "Tracking code")
	hint = (
		"می‌توانید این پنجره را ببندید و به نرم‌افزار حسابیکس برگردید."
		if is_fa
		else "You can close this window and return to Hesabix."
	)
	safe_tracking = html.escape(str(purchase.tracking_code or "-"), quote=True)
	provider_js = json.dumps(str(purchase.provider_id or ""))
	status_js = json.dumps(status_label)
	page = (
		"<html><body style='font-family:sans-serif;text-align:center;padding:48px'>"
		f"<h1>{html.escape(title)}</h1>"
		f"<p>{html.escape(tracking)}: {safe_tracking}</p>"
		f"<p>{html.escape(hint)}</p>"
		f"<script>try{{window.opener&&window.opener.postMessage({{source:'digipay',status:{status_js},providerId:{provider_js}}},'*');}}catch(e){{}}</script>"
		"</body></html>"
	)
	return HTMLResponse(page)


@public_router.api_route("/callback/{business_id}", methods=["GET", "POST"])
async def public_callback(
	request: Request,
	business_id: int = Path(..., gt=0),
	db: Session = Depends(get_db),
) -> Any:
	body: Dict[str, Any] = {}
	if request.method == "POST":
		ctype = (request.headers.get("content-type") or "").lower()
		try:
			if "application/json" in ctype:
				raw = await request.json()
				if isinstance(raw, dict):
					body = raw
			else:
				form = await request.form()
				body = {str(k): form.get(k) for k in form.keys()}
		except Exception:
			body = {}
	payload = _payload_from_callback(request, body)
	return _handle_public_callback(request, business_id, db, payload)
