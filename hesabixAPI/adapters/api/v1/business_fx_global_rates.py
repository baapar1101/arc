from __future__ import annotations

from typing import Any, Dict

from fastapi import APIRouter, Body, Depends, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.permissions import require_business_permission_dep
from app.core.responses import format_datetime_fields, success_response
from app.services.fx_rate_provider_service import (
	apply_global_rates_to_business,
	list_business_relevant_global_rates,
)

router = APIRouter(tags=["currency_revaluation", "حسابداری"], prefix="")


@router.get(
	"/businesses/{business_id}/fx-global-rates/latest",
	summary="نرخ‌های اسنپ‌شات مرکزی مرتبط با ارزهای فرعی کسب‌وکار",
)
def business_fx_global_rates_latest(
	request: Request,
	business_id: int,
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_dep("currency_revaluation", "view")),
) -> dict:
	data = list_business_relevant_global_rates(db, business_id)
	return success_response(
		data=format_datetime_fields(data, request),
		request=request,
		message="BUSINESS_FX_GLOBAL_RATES",
	)


@router.post(
	"/businesses/{business_id}/currency-rates/apply-from-global",
	summary="ثبت سریع نرخ تسعیر از اسنپ‌شات مرکزی",
)
def business_apply_currency_rates_from_global(
	request: Request,
	business_id: int,
	body: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_dep("currency_revaluation", "add")),
) -> dict:
	out = apply_global_rates_to_business(db, business_id, int(ctx.get_user_id()), body)
	db.commit()
	return success_response(
		data=format_datetime_fields(out, request),
		request=request,
		message="CURRENCY_RATES_APPLIED_FROM_GLOBAL",
	)
