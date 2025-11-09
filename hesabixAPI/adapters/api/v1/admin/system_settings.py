from __future__ import annotations

from typing import Dict, Any

from fastapi import APIRouter, Depends, Body, Request
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response
from app.services.system_settings_service import get_wallet_settings, set_wallet_base_currency_code


router = APIRouter(prefix="/admin/system-settings", tags=["admin-system-settings"])


@router.get(
	"/wallet",
	summary="دریافت تنظیمات کیف‌پول (ارز پایه)",
	description="خواندن ارز پایه کیف‌پول. اگر تنظیم نشده باشد IRR بازگردانده می‌شود.",
)
def get_wallet_settings_endpoint(
	request: Request,
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		from app.core.responses import ApiError
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	data = get_wallet_settings(db)
	return success_response(data, request)


@router.put(
	"/wallet",
	summary="تنظیم ارز پایه کیف‌پول",
	description="تنظیم کد ارز پایه کیف‌پول (مثلاً IRR). تنها برای مدیر سیستم.",
)
def set_wallet_settings_endpoint(
	request: Request,
	payload: Dict[str, Any] = Body(...),
	db: Session = Depends(get_db),
	ctx: AuthContext = Depends(get_current_user),
) -> dict:
	if not ctx.has_any_permission("system_settings", "superadmin"):
		from app.core.responses import ApiError
		raise ApiError("FORBIDDEN", "Missing permission: system_settings", http_status=403)
	code = str(payload.get("wallet_base_currency_code") or "").strip().upper()
	data = set_wallet_base_currency_code(db, code)
	return success_response(data, request, message="WALLET_BASE_CURRENCY_UPDATED")


