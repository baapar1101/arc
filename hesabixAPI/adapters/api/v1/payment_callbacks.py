from __future__ import annotations

from typing import Dict, Any

from fastapi import APIRouter, Depends, Request, Query
from sqlalchemy.orm import Session
from fastapi.responses import RedirectResponse
import json

from adapters.db.session import get_db
from app.core.responses import success_response
from app.services.payment_service import verify_payment_callback
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
	db: Session = Depends(get_db),
) -> dict:
	params = {"tx_id": tx_id, "Authority": Authority, "Status": Status}
	data = verify_payment_callback(db, "zarinpal", params)
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
	return success_response(data, request, message="TOPUP_CONFIRMED" if data.get("success") else "TOPUP_FAILED")


@router.get(
	"/parsian",
	summary="بازگشت از پارسیان",
)
def parsian_callback(
	request: Request,
	tx_id: int = Query(0, description="شناسه تراکنش داخلی"),
	Token: str | None = Query(None),
	status: str | None = Query(None),
	db: Session = Depends(get_db),
) -> dict:
	params = {"tx_id": tx_id, "Token": Token, "status": status}
	data = verify_payment_callback(db, "parsian", params)
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
	return success_response(data, request, message="TOPUP_CONFIRMED" if data.get("success") else "TOPUP_FAILED")



