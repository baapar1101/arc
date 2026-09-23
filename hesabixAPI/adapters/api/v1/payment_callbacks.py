from typing import Any, Dict, Optional

from fastapi import APIRouter, Depends, Request, Query
from sqlalchemy.orm import Session
from fastapi.responses import RedirectResponse, HTMLResponse
import json

from adapters.db.session import get_db
from app.core.responses import success_response
from app.services.payment_service import verify_payment_callback
from app.services.public_invoice_share_payment_service import maybe_redirect_public_invoice_share_payment_return
from app.core.payment_response import (
	render_payment_success,
	render_payment_failed,
	detect_source,
	should_return_json,
	resolve_payment_display_name,
	wallet_return_urls,
)
from adapters.db.models.wallet import WalletTransaction
from adapters.db.models.payment_gateway import PaymentGateway


router = APIRouter(prefix="/wallet/payments/callback", tags=["wallet-callbacks"])


def _resolve_business_id(db: Session, tx_id: int) -> Optional[int]:
	if tx_id <= 0:
		return None
	tx = db.query(WalletTransaction).filter(WalletTransaction.id == int(tx_id)).first()
	return int(tx.business_id) if tx and tx.business_id else None


def _resolve_amount(db: Session, tx_id: int, data: Dict[str, Any]) -> float:
	raw = data.get("amount")
	try:
		if raw is not None and float(raw) > 0:
			return float(raw)
	except (TypeError, ValueError):
		pass
	if tx_id > 0:
		tx = db.query(WalletTransaction).filter(WalletTransaction.id == int(tx_id)).first()
		if tx is not None:
			try:
				return float(tx.amount or 0)
			except (TypeError, ValueError):
				return 0.0
	return 0.0


def _maybe_gateway_redirect(
	db: Session,
	tx_id: int,
	data: Dict[str, Any],
) -> Optional[RedirectResponse]:
	try:
		tx = db.query(WalletTransaction).filter(WalletTransaction.id == int(tx_id)).first()
		if tx and tx.extra_info:
			extra = json.loads(tx.extra_info)
			gateway_id = extra.get("gateway_id")
			if gateway_id:
				gw = db.query(PaymentGateway).filter(PaymentGateway.id == int(gateway_id)).first()
				if gw and gw.config_json:
					cfg = json.loads(gw.config_json or "{}")
					target = None
					if data.get("success"):
						target = cfg.get("success_redirect")
					else:
						target = cfg.get("failure_redirect")
					if target:
						from urllib.parse import urlencode, urlparse, parse_qsl, urlunparse
						u = urlparse(target)
						q = dict(parse_qsl(u.query))
						q.update({
							"tx_id": str(tx_id),
							"status": "success" if data.get("success") else "failed",
							"ref": (data.get("external_ref") or ""),
						})
						location = urlunparse((u.scheme, u.netloc, u.path, u.params, urlencode(q), u.fragment))
						return RedirectResponse(url=location, status_code=302)
	except Exception:
		pass
	return None


def _render_wallet_result(
	request: Request,
	db: Session,
	tx_id: int,
	data: Dict[str, Any],
	detected_source: str,
):
	app_name = resolve_payment_display_name(db)
	urls = wallet_return_urls(db, business_id=_resolve_business_id(db, tx_id))
	if data.get("success"):
		return render_payment_success(
			request=request,
			transaction_id=tx_id,
			amount=_resolve_amount(db, tx_id, data),
			external_ref=data.get("external_ref", "") or "",
			card_num=data.get("card_num"),
			source=detected_source,
			dashboard_url=urls["dashboard_url"],
			app_name=app_name,
		)
	return render_payment_failed(
		request=request,
		transaction_id=tx_id,
		external_ref=data.get("external_ref"),
		error_message="تراکنش توسط بانک تایید نشد.",
		source=detected_source,
		retry_url=urls["retry_url"],
		dashboard_url=urls["dashboard_url"],
		support_url=urls["support_url"],
		app_name=app_name,
	)


