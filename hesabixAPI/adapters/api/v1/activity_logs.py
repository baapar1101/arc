from fastapi import APIRouter, Depends, Request, Query
from sqlalchemy.orm import Session
from typing import Optional
from datetime import datetime
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.responses import success_response, ApiError
from app.core.permissions import require_business_access
from adapters.db.session import get_db
from adapters.db.repositories.activity_log_repo import ActivityLogRepository
from adapters.db.models.activity_log import ActivityLog

router = APIRouter(prefix="/activity-logs", tags=["activity-logs"])


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
	
	return success_response(
		data={
			"items": logs_data,
			"page": page,
			"per_page": per_page,
			"total": total,
			"total_pages": (total + per_page - 1) // per_page if total > 0 else 0
		},
		request=request
	)


@router.get("/entity/{entity_type}/{entity_id}")
def get_entity_activity_logs(
	request: Request,
	entity_type: str,
	entity_id: int,
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
		entity_id=entity_id,
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

