from fastapi import APIRouter, Depends, Request, Query, Body
from sqlalchemy.orm import Session
from typing import Optional
from datetime import datetime
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError
from app.core.permissions import require_business_access
from adapters.db.session import get_db
from adapters.db.repositories.activity_log_repo import ActivityLogRepository
from adapters.db.models.activity_log import ActivityLog
from app.core.cache import get_cache

router = APIRouter(prefix="/activity-logs", tags=["activity-logs"])


@router.post("/business/{business_id}/table")
@require_business_access("business_id")
def get_business_activity_logs_table(
	request: Request,
	business_id: int,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
	body: dict = Body(...)
) -> dict:
	"""دریافت لاگ‌های فعالیت یک کسب و کار برای DataTable (POST)"""
	# تبدیل skip/take به page/per_page
	skip = body.get("skip", 0)
	take = body.get("take", 50)
	page = (skip // take) + 1 if take > 0 else 1
	per_page = take
	
	# استخراج فیلترها از body
	category = body.get("category")
	entity_type = body.get("entity_type")
	start_date_str = body.get("start_date")
	end_date_str = body.get("end_date")
	
	start_date = None
	if start_date_str:
		try:
			start_date = datetime.fromisoformat(start_date_str.replace('Z', '+00:00'))
		except:
			pass
	
	end_date = None
	if end_date_str:
		try:
			end_date = datetime.fromisoformat(end_date_str.replace('Z', '+00:00'))
		except:
			pass
	
	# استخراج search و filters
	search = body.get("search")
	search_fields = body.get("search_fields", [])
	filters = body.get("filters", [])
	
	# اعمال فیلترهای اضافی از filters
	for filter_item in filters:
		if isinstance(filter_item, dict):
			prop = filter_item.get("property")
			value = filter_item.get("value")
			if prop == "category" and value:
				category = value
			elif prop == "entity_type" and value:
				entity_type = value
	
	repo = ActivityLogRepository(db)
	offset = (page - 1) * per_page
	
	logs = repo.get_by_business(
		business_id=business_id,
		category=category,
		entity_type=entity_type,
		start_date=start_date,
		end_date=end_date,
		limit=per_page,
		offset=offset
	)
	
	# شمارش کل
	total = repo.count_by_business(
		business_id=business_id,
		category=category,
		entity_type=entity_type,
		start_date=start_date,
		end_date=end_date
	)
	
	# تبدیل به دیکشنری
	logs_data = []
	for log in logs:
		logs_data.append({
			"id": log.id,
			"user_id": log.user_id,
			"user_name": f"{log.user.first_name or ''} {log.user.last_name or ''}".strip() if log.user else None,
			"category": log.category,
			"action": log.action,
			"entity_type": log.entity_type,
			"entity_id": log.entity_id,
			"description": log.description,
			"before_data": log.before_data,
			"after_data": log.after_data,
			"extra_info": log.extra_info,
			"created_at": log.created_at.isoformat()
		})
	
	# فیلتر بر اساس search اگر وجود داشته باشد
	if search and search_fields:
		search_lower = search.lower()
		logs_data = [
			log for log in logs_data
			if any(
				search_lower in str(log.get(field, "")).lower()
				for field in search_fields
			)
		]
		total = len(logs_data)  # در صورت جستجو، total را به‌روزرسانی می‌کنیم
	
	return success_response(
		data={
			"items": logs_data,
			"page": page,
			"limit": per_page,
			"per_page": per_page,  # برای سازگاری
			"total": total,
			"total_pages": (total + per_page - 1) // per_page if total > 0 else 0
		},
		request=request
	)


@router.get("/business/{business_id}")
@require_business_access("business_id")
def get_business_activity_logs(
	request: Request,
	business_id: int,
	category: Optional[str] = Query(None, description="دسته فعالیت"),
	entity_type: Optional[str] = Query(None, description="نوع موجودیت"),
	start_date: Optional[datetime] = Query(None, description="تاریخ شروع"),
	end_date: Optional[datetime] = Query(None, description="تاریخ پایان"),
	page: int = Query(1, ge=1, description="شماره صفحه"),
	per_page: int = Query(50, ge=1, le=200, description="تعداد در هر صفحه"),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db)
) -> dict:
	"""دریافت لاگ‌های فعالیت یک کسب و کار"""
	cache = get_cache()
	cache_key = None

	if cache.enabled:
		import json, hashlib
		key_payload = {
			"business_id": business_id,
			"category": category,
			"entity_type": entity_type,
			"start_date": start_date.isoformat() if start_date else None,
			"end_date": end_date.isoformat() if end_date else None,
			"page": page,
			"per_page": per_page,
		}
		key_str = json.dumps(key_payload, sort_keys=True, ensure_ascii=False)
		key_hash = hashlib.sha256(key_str.encode("utf-8")).hexdigest()[:16]
		cache_key = f"activity_logs:{key_hash}"
		cached = cache.get(cache_key)
		if cached is not None:
			return success_response(data=cached, request=request)

	repo = ActivityLogRepository(db)
	offset = (page - 1) * per_page
	
	logs = repo.get_by_business(
		business_id=business_id,
		category=category,
		entity_type=entity_type,
		start_date=start_date,
		end_date=end_date,
		limit=per_page,
		offset=offset
	)
	
	# شمارش کل
	total = repo.count_by_business(
		business_id=business_id,
		category=category,
		entity_type=entity_type,
		start_date=start_date,
		end_date=end_date
	)
	
	# تبدیل به دیکشنری
	logs_data = []
	for log in logs:
		logs_data.append({
			"id": log.id,
			"user_id": log.user_id,
			"user_name": f"{log.user.first_name or ''} {log.user.last_name or ''}".strip() if log.user else None,
			"category": log.category,
			"action": log.action,
			"entity_type": log.entity_type,
			"entity_id": log.entity_id,
			"description": log.description,
			"before_data": log.before_data,
			"after_data": log.after_data,
			"extra_info": log.extra_info,
			"created_at": log.created_at.isoformat()
		})

	response_data = {
		"items": logs_data,
		"page": page,
		"per_page": per_page,
		"total": total,
		"total_pages": (total + per_page - 1) // per_page if total > 0 else 0
	}

	if cache.enabled and cache_key:
		# لاگ‌ها نسبتا سریع تغییر می‌کنند → TTL کوتاه
		cache.set(cache_key, response_data, ttl=30)
	
	return success_response(
		data=response_data,
		request=request
	)


