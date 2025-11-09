from __future__ import annotations

from typing import Dict, Any, List
import json

from fastapi import APIRouter, Depends, Request, Body, Path, Query
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError
from adapters.db.models.payment_gateway import PaymentGateway


router = APIRouter(prefix="/admin/payment-gateways", tags=["admin-payment-gateways"])


def _mask_config(cfg: dict) -> dict:
	"""Mask sensitive fields in config for safe output"""
	if not isinstance(cfg, dict):
		return {}
	masked = dict(cfg)
	for key in ["merchant_id", "terminal_id", "username", "password", "secret", "secret_key", "api_key"]:
		if key in masked and masked[key]:
			val = str(masked[key])
			if len(val) > 6:
				masked[key] = f"{val[:2]}***{val[-2:]}"
			else:
				masked[key] = "***"
	return masked


@router.get(
	"",
	summary="فهرست درگاه‌های پرداخت",
)
def list_payment_gateways(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	items = db.query(PaymentGateway).order_by(PaymentGateway.id.desc()).all()
	data = []
	for it in items:
		cfg = {}
		try:
			cfg = json.loads(it.config_json or "{}")
		except Exception:
			cfg = {}
		data.append({
			"id": it.id,
			"provider": it.provider,
			"display_name": it.display_name,
			"is_active": it.is_active,
			"is_sandbox": it.is_sandbox,
			"config": _mask_config(cfg),
		})
	return success_response(data, request)


@router.post(
	"",
	summary="ایجاد درگاه پرداخت",
)
def create_payment_gateway(
	request: Request,
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	provider = str(payload.get("provider") or "").strip().lower()
	display_name = str(payload.get("display_name") or "").strip()
	is_active = bool(payload.get("is_active", True))
	is_sandbox = bool(payload.get("is_sandbox", True))
	config = payload.get("config") or {}
	if provider not in ("zarinpal", "parsian"):
		raise ApiError("UNSUPPORTED_PROVIDER", "provider باید یکی از zarinpal یا parsian باشد", http_status=400)
	if not display_name:
		raise ApiError("INVALID_NAME", "display_name الزامی است", http_status=400)
	gw = PaymentGateway(
		provider=provider,
		display_name=display_name,
		is_active=is_active,
		is_sandbox=is_sandbox,
		config_json=json.dumps(config, ensure_ascii=False),
	)
	db.add(gw)
	db.commit()
	db.refresh(gw)
	return success_response({"id": gw.id}, request, message="GATEWAY_CREATED")


@router.get(
	"/{gateway_id}",
	summary="دریافت جزئیات درگاه پرداخت",
)
def get_payment_gateway(
	request: Request,
	gateway_id: int = Path(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	gw = db.query(PaymentGateway).filter(PaymentGateway.id == int(gateway_id)).first()
	if not gw:
		raise ApiError("NOT_FOUND", "درگاه یافت نشد", http_status=404)
	cfg = {}
	try:
		cfg = json.loads(gw.config_json or "{}")
	except Exception:
		cfg = {}
	data = {
		"id": gw.id,
		"provider": gw.provider,
		"display_name": gw.display_name,
		"is_active": gw.is_active,
		"is_sandbox": gw.is_sandbox,
		"config": _mask_config(cfg),
	}
	return success_response(data, request)


@router.put(
	"/{gateway_id}",
	summary="ویرایش درگاه پرداخت",
)
def update_payment_gateway(
	request: Request,
	gateway_id: int = Path(...),
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	gw = db.query(PaymentGateway).filter(PaymentGateway.id == int(gateway_id)).first()
	if not gw:
		raise ApiError("NOT_FOUND", "درگاه یافت نشد", http_status=404)
	if "provider" in payload:
		gw.provider = str(payload.get("provider") or gw.provider).strip().lower()
	if "display_name" in payload:
		gw.display_name = str(payload.get("display_name") or gw.display_name)
	if "is_active" in payload:
		gw.is_active = bool(payload.get("is_active"))
	if "is_sandbox" in payload:
		gw.is_sandbox = bool(payload.get("is_sandbox"))
	if "config" in payload:
		cfg = payload.get("config") or {}
		gw.config_json = json.dumps(cfg, ensure_ascii=False)
	db.commit()
	db.refresh(gw)
	return success_response({"id": gw.id}, request, message="GATEWAY_UPDATED")


@router.delete(
	"/{gateway_id}",
	summary="حذف درگاه پرداخت",
)
def delete_payment_gateway(
	request: Request,
	gateway_id: int = Path(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	gw = db.query(PaymentGateway).filter(PaymentGateway.id == int(gateway_id)).first()
	if not gw:
		raise ApiError("NOT_FOUND", "درگاه یافت نشد", http_status=404)
	db.delete(gw)
	db.commit()
	return success_response({"id": gateway_id}, request, message="GATEWAY_DELETED")



