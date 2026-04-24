"""مدیریت ارزها (ادمین)."""
from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import ApiError, success_response
from app.services.currency_admin_service import (
	create_currency,
	delete_currency_if_allowed,
	get_currency_delete_blockers,
	list_all_currencies_admin,
	update_currency,
)

router = APIRouter(prefix="/admin/currencies", tags=["مدیریت ارزها"])


def _require_system(ctx: AuthContext) -> None:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)


class CurrencyCreateBody(BaseModel):
	name: str = Field(..., min_length=1, max_length=100)
	title: str = Field(..., min_length=1, max_length=100)
	symbol: str = Field(..., min_length=1, max_length=16)
	code: str = Field(..., min_length=2, max_length=16)
	decimal_places: int = Field(2, ge=0, le=8)
	round_monetary_amounts: bool = True


class CurrencyUpdateBody(BaseModel):
	name: Optional[str] = Field(None, min_length=1, max_length=100)
	title: Optional[str] = Field(None, min_length=1, max_length=100)
	symbol: Optional[str] = Field(None, min_length=1, max_length=16)
	code: Optional[str] = Field(None, min_length=2, max_length=16)
	decimal_places: Optional[int] = Field(None, ge=0, le=8)
	round_monetary_amounts: Optional[bool] = None


@router.get(
	"",
	summary="فهرست کامل ارزها (ادمین)",
)
def admin_list_currencies(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_system(ctx)
	data = list_all_currencies_admin(db)
	return success_response(data, request)


@router.post(
	"",
	summary="ایجاد ارز",
)
def admin_create_currency(
	request: Request,
	payload: CurrencyCreateBody,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_system(ctx)
	c = create_currency(
		db,
		name=payload.name,
		title=payload.title,
		symbol=payload.symbol,
		code=payload.code,
		decimal_places=payload.decimal_places,
		round_monetary_amounts=payload.round_monetary_amounts,
	)
	from app.services.currency_admin_service import currency_to_dict

	return success_response(currency_to_dict(c), request, message="CURRENCY_CREATED")


@router.patch(
	"/{currency_id}",
	summary="ویرایش ارز",
)
def admin_update_currency(
	request: Request,
	currency_id: int,
	payload: CurrencyUpdateBody,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_system(ctx)
	c = update_currency(
		db,
		currency_id,
		name=payload.name,
		title=payload.title,
		symbol=payload.symbol,
		code=payload.code,
		decimal_places=payload.decimal_places,
		round_monetary_amounts=payload.round_monetary_amounts,
	)
	from app.services.currency_admin_service import currency_to_dict

	return success_response(currency_to_dict(c), request, message="CURRENCY_UPDATED")


@router.delete(
	"/{currency_id}",
	summary="حذف ارز در صورت نبود وابستگی",
)
def admin_delete_currency(
	request: Request,
	currency_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_system(ctx)
	delete_currency_if_allowed(db, currency_id)
	return success_response({"deleted": True, "id": currency_id}, request, message="CURRENCY_DELETED")


@router.get(
	"/{currency_id}/delete-check",
	summary="بررسی امکان حذف ارز (لیست مانع‌ها)",
)
def admin_currency_delete_check(
	request: Request,
	currency_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_system(ctx)
	blockers = get_currency_delete_blockers(db, currency_id)
	return success_response(
		{"can_delete": len(blockers) == 0, "blockers": blockers},
		request,
	)

