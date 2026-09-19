"""API کالای هزینه‌شده / کالای درآمدشده"""

from __future__ import annotations

from datetime import date, datetime
from typing import Any, Dict, Optional

from fastapi import APIRouter, Body, Depends, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.permissions import (
	has_business_permission_for_business,
	require_business_access,
	require_business_permission_dep,
)
from app.core.responses import ApiError, format_datetime_fields, success_response
from app.services.goods_expense_income_service import (
	allocate_account,
	cancel_document,
	create_document,
	create_from_stock_count,
	delete_document,
	get_document,
	get_workflow_settings,
	list_documents,
	post_document,
	submit_to_accounting,
	update_document,
	_get_business,
)


router = APIRouter(tags=["goods-expense-income"])


def _can(ctx: AuthContext, db: Session, business_id: int, action: str) -> bool:
	return has_business_permission_for_business(
		ctx, db, business_id, "goods_expense_income", action
	)


def _parse_date(value: Any) -> date:
	if isinstance(value, date) and not isinstance(value, datetime):
		return value
	if isinstance(value, datetime):
		return value.date()
	try:
		return datetime.fromisoformat(str(value)).date()
	except Exception as exc:
		raise ApiError("INVALID_DATE", "فرمت تاریخ نامعتبر است", http_status=400) from exc


@router.get(
	"/businesses/{business_id}/goods-expense-income/settings",
	summary="تنظیمات گردش‌کار کالای هزینه/درآمد",
)
@require_business_access("business_id")
async def get_settings_endpoint(
	request: Request,
	business_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_dep("goods_expense_income", "view")),
):
	biz = _get_business(db, business_id)
	return success_response(
		data=get_workflow_settings(biz),
		request=request,
		message="GEI_SETTINGS_FETCHED",
	)


@router.post(
	"/businesses/{business_id}/goods-expense-income",
	summary="لیست اسناد کالای هزینه/درآمد",
)
@require_business_access("business_id")
async def list_endpoint(
	request: Request,
	business_id: int,
	body: Dict[str, Any] = Body(default={}),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_dep("goods_expense_income", "view")),
):
	result = list_documents(db, business_id, body or {})
	return success_response(
		data=format_datetime_fields(result, request),
		request=request,
		message="GEI_LIST_FETCHED",
	)


@router.get(
	"/businesses/{business_id}/goods-expense-income/{document_id}",
	summary="جزئیات سند",
)
@require_business_access("business_id")
async def get_endpoint(
	request: Request,
	business_id: int,
	document_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_dep("goods_expense_income", "view")),
):
	result = get_document(db, business_id, document_id)
	return success_response(
		data=format_datetime_fields(result, request),
		request=request,
		message="GEI_FETCHED",
	)


@router.post(
	"/businesses/{business_id}/goods-expense-income/create",
	summary="ایجاد سند کالای هزینه/درآمد",
)
@require_business_access("business_id")
async def create_endpoint(
	request: Request,
	business_id: int,
	body: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_dep("goods_expense_income", "add")),
):
	user_id = ctx.get_user_id()
	result = create_document(
		db,
		business_id,
		user_id,
		body,
		user_can_allocate=_can(ctx, db, business_id, "allocate"),
		user_can_post=_can(ctx, db, business_id, "post"),
		user_can_change_unit_cost=_can(ctx, db, business_id, "change_unit_cost"),
	)
	return success_response(
		data=format_datetime_fields(result, request),
		request=request,
		message="GEI_CREATED",
	)


@router.put(
	"/businesses/{business_id}/goods-expense-income/{document_id}",
	summary="ویرایش سند غیرقطعی",
)
@require_business_access("business_id")
async def update_endpoint(
	request: Request,
	business_id: int,
	document_id: int,
	body: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_dep("goods_expense_income", "edit")),
):
	user_id = ctx.get_user_id()
	# اگر فقط add دارد و allocate ندارد، ویرایش عملیاتی محسوب می‌شود
	is_ops_edit = not _can(ctx, db, business_id, "allocate")
	result = update_document(
		db,
		business_id,
		user_id,
		document_id,
		body,
		user_can_allocate=_can(ctx, db, business_id, "allocate"),
		user_can_change_unit_cost=_can(ctx, db, business_id, "change_unit_cost"),
		is_ops_edit=is_ops_edit,
	)
	return success_response(
		data=format_datetime_fields(result, request),
		request=request,
		message="GEI_UPDATED",
	)


