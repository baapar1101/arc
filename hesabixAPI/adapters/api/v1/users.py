from __future__ import annotations

from fastapi import APIRouter, Depends, Request, Query
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from adapters.db.repositories.user_repo import UserRepository
from adapters.api.v1.schemas import QueryInfo
from app.core.responses import success_response, format_datetime_fields
from app.core.auth_dependency import get_current_user, AuthContext


router = APIRouter(prefix="/users", tags=["users"])


@router.get("", summary="لیست کاربران با فیلتر پیشرفته")
def list_users(
	request: Request,
	query_info: QueryInfo = Depends(),
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db)
) -> dict:
	"""
	دریافت لیست کاربران با قابلیت فیلتر، جستجو، مرتب‌سازی و صفحه‌بندی
	
	پارامترهای QueryInfo:
	- sort_by: فیلد مرتب‌سازی (مثال: created_at, first_name)
	- sort_desc: ترتیب نزولی (true/false)
	- take: تعداد رکورد در هر صفحه (پیش‌فرض: 10)
	- skip: تعداد رکورد صرف‌نظر شده (پیش‌فرض: 0)
	- search: عبارت جستجو
	- search_fields: فیلدهای جستجو (مثال: ["first_name", "last_name", "email"])
	- filters: آرایه فیلترها با ساختار:
	  [
		{
		  "property": "is_active",
		  "operator": "=",
		  "value": true
		},
		{
		  "property": "first_name", 
		  "operator": "*",
		  "value": "احمد"
		}
	  ]
	
	عملگرهای پشتیبانی شده:
	- = : برابر
	- > : بزرگتر از
	- >= : بزرگتر یا مساوی
	- < : کوچکتر از
	- <= : کوچکتر یا مساوی
	- != : نامساوی
	- * : شامل (contains)
	- ?* : خاتمه یابد (ends with)
	- *? : شروع شود (starts with)
	- in : در بین مقادیر آرایه
	"""
	repo = UserRepository(db)
	users, total = repo.query_with_filters(query_info)
	
	# تبدیل User objects به dictionary
	user_dicts = [repo.to_dict(user) for user in users]
	
	# فرمت کردن تاریخ‌ها
	formatted_users = [format_datetime_fields(user_dict, request) for user_dict in user_dicts]
	
	# محاسبه اطلاعات صفحه‌بندی
	page = (query_info.skip // query_info.take) + 1
	total_pages = (total + query_info.take - 1) // query_info.take
	
	response_data = {
		"items": formatted_users,
		"pagination": {
			"total": total,
			"page": page,
			"per_page": query_info.take,
			"total_pages": total_pages,
			"has_next": page < total_pages,
			"has_prev": page > 1
		},
		"query_info": {
			"sort_by": query_info.sort_by,
			"sort_desc": query_info.sort_desc,
			"search": query_info.search,
			"search_fields": query_info.search_fields,
			"filters": [{"property": f.property, "operator": f.operator, "value": f.value} for f in (query_info.filters or [])]
		}
	}
	
	return success_response(response_data, request)


@router.get("/{user_id}", summary="دریافت اطلاعات یک کاربر")
def get_user(
	user_id: int,
	request: Request,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db)
) -> dict:
	"""دریافت اطلاعات یک کاربر بر اساس ID"""
	repo = UserRepository(db)
	user = repo.get_by_id(user_id)
	
	if not user:
		from fastapi import HTTPException
		raise HTTPException(status_code=404, detail="کاربر یافت نشد")
	
	user_dict = repo.to_dict(user)
	formatted_user = format_datetime_fields(user_dict, request)
	
	return success_response(formatted_user, request)


@router.get("/stats/summary", summary="آمار کلی کاربران")
def get_users_summary(
	request: Request,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db)
) -> dict:
	"""دریافت آمار کلی کاربران"""
	repo = UserRepository(db)
	
	# تعداد کل کاربران
	total_users = repo.count_all()
	
	# تعداد کاربران فعال
	active_users = repo.query_with_filters(QueryInfo(
		filters=[{"property": "is_active", "operator": "=", "value": True}]
	))[1]
	
	# تعداد کاربران غیرفعال
	inactive_users = total_users - active_users
	
	response_data = {
		"total_users": total_users,
		"active_users": active_users,
		"inactive_users": inactive_users,
		"active_percentage": round((active_users / total_users * 100), 2) if total_users > 0 else 0
	}
	
	return success_response(response_data, request)


