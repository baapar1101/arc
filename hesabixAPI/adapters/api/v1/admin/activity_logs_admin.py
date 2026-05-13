"""
Admin endpoints برای مشاهده لاگ فعالیت‌ها به‌صورت سراسری (همهٔ کسب‌وکارها).

این ماژول مخصوص صفحهٔ /user/profile/system-settings/business-activity-logs است
و دسترسی آن به سوپرادمین یا دارندگان مجوز اپلیکیشنی `system_settings` محدود شده است.

نکات طراحی:
- صفحه‌بندی کاملاً سمت سرور انجام می‌شود (skip/take) تا حجم زیاد لاگ‌ها روی فرانت بار نگذارد.
- شمارش total فقط روی همان فیلترهای فعال انجام می‌شود.
- داده‌های حساس قبل از ارسال به کلاینت ماسک می‌شوند.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Body, Depends, Path, Query, Request
from sqlalchemy.orm import Session

from adapters.db.repositories.activity_log_repo import ActivityLogRepository
from adapters.db.session import get_db
from app.core.auth_dependency import AuthContext, get_current_user
from app.core.permissions import require_app_permission
from app.core.responses import ApiError, format_datetime_fields, success_response


router = APIRouter(prefix="/admin/activity-logs", tags=["admin-activity-logs"])


# فیلدهای حساسی که در before_data/after_data/extra_info ماسک می‌شوند تا
# اطلاعات سیستمی به صفحهٔ ادمین لیک نشوند.
_SENSITIVE_KEYS = {
	"password",
	"password_hash",
	"new_password",
	"current_password",
	"old_password",
	"token",
	"access_token",
	"refresh_token",
	"api_key",
	"secret",
	"client_secret",
	"otp",
	"otp_code",
	"verification_code",
	"signature",
}


def _mask_sensitive(value: Any) -> Any:
	"""ماسک بازگشتی فیلدهای حساس درون JSON ها."""
	if isinstance(value, dict):
		out: Dict[str, Any] = {}
		for k, v in value.items():
			if isinstance(k, str) and k.lower() in _SENSITIVE_KEYS:
				out[k] = "***"
			else:
				out[k] = _mask_sensitive(v)
		return out
	if isinstance(value, list):
		return [_mask_sensitive(item) for item in value]
	return value


def _full_name(user) -> Optional[str]:
	if user is None:
		return None
	first = (user.first_name or "").strip()
	last = (user.last_name or "").strip()
	full = f"{first} {last}".strip()
	return full or None


def _serialize_log(log) -> Dict[str, Any]:
	"""تبدیل ActivityLog به dict پاسخ، با ماسک کردن داده‌های حساس."""
	business = getattr(log, "business", None)
	user = getattr(log, "user", None)
	user_full = _full_name(user)

	return {
		"id": log.id,
		"created_at": log.created_at.isoformat() if log.created_at else None,
		"business_id": log.business_id,
		"business_name": business.name if business else None,
		"user_id": log.user_id,
		"user_name": user_full,
		"user_email": user.email if user else None,
		"user_mobile": user.mobile if user else None,
		"category": log.category,
		"action": log.action,
		"entity_type": log.entity_type,
		"entity_id": log.entity_id,
		"description": log.description,
		"before_data": _mask_sensitive(log.before_data),
		"after_data": _mask_sensitive(log.after_data),
		"extra_info": _mask_sensitive(log.extra_info),
	}


def _parse_iso_datetime(value: Any) -> Optional[datetime]:
	"""parse امن تاریخ ISO. همان روال موجود در activity_logs.py."""
	if not value:
		return None
	if isinstance(value, datetime):
		return value
	try:
		return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
	except Exception:
		return None


def _ensure_admin_or_settings(ctx: AuthContext) -> None:
	"""دسترسی: سوپرادمین یا دارندهٔ مجوز system_settings."""
	if not (ctx.is_superadmin() or ctx.has_app_permission("system_settings")):
		raise ApiError(
			"FORBIDDEN",
			"system_settings permission required",
			http_status=403,
		)


# =====================================================================
# Endpoint اصلی DataTable
# =====================================================================
@router.post(
	"/table",
	summary="لاگ فعالیت کسب‌وکارها (DataTable، صفحه‌بندی سمت سرور)",
	description="ورودی متعارف DataTableWidget شامل skip/take/sort_by/sort_desc/search/filters و فیلترهای additionalParams.",
)
@require_app_permission("system_settings")
def list_business_activity_logs_admin(
	request: Request,
	body: Dict[str, Any] = Body(default_factory=dict),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
) -> dict:
	# DataTableWidget مقادیر skip/take می‌فرستد
	skip = int(body.get("skip", 0) or 0)
	take = int(body.get("take", 50) or 50)
	# سقف امن برای محافظت از سرور
	if take <= 0:
		take = 50
	if take > 200:
		take = 200
	if skip < 0:
		skip = 0

	sort_by = body.get("sort_by") or "created_at"
	sort_desc = bool(body.get("sort_desc", True))

	# فیلترهای additionalParams که از فرانت می‌آیند
	business_id = body.get("business_id")
	user_id = body.get("user_id")
	category = body.get("category") or None
	action = body.get("action") or None
	entity_type = body.get("entity_type") or None
	start_date = _parse_iso_datetime(body.get("start_date"))
	end_date = _parse_iso_datetime(body.get("end_date"))

	# جستجوی متنی DataTableWidget روی description
	search = body.get("search")
	if isinstance(search, str):
		search = search.strip() or None

	# DataTableWidget می‌تواند filters را هم بفرستد (column filters). آنها را هم اعمال کنیم.
	for filter_item in body.get("filters") or []:
		if not isinstance(filter_item, dict):
			continue
		prop = filter_item.get("property")
		value = filter_item.get("value")
		if value is None or value == "":
			continue
		if prop == "category":
			category = str(value)
		elif prop == "action":
			action = str(value)
		elif prop == "entity_type":
			entity_type = str(value)
		elif prop == "business_id":
			business_id = value
		elif prop == "user_id":
			user_id = value

	# normalize شناسه‌های عددی
	try:
		business_id_int = int(business_id) if business_id not in (None, "") else None
	except (TypeError, ValueError):
		business_id_int = None
	try:
		user_id_int = int(user_id) if user_id not in (None, "") else None
	except (TypeError, ValueError):
		user_id_int = None

	repo = ActivityLogRepository(db)

	total = repo.count_admin(
		business_id=business_id_int,
		user_id=user_id_int,
		category=category,
		action=action,
		entity_type=entity_type,
		start_date=start_date,
		end_date=end_date,
		search=search,
	)

	logs = repo.get_admin(
		business_id=business_id_int,
		user_id=user_id_int,
		category=category,
		action=action,
		entity_type=entity_type,
		start_date=start_date,
		end_date=end_date,
		search=search,
		sort_by=sort_by,
		sort_desc=sort_desc,
		limit=take,
		offset=skip,
	)

	items = [format_datetime_fields(_serialize_log(log), request) for log in logs]

	page = (skip // take) + 1 if take > 0 else 1
	total_pages = (total + take - 1) // take if (take > 0 and total > 0) else 0

	return success_response(
		data={
			"items": items,
			"total": total,
			"page": page,
			"limit": take,
			"per_page": take,
			"total_pages": total_pages,
		},
		request=request,
	)


# =====================================================================
# Autocomplete: businesses
# =====================================================================
@router.get(
	"/filters/businesses",
	summary="جستجوی کسب‌وکارها برای فیلتر autocomplete",
)
@require_app_permission("system_settings")
def search_businesses_for_filter(
	request: Request,
	q: Optional[str] = Query(None, description="متن جستجو در نام کسب‌وکار"),
	limit: int = Query(20, ge=1, le=50),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
) -> dict:
	repo = ActivityLogRepository(db)
	businesses = repo.search_businesses(query_text=q, limit=limit)
	items = [
		{
			"id": b.id,
			"name": b.name,
			"business_type": b.business_type.value if b.business_type else None,
		}
		for b in businesses
	]
	return success_response(data={"items": items}, request=request)


# =====================================================================
# Autocomplete: users (in a business or globally)
# =====================================================================
@router.get(
	"/filters/users",
	summary="جستجوی کاربران برای فیلتر autocomplete",
	description="اگر business_id داده شود، فقط اعضای آن کسب‌وکار بازگردانده می‌شوند؛ در غیر این صورت همهٔ کاربران فعال.",
)
@require_app_permission("system_settings")
def search_users_for_filter(
	request: Request,
	q: Optional[str] = Query(None, description="نام/ایمیل/موبایل"),
	business_id: Optional[int] = Query(None, ge=1),
	limit: int = Query(20, ge=1, le=50),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
) -> dict:
	repo = ActivityLogRepository(db)
	rows = repo.search_users(query_text=q, business_id=business_id, limit=limit)
	items: List[Dict[str, Any]] = []
	for user, _ in rows:
		items.append(
			{
				"id": user.id,
				"full_name": _full_name(user) or (user.email or user.mobile or f"#{user.id}"),
				"email": user.email,
				"mobile": user.mobile,
			}
		)
	return success_response(data={"items": items}, request=request)


# =====================================================================
# لیست گزینه‌های ثابت برای dropdownها
# =====================================================================
@router.get(
	"/filters/options",
	summary="لیست گزینه‌های فیلتر (دسته‌ها، اکشن‌ها، نوع موجودیت)",
)
@require_app_permission("system_settings")
def get_filter_options(
	request: Request,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
) -> dict:
	# همان مقادیر معتبر در ActivityLog (مطابق توضیحات مدل)
	categories = [
		"accounting", "warehouse", "product", "person", "business", "user",
		"settings", "invoice", "document", "workflow", "marketplace",
		"storage", "payment", "wallet", "warranty", "ai", "support", "other",
	]
	entity_types = [
		"invoice", "document", "warehouse_document", "product", "person",
		"account", "business", "user", "fiscal_year",
	]
	# actionها از مقادیر distinct موجود گرفته می‌شوند تا با گذر زمان به‌روز بمانند.
	repo = ActivityLogRepository(db)
	actions = repo.get_distinct_actions()
	# fallback اگر دیتابیس خالی است
	if not actions:
		actions = [
			"create", "update", "delete", "post", "cancel",
			"approve", "reject", "export", "import",
			"login", "logout", "password_change",
		]

	return success_response(
		data={
			"categories": categories,
			"entity_types": entity_types,
			"actions": actions,
		},
		request=request,
	)


# =====================================================================
# Detail (در انتها قرار داده شده تا روی مسیرهای /filters/* اولویت نگیرد)
# =====================================================================
@router.get(
	"/{log_id}",
	summary="جزئیات یک لاگ فعالیت (مخصوص ادمین)",
)
@require_app_permission("system_settings")
def get_activity_log_detail_admin(
	request: Request,
	log_id: int = Path(..., ge=1),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
) -> dict:
	from sqlalchemy.orm import joinedload as _jl

	from adapters.db.models.activity_log import ActivityLog as _AL

	log = (
		db.query(_AL)
		.options(_jl(_AL.user), _jl(_AL.business))
		.filter(_AL.id == log_id)
		.first()
	)
	if not log:
		raise ApiError("NOT_FOUND", "Activity log not found", http_status=404)

	data = format_datetime_fields(_serialize_log(log), request)
	return success_response(data=data, request=request)
