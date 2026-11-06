"""
API endpoints برای استفاده از سرویس‌های استعلامات زحل (کاربران)
"""

from typing import Dict, Any, Optional
import structlog

from fastapi import APIRouter, Depends, Request, Body, Path, Query
from sqlalchemy.orm import Session
from pydantic import BaseModel

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError
from app.core.permissions import require_business_access
from app.services.zohal_service import (
	list_zohal_services,
	execute_zohal_inquiry,
	list_zohal_service_logs,
	get_zohal_service_log,
)
from app.services.wallet_service import get_wallet_overview
from app.services.system_settings_service import get_zohal_settings

logger = structlog.get_logger()

router = APIRouter(prefix="/businesses/{business_id}/zohal", tags=["یکپارچه‌سازی", "مالیات"])


# ==================== لیست سرویس‌ها ====================

@router.get(
	"/services",
	summary="لیست سرویس‌های استعلامات زحل",
	description=(
		"سرویس‌های فعال زحل به‌همراه schema درخواست/پاسخ، قیمت پایه، موجودی کیف‌پول کسب‌وکار و هشدار موجودی کم. "
		"قبل از POST /inquiry/{service_code} فیلدهای request_schema همان سرویس را بخوانید. "
		"ابزار MCP متناظر: list_zohal_services."
	),
)
@require_business_access("business_id")
def list_zohal_services_for_business(
	request: Request,
	business_id: int = Path(..., description="شناسه کسب‌وکار"),
	category: Optional[str] = Query(None, description="فیلتر بر اساس دسته‌بندی"),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	"""لیست سرویس‌های فعال برای کاربر"""
	services = list_zohal_services(db, category=category, only_active=True)
	
	# دریافت موجودی کیف پول
	wallet = get_wallet_overview(db, business_id)
	wallet_balance = wallet.get("available_balance", 0)
	
	# بررسی موجودی کم
	zohal_settings = get_zohal_settings(db)
	low_balance_threshold = zohal_settings.get("low_balance_threshold", 10000)
	low_balance_warning = wallet_balance < low_balance_threshold
	
	return success_response({
		"services": services,
		"wallet_balance": wallet_balance,
		"wallet_currency": wallet.get("base_currency_code"),
		"low_balance_warning": low_balance_warning,
		"low_balance_threshold": low_balance_threshold,
	}, request)


# ==================== اجرای استعلام ====================

class InquiryRequest(BaseModel):
	"""درخواست استعلام - فیلدها بسته به سرویس متفاوت است"""
	pass


@router.post(
	"/inquiry/{service_code}",
	summary="اجرای استعلام زحل",
	description=(
		"اجرای استعلام پولی زحل: بررسی فعال بودن سرویس، کسر از کیف‌پول، فراخوانی API، ثبت سند حسابداری و لاگ. "
		"بدنه JSON باید مطابق request_schema سرویس باشد. ابزار MCP: execute_zohal_inquiry (نیاز به تأیید)."
	),
)
@require_business_access("business_id")
def execute_inquiry(
	request: Request,
	business_id: int = Path(..., description="شناسه کسب‌وکار"),
	service_code: str = Path(..., description="کد سرویس"),
	request_data: Dict[str, Any] = Body(..., description="داده‌های درخواست"),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	"""اجرای یک استعلام زحل"""
	result = execute_zohal_inquiry(
		db=db,
		business_id=business_id,
		user_id=ctx.get_user_id(),
		service_code=service_code,
		request_data=request_data,
	)
	return success_response(result, request, message="INQUIRY_COMPLETED" if result.get("success") else "INQUIRY_FAILED")


# ==================== تاریخچه ====================

@router.get(
	"/logs",
	summary="تاریخچه استفاده از سرویس‌های زحل",
	description=(
		"لاگ استعلام‌های همین کسب‌وکار با فیلتر service_id و بازه تاریخ ISO. صفحه‌بندی limit/skip حداکثر ۱۰۰. "
		"ابزار MCP: list_zohal_inquiry_logs."
	),
)
@require_business_access("business_id")
def list_inquiry_logs(
	request: Request,
	business_id: int = Path(..., description="شناسه کسب‌وکار"),
	service_id: Optional[int] = Query(None, description="فیلتر بر اساس سرویس"),
	start_date: Optional[str] = Query(None, description="تاریخ شروع (ISO format)"),
	end_date: Optional[str] = Query(None, description="تاریخ پایان (ISO format)"),
	limit: int = Query(50, ge=1, le=100, description="تعداد نتایج"),
	skip: int = Query(0, ge=0, description="تعداد نتایج برای رد شدن"),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	"""لیست لاگ‌های استفاده از سرویس‌های زحل"""
	logs = list_zohal_service_logs(
		db,
		business_id=business_id,
		service_id=service_id,
		start_date=start_date,
		end_date=end_date,
		limit=limit,
		skip=skip,
	)
	return success_response(logs, request)


@router.get(
	"/logs/{log_id}",
	summary="جزئیات یک لاگ استعلام زحل",
	description="جزئیات یک لاگ متعلق به همین کسب‌وکار شامل ورودی/خروجی و مبلغ کسرشده. ابزار MCP: get_zohal_inquiry_log.",
)
@require_business_access("business_id")
def get_inquiry_log(
	request: Request,
	business_id: int = Path(..., description="شناسه کسب‌وکار"),
	log_id: int = Path(..., description="شناسه لاگ"),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	"""دریافت جزئیات یک لاگ"""
	log = get_zohal_service_log(db, log_id, business_id)
	return success_response(log, request)