@router.get("/entity/{entity_type}/{entity_id}")
def get_entity_activity_logs(
	request: Request,
	entity_type: str,
	entity_id: str,  # تغییر به str برای پشتیبانی از UUID
	business_id: Optional[int] = Query(None, description="شناسه کسب و کار (اختیاری)"),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db)
) -> dict:
	"""دریافت تاریخچه تغییرات یک موجودیت"""
	# اگر business_id داده شده، بررسی دسترسی
	if business_id:
		if not ctx.can_access_business(business_id):
			raise ApiError("FORBIDDEN", f"No access to business {business_id}", http_status=403)
	
	repo = ActivityLogRepository(db)
	
	logs = repo.get_by_entity(
		entity_type=entity_type,
		entity_id=entity_id,  # حالا می‌تواند UUID (str) یا int (به صورت str) باشد
		business_id=business_id
	)
	
	logs_data = []
	for log in logs:
		# بررسی دسترسی به business_id لاگ
		if log.business_id and not ctx.can_access_business(log.business_id):
			continue  # skip لاگ‌هایی که دسترسی نداریم
		
		logs_data.append({
			"id": log.id,
			"user_id": log.user_id,
			"user_name": f"{log.user.first_name or ''} {log.user.last_name or ''}".strip() if log.user else None,
			"business_id": log.business_id,
			"action": log.action,
			"description": log.description,
			"before_data": log.before_data,
			"after_data": log.after_data,
			"created_at": log.created_at.isoformat()
		})
	
	return success_response(data={"items": logs_data}, request=request)


@router.get("/user/me")
def get_my_activity_logs(
	request: Request,
	business_id: Optional[int] = Query(None, description="شناسه کسب و کار (اختیاری)"),
	page: int = Query(1, ge=1, description="شماره صفحه"),
	per_page: int = Query(50, ge=1, le=200, description="تعداد در هر صفحه"),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db)
) -> dict:
	"""دریافت لاگ‌های فعالیت کاربر جاری"""
	# اگر business_id داده شده، بررسی دسترسی
	if business_id:
		if not ctx.can_access_business(business_id):
			raise ApiError("FORBIDDEN", f"No access to business {business_id}", http_status=403)
	
	repo = ActivityLogRepository(db)
	offset = (page - 1) * per_page
	
	logs = repo.get_by_user(
		user_id=ctx.user.id,
		business_id=business_id,
		limit=per_page,
		offset=offset
	)
	
	logs_data = []
	for log in logs:
		# بررسی دسترسی به business_id لاگ
		if log.business_id and not ctx.can_access_business(log.business_id):
			continue  # skip لاگ‌هایی که دسترسی نداریم
		
		logs_data.append({
			"id": log.id,
			"business_id": log.business_id,
			"business_name": log.business.name if log.business else None,
			"category": log.category,
			"action": log.action,
			"entity_type": log.entity_type,
			"entity_id": log.entity_id,
			"description": log.description,
			"created_at": log.created_at.isoformat()
		})
	
	return success_response(
		data={
			"items": logs_data,
			"page": page,
			"per_page": per_page
		},
		request=request
	)

