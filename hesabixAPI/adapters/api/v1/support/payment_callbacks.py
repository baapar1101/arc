"""Callback درگاه برای پرداخت اشتراک پشتیبانی."""

from __future__ import annotations

from typing import Any, Optional
from urllib.parse import parse_qsl, urlencode, urlparse, urlunparse

from fastapi import APIRouter, Depends, Query, Request
from fastapi.responses import RedirectResponse
from sqlalchemy.orm import Session

from adapters.db.models.support.billing import SupportPaymentSession
from adapters.db.session import get_db
from app.core.payment_response import (
	detect_source,
	render_payment_failed,
	render_payment_success,
	resolve_frontend_base_url,
	resolve_payment_display_name,
	should_return_json,
	support_return_urls,
)
from app.core.responses import success_response
from app.services.support.support_payment_gateway import verify_support_gateway_payment

router = APIRouter(prefix="/support/payments/callback", tags=["support-payment-callbacks"])


def _handle_callback(
	request: Request,
	provider: str,
	db: Session,
	session_id: int,
	params: dict[str, Any],
	source: Optional[str],
):
	params = dict(params)
	params["session_id"] = session_id
	data = verify_support_gateway_payment(db, provider=provider, params=params)

	# Redirect به مسیر اپ در صورت وجود client_return_path
	try:
		session = db.query(SupportPaymentSession).filter(SupportPaymentSession.id == int(session_id)).first()
		if session and session.client_return_path:
			path = session.client_return_path
			if path.startswith("http"):
				target = path
			else:
				front = resolve_frontend_base_url(db)
				if not front:
					raise ValueError("frontend base url is not configured")
				target = f"{front}{path if path.startswith('/') else '/' + path}"
			u = urlparse(target)
			q = dict(parse_qsl(u.query))
			q.update(
				{
					"session_id": str(session_id),
					"status": "success" if data.get("success") else "failed",
					"invoice_id": str(data.get("invoice_id") or ""),
					"ref": str(data.get("external_ref") or ""),
				}
			)
			location = urlunparse((u.scheme, u.netloc, u.path, u.params, urlencode(q), u.fragment))
			if u.scheme and u.netloc:
				return RedirectResponse(url=location, status_code=302)
	except Exception:
		pass

	detected = detect_source(request, source)
	if should_return_json(request):
		return success_response(
			data,
			request,
			message="SUPPORT_PAYMENT_OK" if data.get("success") else "SUPPORT_PAYMENT_FAILED",
		)

	app_name = resolve_payment_display_name(db)
	urls = support_return_urls(db)
	amount = 0.0
	try:
		amount = float(data.get("amount") or 0)
	except (TypeError, ValueError):
		amount = 0.0
	if amount <= 0 and session_id > 0:
		session = db.query(SupportPaymentSession).filter(SupportPaymentSession.id == int(session_id)).first()
		if session is not None:
			try:
				amount = float(session.amount or 0)
			except (TypeError, ValueError):
				amount = 0.0

	if data.get("success"):
		return render_payment_success(
			request,
			transaction_id=int(session_id),
			amount=amount,
			external_ref=str(data.get("external_ref") or ""),
			source=detected,
			dashboard_url=urls["dashboard_url"],
			app_name=app_name,
		)
	return render_payment_failed(
		request,
		transaction_id=int(session_id),
		external_ref=str(data.get("external_ref") or "") or None,
		error_message="پرداخت اشتراک پشتیبانی ناموفق بود",
		source=detected,
		retry_url=urls["retry_url"],
		dashboard_url=urls["dashboard_url"],
		support_url=urls["support_url"],
		app_name=app_name,
	)


@router.get("/zarinpal")
def zarinpal_callback(
	request: Request,
	session_id: int = Query(0),
	Authority: Optional[str] = Query(None),
	Status: Optional[str] = Query(None),
	source: Optional[str] = Query(None),
	db: Session = Depends(get_db),
):
	return _handle_callback(
		request,
		"zarinpal",
		db,
		session_id,
		{"Authority": Authority, "Status": Status},
		source,
	)


@router.get("/parsian")
@router.post("/parsian")
async def parsian_callback(
	request: Request,
	session_id: int = Query(0),
	Token: Optional[str] = Query(None),
	status: Optional[str] = Query(None),
	OrderId: Optional[str] = Query(None),
	Amount: Optional[str] = Query(None),
	RRN: Optional[str] = Query(None),
	source: Optional[str] = Query(None),
	db: Session = Depends(get_db),
):
	params: dict[str, Any] = {
		"Token": Token,
		"status": status,
		"OrderId": OrderId,
		"Amount": Amount,
		"RRN": RRN,
	}
	if request.method == "POST":
		try:
			form = await request.form()
			for k, v in form.items():
				params[str(k)] = v
			if not session_id:
				session_id = int(params.get("session_id") or 0)
		except Exception:
			pass
	if not session_id:
		try:
			from app.services.parsian_gateway import decode_order_id, parse_amount
			scope, decoded = decode_order_id(parse_amount(params.get("OrderId") or 0))
			if scope == "support" and decoded > 0:
				session_id = decoded
		except Exception:
			pass
	return _handle_callback(request, "parsian", db, session_id, params, source)


@router.get("/bitpay")
@router.post("/bitpay")
async def bitpay_callback(
	request: Request,
	session_id: int = Query(0),
	trans_id: Optional[str] = Query(None),
	id_get: Optional[str] = Query(None),
	source: Optional[str] = Query(None),
	db: Session = Depends(get_db),
):
	params: dict[str, Any] = {"trans_id": trans_id, "id_get": id_get}
	if request.method == "POST":
		try:
			form = await request.form()
			for k, v in form.items():
				params[str(k)] = v
			if not session_id:
				session_id = int(params.get("session_id") or 0)
		except Exception:
			pass
	return _handle_callback(request, "bitpay", db, session_id, params, source)
