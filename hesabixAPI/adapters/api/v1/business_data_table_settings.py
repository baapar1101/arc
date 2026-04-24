from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy.orm import Session

from adapters.api.v1.schemas import SuccessResponse
from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.permissions import require_business_access
from app.core.responses import success_response
from app.services.data_table_user_settings_service import (
	delete_column_settings,
	get_column_settings,
	save_column_settings,
	validate_table_id,
)

router = APIRouter(prefix="/business", tags=["business-data-table"])


@router.get(
	"/{business_id}/data-tables/column-settings",
	summary="دریافت تنظیمات ستون جدول ذخیره‌شده",
	response_model=SuccessResponse,
)
@require_business_access("business_id")
def get_data_table_column_settings(
	request: Request,
	business_id: int,
	table_id: str = Query(..., min_length=1, max_length=255),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
) -> dict:
	try:
		validate_table_id(table_id)
	except ValueError:
		raise HTTPException(status_code=400, detail="INVALID_TABLE_ID")
	uid = ctx.get_user_id()
	if not uid:
		raise HTTPException(status_code=401, detail="UNAUTHORIZED")
	settings = get_column_settings(db, business_id=business_id, user_id=int(uid), table_id=table_id)
	return success_response({"settings": settings}, request)


@router.put(
	"/{business_id}/data-tables/column-settings",
	summary="ذخیره تنظیمات ستون جدول",
	response_model=SuccessResponse,
)
@require_business_access("business_id")
def put_data_table_column_settings(
	request: Request,
	business_id: int,
	payload: dict,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
) -> dict:
	uid = ctx.get_user_id()
	if not uid:
		raise HTTPException(status_code=401, detail="UNAUTHORIZED")
	raw_id = str(payload.get("table_id") or "")
	try:
		tid = validate_table_id(raw_id)
	except ValueError:
		raise HTTPException(status_code=400, detail="INVALID_TABLE_ID")
	settings = payload.get("settings")
	if not isinstance(settings, dict):
		raise HTTPException(status_code=400, detail="INVALID_SETTINGS")
	data = save_column_settings(
		db,
		business_id=business_id,
		user_id=int(uid),
		table_id=tid,
		settings=settings,
	)
	return success_response(data, request)


@router.delete(
	"/{business_id}/data-tables/column-settings",
	summary="حذف تنظیمات ستون جدول (بازگشت به پیش‌فرض)",
	response_model=SuccessResponse,
)
@require_business_access("business_id")
def delete_data_table_column_settings(
	request: Request,
	business_id: int,
	table_id: str = Query(..., min_length=1, max_length=255),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
) -> dict:
	try:
		validate_table_id(table_id)
	except ValueError:
		raise HTTPException(status_code=400, detail="INVALID_TABLE_ID")
	uid = ctx.get_user_id()
	if not uid:
		raise HTTPException(status_code=401, detail="UNAUTHORIZED")
	deleted = delete_column_settings(db, business_id=business_id, user_id=int(uid), table_id=table_id)
	return success_response({"deleted": deleted}, request)
