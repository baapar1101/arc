from typing import Dict, Any

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
    should_return_json
)
from adapters.db.models.wallet import WalletTransaction
from adapters.db.models.payment_gateway import PaymentGateway


router = APIRouter(prefix="/wallet/payments/callback", tags=["wallet-callbacks"])


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
	
	# تشخیص منبع درخواست
	detected_source = detect_source(request, source)
	
	# Optional auto-redirect based on gateway config
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
	
	# اگر کاربر JSON می‌خواهد (برای API calls)
	if should_return_json(request):
		return success_response(data, request, message="TOPUP_CONFIRMED" if data.get("success") else "TOPUP_FAILED")
	
	# پیش‌فرض: نمایش صفحه HTML زیبا
	if data.get("success"):
		return render_payment_success(
			request=request,
			transaction_id=tx_id,
			amount=data.get("amount", 0),
			external_ref=data.get("external_ref", ""),
			card_num=data.get("card_num"),
			source=detected_source,
			dashboard_url="https://hsxn.hesabix.ir/dashboard",
		)
	else:
		return render_payment_failed(
			request=request,
			transaction_id=tx_id,
			external_ref=data.get("external_ref"),
			error_message="تراکنش توسط بانک تایید نشد.",
			source=detected_source,
			retry_url="https://hsxn.hesabix.ir/wallet",
			dashboard_url="https://hsxn.hesabix.ir/dashboard",
			support_url="https://hsxn.hesabix.ir/support",
		)


@router.get(
	"/parsian",
	summary="بازگشت از پارسیان",
)
def parsian_callback(
	request: Request,
	tx_id: int = Query(0, description="شناسه تراکنش داخلی"),
	Token: str | None = Query(None),
	status: str | None = Query(None),
	source: str | None = Query(None, description="منبع درخواست (app/mobile_web/desktop)"),
	db: Session = Depends(get_db),
):
	params = {"tx_id": tx_id, "Token": Token, "status": status}
	data = verify_payment_callback(db, "parsian", params)

	redir = maybe_redirect_public_invoice_share_payment_return(db, tx_id=tx_id, verify_data=data)
	if redir is not None:
		return redir
	
	# تشخیص منبع درخواست
	detected_source = detect_source(request, source)
	
	# Optional auto-redirect based on gateway config
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
	
	# اگر کاربر JSON می‌خواهد (برای API calls)
	if should_return_json(request):
		return success_response(data, request, message="TOPUP_CONFIRMED" if data.get("success") else "TOPUP_FAILED")
	
	# پیش‌فرض: نمایش صفحه HTML زیبا
	if data.get("success"):
		return render_payment_success(
			request=request,
			transaction_id=tx_id,
			amount=data.get("amount", 0),
			external_ref=data.get("external_ref", ""),
			card_num=data.get("card_num"),
			source=detected_source,
			dashboard_url="https://hsxn.hesabix.ir/dashboard",
		)
	else:
		return render_payment_failed(
			request=request,
			transaction_id=tx_id,
			external_ref=data.get("external_ref"),
			error_message="تراکنش توسط بانک تایید نشد.",
			source=detected_source,
			retry_url="https://hsxn.hesabix.ir/wallet",
			dashboard_url="https://hsxn.hesabix.ir/dashboard",
			support_url="https://hsxn.hesabix.ir/support",
		)


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
	
	# تشخیص منبع درخواست
	detected_source = detect_source(request, source)
	
	# Optional auto-redirect based on gateway config
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
	
	# اگر کاربر JSON می‌خواهد (برای API calls)
	if should_return_json(request):
		return success_response(data, request, message="TOPUP_CONFIRMED" if data.get("success") else "TOPUP_FAILED")
	
	# پیش‌فرض: نمایش صفحه HTML زیبا
	if data.get("success"):
		return render_payment_success(
			request=request,
			transaction_id=tx_id,
			amount=data.get("amount", 0),
			external_ref=data.get("external_ref", ""),
			card_num=data.get("card_num"),
			source=detected_source,
			dashboard_url="https://hsxn.hesabix.ir/dashboard",
		)
	else:
		return render_payment_failed(
			request=request,
			transaction_id=tx_id,
			external_ref=data.get("external_ref"),
			error_message="تراکنش توسط بانک تایید نشد.",
			source=detected_source,
			retry_url="https://hsxn.hesabix.ir/wallet",
			dashboard_url="https://hsxn.hesabix.ir/dashboard",
			support_url="https://hsxn.hesabix.ir/support",
		)