@router.get(
	"/zarinpal",
	summary="بازگشت از زرین‌پال",
)
def zarinpal_callback(
	request: Request,
	tx_id: int = Query(0, description="شناسه تراکنش داخلی"),
	Authority: str | None = Query(None),
	Status: str | None = Query(None),
	source: str | None = Query(None, description="منبع درخواست (app/mobile_web/desktop)"),
	db: Session = Depends(get_db),
):
	params = {"tx_id": tx_id, "Authority": Authority, "Status": Status}
	data = verify_payment_callback(db, "zarinpal", params)

	redir = maybe_redirect_public_invoice_share_payment_return(db, tx_id=tx_id, verify_data=data)
	if redir is not None:
		return redir

	detected_source = detect_source(request, source)

	gw_redir = _maybe_gateway_redirect(db, tx_id, data)
	if gw_redir is not None:
		return gw_redir

	if should_return_json(request):
		return success_response(data, request, message="TOPUP_CONFIRMED" if data.get("success") else "TOPUP_FAILED")

	return _render_wallet_result(request, db, tx_id, data, detected_source)


@router.get(
	"/parsian",
	summary="بازگشت از پارسیان",
)
@router.post(
	"/parsian",
	summary="بازگشت از پارسیان (POST)",
)
async def parsian_callback(
	request: Request,
	tx_id: int = Query(0, description="شناسه تراکنش داخلی"),
	Token: str | None = Query(None),
	status: str | None = Query(None),
	OrderId: str | None = Query(None),
	Amount: str | None = Query(None),
	RRN: str | None = Query(None),
	source: str | None = Query(None, description="منبع درخواست (app/mobile_web/desktop)"),
	db: Session = Depends(get_db),
):
	params: Dict[str, Any] = {
		"tx_id": tx_id,
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
		except Exception:
			pass
	try:
		params["tx_id"] = int(params.get("tx_id") or tx_id or 0)
	except (TypeError, ValueError):
		params["tx_id"] = int(tx_id or 0)
	data = verify_payment_callback(db, "parsian", params)
	tx_id = int(data.get("transaction_id") or params.get("tx_id") or tx_id or 0)

	redir = maybe_redirect_public_invoice_share_payment_return(db, tx_id=tx_id, verify_data=data)
	if redir is not None:
		return redir

	detected_source = detect_source(request, source)

	gw_redir = _maybe_gateway_redirect(db, tx_id, data)
	if gw_redir is not None:
		return gw_redir

	if should_return_json(request):
		return success_response(data, request, message="TOPUP_CONFIRMED" if data.get("success") else "TOPUP_FAILED")

	return _render_wallet_result(request, db, tx_id, data, detected_source)


@router.get(
	"/bitpay",
	summary="بازگشت از بیت‌پی",
)
def bitpay_callback(
	request: Request,
	tx_id: int = Query(0, description="شناسه تراکنش داخلی"),
	trans_id: str | None = Query(None, description="شماره پیگیری تراکنش از بیت‌پی"),
	id_get: str | None = Query(None, description="شناسه پرداخت از بیت‌پی"),
	source: str | None = Query(None, description="منبع درخواست (app/mobile_web/desktop)"),
	db: Session = Depends(get_db),
):
	params = {"tx_id": tx_id, "trans_id": trans_id, "id_get": id_get}
	data = verify_payment_callback(db, "bitpay", params)

	redir = maybe_redirect_public_invoice_share_payment_return(db, tx_id=tx_id, verify_data=data)
	if redir is not None:
		return redir

	detected_source = detect_source(request, source)

	gw_redir = _maybe_gateway_redirect(db, tx_id, data)
	if gw_redir is not None:
		return gw_redir

	if should_return_json(request):
		return success_response(data, request, message="TOPUP_CONFIRMED" if data.get("success") else "TOPUP_FAILED")

	return _render_wallet_result(request, db, tx_id, data, detected_source)
