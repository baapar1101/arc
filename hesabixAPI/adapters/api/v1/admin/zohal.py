"""
API endpoints برای مدیریت سرویس‌های زحل (مدیر سیستم)
"""
from __future__ import annotations

from typing import Dict, Any, Optional
from decimal import Decimal
import structlog

from fastapi import APIRouter, Depends, Request, Body, Path, Query
from sqlalchemy.orm import Session
from pydantic import BaseModel

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError
from app.services.zohal_service import (
	list_zohal_services,
	get_zohal_service,
	toggle_zohal_service,
	update_zohal_service_price,
	load_services_from_json,
)
from app.services.system_settings_service import get_zohal_settings, set_zohal_settings

logger = structlog.get_logger()

router = APIRouter(prefix="/admin/zohal", tags=["admin-zohal"])


def _require_admin(ctx: AuthContext) -> None:
	"""بررسی دسترسی مدیر سیستم"""
	if not ctx.has_any_permission("system_settings", "superadmin"):
		raise ApiError("FORBIDDEN", "دسترسی به این بخش ندارید", http_status=403)


# ==================== تنظیمات ====================

@router.get(
	"/settings",
	summary="دریافت تنظیمات سرویس زحل",
	description="خواندن تنظیمات API Key و پیکربندی سرویس زحل",
)
def get_zohal_settings_endpoint(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_admin(ctx)
	data = get_zohal_settings(db)
	return success_response(data, request)


class ZohalSettingsPayload(BaseModel):
	api_key: Optional[str] = None
	base_url: Optional[str] = None
	low_balance_threshold: Optional[float] = None


@router.put(
	"/settings",
	summary="تنظیم پیکربندی سرویس زحل",
	description="تنظیم API Key، آدرس پایه و آستانه موجودی کم برای سرویس زحل",
)
def set_zohal_settings_endpoint(
	request: Request,
	payload: ZohalSettingsPayload,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_admin(ctx)
	data = set_zohal_settings(
		db,
		api_key=payload.api_key,
		base_url=payload.base_url,
		low_balance_threshold=payload.low_balance_threshold,
	)
	return success_response(data, request, message="ZOHAL_SETTINGS_UPDATED")


# ==================== مدیریت سرویس‌ها ====================

@router.get(
	"/services",
	summary="لیست سرویس‌های زحل",
	description="دریافت لیست تمام سرویس‌های زحل با امکان فیلتر",
)
def list_zohal_services_endpoint(
	request: Request,
	category: Optional[str] = Query(None, description="فیلتر بر اساس دسته‌بندی"),
	only_active: Optional[bool] = Query(None, description="فقط سرویس‌های فعال"),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_admin(ctx)
	services = list_zohal_services(db, category=category, only_active=only_active)
	return success_response({"items": services, "total": len(services)}, request)


@router.get(
	"/services/{service_id}",
	summary="دریافت اطلاعات یک سرویس",
	description="دریافت جزئیات یک سرویس زحل",
)
def get_zohal_service_endpoint(
	request: Request,
	service_id: int = Path(..., description="شناسه سرویس"),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_admin(ctx)
	service = get_zohal_service(db, service_id)
	return success_response(service, request)


class ToggleServicePayload(BaseModel):
	is_active: bool


@router.put(
	"/services/{service_id}/toggle",
	summary="فعال/غیرفعال کردن سرویس",
	description="تغییر وضعیت فعال/غیرفعال یک سرویس",
)
def toggle_zohal_service_endpoint(
	request: Request,
	service_id: int = Path(..., description="شناسه سرویس"),
	payload: ToggleServicePayload = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_admin(ctx)
	service = toggle_zohal_service(db, service_id, payload.is_active)
	return success_response(service, request, message="SERVICE_STATUS_UPDATED")


class UpdatePricePayload(BaseModel):
	base_price: float
	currency_id: int


@router.put(
	"/services/{service_id}/price",
	summary="به‌روزرسانی قیمت سرویس",
	description="تغییر قیمت و ارز یک سرویس",
)
def update_zohal_service_price_endpoint(
	request: Request,
	service_id: int = Path(..., description="شناسه سرویس"),
	payload: UpdatePricePayload = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_admin(ctx)
	service = update_zohal_service_price(
		db,
		service_id,
		Decimal(str(payload.base_price)),
		payload.currency_id,
	)
	return success_response(service, request, message="SERVICE_PRICE_UPDATED")


class LoadServicesPayload(BaseModel):
	json_file_path: str
	default_currency_id: int


@router.post(
	"/services/load-from-json",
	summary="بارگذاری سرویس‌ها از فایل JSON",
	description="بارگذاری و به‌روزرسانی سرویس‌ها از فایل OpenAPI JSON",
)
def load_services_from_json_endpoint(
	request: Request,
	payload: LoadServicesPayload = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_admin(ctx)
	result = load_services_from_json(
		db,
		payload.json_file_path,
		payload.default_currency_id,
	)
	return success_response(result, request, message="SERVICES_LOADED")


# ==================== آمار و گزارش‌ها ====================

@router.get(
	"/statistics",
	summary="آمار استفاده از سرویس‌های زحل",
	description="دریافت آمار استفاده از سرویس‌های زحل",
)
def get_zohal_statistics_endpoint(
	request: Request,
	start_date: Optional[str] = Query(None, description="تاریخ شروع (ISO format)"),
	end_date: Optional[str] = Query(None, description="تاریخ پایان (ISO format)"),
	business_id: Optional[int] = Query(None, description="فیلتر بر اساس کسب‌وکار"),
	service_id: Optional[int] = Query(None, description="فیلتر بر اساس سرویس"),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	_require_admin(ctx)
	from app.services.zohal_service import get_zohal_statistics
	statistics = get_zohal_statistics(
		db,
		start_date=start_date,
		end_date=end_date,
		business_id=business_id,
		service_id=service_id,
	)
	return success_response(statistics, request)

