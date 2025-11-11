from __future__ import annotations

from typing import Any, Dict
from fastapi import APIRouter, Depends, Request, Body
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_access_dep
from app.core.responses import success_response
from app.services.marketplace_service import (
	list_plugins,
	purchase_plugin,
	list_orders,
	list_invoices,
)


router = APIRouter(prefix="/marketplace", tags=["marketplace"])


@router.get(
	"/plugins",
	summary="لیست افزونه‌ها و پلن‌ها",
)
def list_plugins_endpoint(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = list_plugins(db)
	return success_response(data, request)


@router.post(
	"/business/{business_id}/purchase",
	summary="خرید افزونه برای کسب‌وکار (پرداخت از کیف‌پول در صورت کفایت)",
)
def purchase_plugin_endpoint(
	request: Request,
	business_id: int,
	payload: Dict[str, Any] = Body(...),
	_: None = Depends(require_business_access_dep),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	result = purchase_plugin(db, business_id=int(business_id), user_id=ctx.get_user_id(), payload=payload)
	return success_response(result, request)


@router.get(
	"/business/{business_id}/orders",
	summary="لیست سفارش‌های بازار افزونه برای کسب‌وکار",
)
def list_orders_endpoint(
	request: Request,
	business_id: int,
	limit: int = 20,
	skip: int = 0,
	_: None = Depends(require_business_access_dep),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = list_orders(db, business_id=int(business_id), limit=limit, skip=skip)
	return success_response(data, request)


@router.get(
	"/business/{business_id}/invoices",
	summary="لیست صورتحساب‌های بازار افزونه برای کسب‌وکار",
)
def list_invoices_endpoint(
	request: Request,
	business_id: int,
	limit: int = 20,
	skip: int = 0,
	_: None = Depends(require_business_access_dep),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	data = list_invoices(db, business_id=int(business_id), limit=limit, skip=skip)
	return success_response(data, request)