@router.post(
	"/businesses/{business_id}/goods-expense-income/{document_id}/submit",
	summary="ارسال به حسابداری (گردش‌کار دو مرحله‌ای)",
)
@require_business_access("business_id")
async def submit_endpoint(
	request: Request,
	business_id: int,
	document_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_dep("goods_expense_income", "submit")),
):
	result = submit_to_accounting(db, business_id, ctx.get_user_id(), document_id)
	return success_response(
		data=format_datetime_fields(result, request),
		request=request,
		message="GEI_SUBMITTED",
	)


@router.post(
	"/businesses/{business_id}/goods-expense-income/{document_id}/allocate",
	summary="تخصیص/تأیید حساب معین",
)
@require_business_access("business_id")
async def allocate_endpoint(
	request: Request,
	business_id: int,
	document_id: int,
	body: Dict[str, Any] = Body(default={}),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_dep("goods_expense_income", "allocate")),
):
	result = allocate_account(db, business_id, ctx.get_user_id(), document_id, body or {})
	return success_response(
		data=format_datetime_fields(result, request),
		request=request,
		message="GEI_ALLOCATED",
	)


@router.post(
	"/businesses/{business_id}/goods-expense-income/{document_id}/post",
	summary="قطعی‌سازی (حواله انبار + سند حسابداری)",
)
@require_business_access("business_id")
async def post_endpoint(
	request: Request,
	business_id: int,
	document_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_dep("goods_expense_income", "post")),
):
	result = post_document(db, business_id, ctx.get_user_id(), document_id)
	return success_response(
		data=format_datetime_fields(result, request),
		request=request,
		message="GEI_POSTED",
	)


@router.post(
	"/businesses/{business_id}/goods-expense-income/{document_id}/cancel",
	summary="ابطال سند قطعی",
)
@require_business_access("business_id")
async def cancel_endpoint(
	request: Request,
	business_id: int,
	document_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_dep("goods_expense_income", "cancel")),
):
	result = cancel_document(db, business_id, ctx.get_user_id(), document_id)
	return success_response(
		data=format_datetime_fields(result, request),
		request=request,
		message="GEI_CANCELLED",
	)


@router.delete(
	"/businesses/{business_id}/goods-expense-income/{document_id}",
	summary="حذف سند غیرقطعی",
)
@require_business_access("business_id")
async def delete_endpoint(
	request: Request,
	business_id: int,
	document_id: int,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_dep("goods_expense_income", "delete")),
):
	result = delete_document(db, business_id, document_id)
	return success_response(
		data=format_datetime_fields(result, request),
		request=request,
		message="GEI_DELETED",
	)


@router.post(
	"/businesses/{business_id}/goods-expense-income/from-stock-count",
	summary="ایجاد اسناد از اختلافات انبارگردانی",
)
@require_business_access("business_id")
async def from_stock_count_endpoint(
	request: Request,
	business_id: int,
	body: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
	_: None = Depends(require_business_permission_dep("goods_expense_income", "add")),
):
	items = body.get("items") or []
	if not items:
		raise ApiError("ITEMS_REQUIRED", "لیست اقلام الزامی است", http_status=400)
	stock_count_code = str(body.get("stock_count_code") or "").strip() or "SC"
	stock_count_date = _parse_date(body.get("stock_count_date") or date.today().isoformat())
	result = create_from_stock_count(
		db,
		business_id,
		ctx.get_user_id(),
		stock_count_code=stock_count_code,
		stock_count_date=stock_count_date,
		items=items,
		notes=body.get("notes"),
		user_can_allocate=_can(ctx, db, business_id, "allocate"),
		user_can_post=_can(ctx, db, business_id, "post"),
	)
	return success_response(
		data=format_datetime_fields(result, request),
		request=request,
		message="GEI_FROM_STOCK_COUNT_CREATED",
	)
