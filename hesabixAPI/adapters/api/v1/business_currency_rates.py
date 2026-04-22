from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, Optional

from fastapi import APIRouter, Depends, Query, Request, Body
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_business_permission_dep
from app.core.responses import success_response, format_datetime_fields, ApiError
from app.services.business_currency_rate_service import (
	list_business_currency_rates,
	create_business_currency_rate,
	update_business_currency_rate,
	delete_business_currency_rate,
	resolve_rate_to_base,
)

router = APIRouter(tags=["currency_revaluation", "حسابداری"], prefix="")


@router.get(
	"/businesses/{business_id}/currency-rates",
	summary="لیست نرخ‌های تسعیر (تاریخچه)",
	description="نرخ‌های ثبت‌شده نسبت به ارز اصلی؛ چند نرخ در یک روز با زمان مؤثر متفاوت مجاز است",
)
def list_currency_rates(
	request: Request,
	business_id: int,
	skip: int = Query(0, ge=0),
	take: int = Query(50, ge=1, le=200),
	currency_id: Optional[int] = None,
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_dep("currency_revaluation", "view")),
) -> dict:
	items, total = list_business_currency_rates(
		db, business_id, currency_id=currency_id, skip=skip, take=take
	)
	return success_response(
		data=format_datetime_fields(
			{"items": items, "total": total, "skip": skip, "take": take},
			request,
		),
		request=request,
		message="CURRENCY_RATES_LIST",
	)


@router.get(
	"/businesses/{business_id}/currency-rates/resolve",
	summary="تعیین نرخ در لحظه (برای تسعیر اسناد)",
	description="بازگرداندن نرخ تبدیل ۱ واحد ارز به ارز پایه در زمان as_of (آخرین نرخ با effective_at <= as_of)",
)
def resolve_currency_rate(
	request: Request,
	business_id: int,
	currency_id: int = Query(..., description="شناسه ارز غیرپایه"),
	as_of: str = Query(
		...,
		description="ISO8601، مثال: 2024-12-20T15:30:00+00:00",
	),
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_dep("currency_revaluation", "view")),
) -> dict:
	s = as_of.replace("Z", "+00:00")
	try:
		dt = datetime.fromisoformat(s)
	except Exception:
		raise ApiError("AS_OF_INVALID", "پارامتر as_of نامعتبر است", http_status=400)
	out = resolve_rate_to_base(db, business_id, currency_id, dt)
	# rate may be Decimal
	data = {**out, "rate": str(out["rate"])}
	return success_response(data=format_datetime_fields(data, request), request=request, message="CURRENCY_RATE_RESOLVED")


@router.post(
	"/businesses/{business_id}/currency-rates",
	summary="ثبت نرخ تسعیر جدید",
)
def create_currency_rate(
	request: Request,
	business_id: int,
	body: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_dep("currency_revaluation", "add")),
) -> dict:
	row = create_business_currency_rate(db, business_id, int(ctx.get_user_id()), body)
	out = {**row, "rate": str(row["rate"])}
	return success_response(
		data=format_datetime_fields(out, request),
		request=request,
		message="CURRENCY_RATE_CREATED",
	)


@router.put(
	"/businesses/{business_id}/currency-rates/{rate_id}",
	summary="ویرایش نرخ",
)
def update_currency_rate(
	request: Request,
	business_id: int,
	rate_id: int,
	body: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_dep("currency_revaluation", "edit")),
) -> dict:
	row = update_business_currency_rate(db, business_id, int(ctx.get_user_id()), rate_id, body)
	out = {**row, "rate": str(row["rate"])}
	return success_response(
		data=format_datetime_fields(out, request),
		request=request,
		message="CURRENCY_RATE_UPDATED",
	)


@router.delete(
	"/businesses/{business_id}/currency-rates/{rate_id}",
	summary="حذف نرخ",
)
def delete_currency_rate(
	request: Request,
	business_id: int,
	rate_id: int,
	db: Session = Depends(get_db),
	_ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_dep("currency_revaluation", "delete")),
) -> dict:
	delete_business_currency_rate(db, business_id, rate_id)
	return success_response(data={"id": rate_id}, request=request, message="CURRENCY_RATE_DELETED")
