"""API صورتحساب و اشتراک پشتیبانی برای کاربر نهایی."""

from __future__ import annotations

from typing import Any, Dict, Optional

from fastapi import APIRouter, Body, Depends, Query, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.responses import success_response
from app.services.support.support_billing_service import (
	checkout_support_plan,
	get_user_invoice,
	get_user_subscription,
	list_user_invoices,
	retry_invoice_payment,
)
from app.services.support.support_entitlement_service import get_support_entitlement
from app.services.support.support_payment_gateway import list_active_system_gateways
from app.services.support.support_plan_service import list_support_plans
from app.services.system_settings_service import assert_end_user_support_tickets_allowed

router = APIRouter(tags=["support-billing"])


@router.get("/billing/entitlement")
def entitlement_endpoint(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = get_support_entitlement(db, ctx.get_user_id())
	return success_response(data, request)


@router.get("/billing/plans")
def public_plans_endpoint(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	assert_end_user_support_tickets_allowed(db)
	data = list_support_plans(db, only_active=True)
	# فقط پلن‌های قابل نمایش؛ رایگان‌های غیرفعال در ادمین می‌مانند
	return success_response({"items": data}, request)


@router.get("/billing/subscription")
def subscription_endpoint(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = get_user_subscription(db, ctx.get_user_id())
	return success_response(data, request)


@router.get("/billing/invoices")
def invoices_endpoint(
	request: Request,
	limit: int = Query(50, ge=1, le=100),
	offset: int = Query(0, ge=0),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = list_user_invoices(db, ctx.get_user_id(), limit=limit, offset=offset)
	return success_response(data, request)


@router.get("/billing/invoices/{invoice_id}")
def invoice_detail_endpoint(
	invoice_id: int,
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = get_user_invoice(db, ctx.get_user_id(), invoice_id)
	return success_response(data, request)


@router.get("/billing/gateways")
def gateways_endpoint(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	return success_response({"items": list_active_system_gateways(db)}, request)


@router.post("/billing/checkout")
def checkout_endpoint(
	request: Request,
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	assert_end_user_support_tickets_allowed(db)
	plan_id = int(payload.get("plan_id") or 0)
	gateway_id = payload.get("gateway_id")
	gateway_id_int = int(gateway_id) if gateway_id not in (None, "", 0, "0") else None
	source = str(payload.get("source") or "app")
	client_return_path = payload.get("client_return_path")
	data = checkout_support_plan(
		db,
		user_id=ctx.get_user_id(),
		plan_id=plan_id,
		gateway_id=gateway_id_int,
		client_return_path=client_return_path,
		source=source,
	)
	return success_response(data, request, "درخواست خرید ثبت شد")


@router.post("/billing/invoices/{invoice_id}/retry-payment")
def retry_payment_endpoint(
	invoice_id: int,
	request: Request,
	payload: Optional[Dict[str, Any]] = Body(None),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	assert_end_user_support_tickets_allowed(db)
	payload = payload or {}
	gateway_id = payload.get("gateway_id")
	gateway_id_int = int(gateway_id) if gateway_id not in (None, "", 0, "0") else None
	data = retry_invoice_payment(
		db,
		user_id=ctx.get_user_id(),
		invoice_id=invoice_id,
		gateway_id=gateway_id_int,
		source=str(payload.get("source") or "app"),
	)
	return success_response(data, request, "درخواست پرداخت مجدد ایجاد شد")
