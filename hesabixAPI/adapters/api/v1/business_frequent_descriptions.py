from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Body, Depends, Query, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.permissions import require_business_access_dep
from app.core.responses import ApiError, success_response
from app.services import business_frequent_description_service as svc

router = APIRouter(prefix="/businesses/{business_id}/frequent-descriptions", tags=["شرح پرتکرار"])


def _map_validation(err: ValueError) -> None:
	code = err.args[0] if err.args else "VALIDATION_ERROR"
	if code == "TEXT_TOO_LONG":
		raise ApiError("TEXT_TOO_LONG", "حداکثر طول شرح ۲۰۰۰ کاراکتر است.", http_status=400)
	if code == "TEXT_EMPTY":
		raise ApiError("TEXT_EMPTY", "متن شرح نمی‌تواند خالی باشد.", http_status=400)
	if code == "LIMIT_REACHED":
		raise ApiError("LIMIT_REACHED", "حداکثر ۵۰۰ شرح پرتکرار برای هر بخش (اسکوپ) مجاز است.", http_status=400)
	raise ApiError("VALIDATION_ERROR", str(err), http_status=400)


@router.get(
	"",
	summary="لیست شرح‌های پرتکرار کسب‌وکار",
)
def list_frequent_descriptions(
	request: Request,
	business_id: int,
	scope: str = Query("general", description="بخش تفکیک‌شدهٔ لیست (مثلاً receipt_payment، expense_income)"),
	_: None = Depends(require_business_access_dep),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	rows = svc.list_for_business(db, business_id, scope=scope)
	return success_response({"items": [svc.to_dict(r) for r in rows]}, request)


@router.post(
	"",
	summary="افزودن شرح پرتکرار",
)
def create_frequent_description(
	request: Request,
	business_id: int,
	payload: dict[str, Any] = Body(...),
	_: None = Depends(require_business_access_dep),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	text = payload.get("text")
	if not isinstance(text, str):
		raise ApiError("INVALID_PAYLOAD", "فیلد text الزامی است.", http_status=400)
	scope = payload.get("scope", "general")
	if scope is not None and not isinstance(scope, str):
		raise ApiError("INVALID_PAYLOAD", "فیلد scope باید رشته باشد.", http_status=400)
	sort_order = payload.get("sort_order")
	so = int(sort_order) if sort_order is not None and str(sort_order).strip() != "" else None
	try:
		row = svc.create_row(db, business_id, text, sort_order=so, scope=scope if isinstance(scope, str) else None)
	except ValueError as e:
		_map_validation(e)
	db.commit()
	return success_response(svc.to_dict(row), request, message="CREATED")


@router.patch(
	"/{row_id}",
	summary="ویرایش شرح پرتکرار",
)
def update_frequent_description(
	request: Request,
	business_id: int,
	row_id: int,
	payload: dict[str, Any] = Body(...),
	_: None = Depends(require_business_access_dep),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	text = payload.get("text") if "text" in payload else None
	if text is not None and not isinstance(text, str):
		raise ApiError("INVALID_PAYLOAD", "فیلد text باید رشته باشد.", http_status=400)
	sort_order = payload.get("sort_order") if "sort_order" in payload else None
	so = int(sort_order) if sort_order is not None and str(sort_order).strip() != "" else None
	try:
		row = svc.update_row(db, business_id, row_id, text=text, sort_order=so)
	except ValueError as e:
		_map_validation(e)
	if row is None:
		raise ApiError("NOT_FOUND", "رکورد یافت نشد.", http_status=404)
	db.commit()
	return success_response(svc.to_dict(row), request, message="UPDATED")


@router.delete(
	"/{row_id}",
	summary="حذف شرح پرتکرار",
)
def delete_frequent_description(
	request: Request,
	business_id: int,
	row_id: int,
	_: None = Depends(require_business_access_dep),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	ok = svc.delete_row(db, business_id, row_id)
	if not ok:
		raise ApiError("NOT_FOUND", "رکورد یافت نشد.", http_status=404)
	db.commit()
	return success_response({"deleted": True, "id": row_id}, request, message="DELETED")
