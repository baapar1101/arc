# Removed __future__ annotations to fix OpenAPI schema generation

from fastapi import APIRouter, Depends, Request, Query
from sqlalchemy.orm import Session

from adapters.db.session import get_db
from adapters.db.repositories.user_repo import UserRepository
from adapters.api.v1.schemas import QueryInfo, SuccessResponse, UsersListResponse, UsersSummaryResponse, UserResponse
from app.core.responses import success_response, format_datetime_fields
from app.core.auth_dependency import get_current_user, AuthContext
from app.core.permissions import require_user_management


router = APIRouter(prefix="/users", tags=["users"])


@router.post("/search", 
	summary="لیست کاربران با فیلتر پیشرفته", 
	description="دریافت لیست کاربران با قابلیت فیلتر، جستجو، مرتب‌سازی و صفحه‌بندی. نیاز به مجوز usermanager در سطح اپلیکیشن دارد.",
	response_model=SuccessResponse,
	responses={
		200: {
			"description": "لیست کاربران با موفقیت دریافت شد",
			"content": {
				"application/json": {
					"example": {
						"success": True,
						"message": "لیست کاربران دریافت شد",
						"data": {
							"items": [
								{
									"id": 1,
									"email": "user@example.com",
									"mobile": "09123456789",
									"first_name": "احمد",
									"last_name": "احمدی",
									"is_active": True,
									"referral_code": "ABC123",
									"created_at": "2024-01-01T00:00:00Z"
								}
							],
							"pagination": {
								"total": 1,
								"page": 1,
								"per_page": 10,
								"total_pages": 1,
								"has_next": False,
								"has_prev": False
							}
						}
					}
				}
			}
		},
		401: {
			"description": "کاربر احراز هویت نشده است"
		},
		403: {
			"description": "دسترسی غیرمجاز - نیاز به مجوز usermanager",
			"content": {
				"application/json": {
					"example": {
						"success": False,
						"message": "Missing app permission: user_management",
						"error_code": "FORBIDDEN"
					}
				}
			}
		}
	}
)
@require_user_management()
def list_users(
	request: Request,
	query_info: QueryInfo,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db)
):
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


@router.get("", 
	summary="لیست ساده کاربران", 
	description="دریافت لیست ساده کاربران. نیاز به مجوز usermanager در سطح اپلیکیشن دارد.",
	response_model=SuccessResponse,
	responses={
		200: {
			"description": "لیست کاربران با موفقیت دریافت شد",
			"content": {
				"application/json": {
					"example": {
						"success": True,
						"message": "لیست کاربران دریافت شد",
						"data": [
							{
								"id": 1,
								"email": "user@example.com",
								"mobile": "09123456789",
								"first_name": "احمد",
								"last_name": "احمدی",
								"is_active": True,
								"referral_code": "ABC123",
								"created_at": "2024-01-01T00:00:00Z"
							}
						]
					}
				}
			}
		},
		401: {
			"description": "کاربر احراز هویت نشده است"
		},
		403: {
			"description": "دسترسی غیرمجاز - نیاز به مجوز usermanager",
			"content": {
				"application/json": {
					"example": {
						"success": False,
						"message": "Missing app permission: user_management",
						"error_code": "FORBIDDEN"
					}
				}
			}
		}
	}
)
@require_user_management()
def list_users_simple(
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db),
	limit: int = Query(10, ge=1, le=100, description="تعداد رکورد در هر صفحه"),
	offset: int = Query(0, ge=0, description="تعداد رکورد صرف‌نظر شده")
):
	"""دریافت لیست ساده کاربران"""
	repo = UserRepository(db)
	
	# Create basic query info
	query_info = QueryInfo(take=limit, skip=offset)
	users, total = repo.query_with_filters(query_info)
	
	# تبدیل User objects به dictionary
	user_dicts = [repo.to_dict(user) for user in users]
	
	# فرمت کردن تاریخ‌ها
	formatted_users = [format_datetime_fields(user_dict, None) for user_dict in user_dicts]
	
	return success_response(formatted_users, None)


@router.get("/{user_id}", 
	summary="دریافت اطلاعات یک کاربر", 
	description="دریافت اطلاعات کامل یک کاربر بر اساس شناسه. نیاز به مجوز usermanager در سطح اپلیکیشن دارد.",
	response_model=SuccessResponse,
	responses={
		200: {
			"description": "اطلاعات کاربر با موفقیت دریافت شد",
			"content": {
				"application/json": {
					"example": {
						"success": True,
						"message": "اطلاعات کاربر دریافت شد",
						"data": {
							"id": 1,
							"email": "user@example.com",
							"mobile": "09123456789",
							"first_name": "احمد",
							"last_name": "احمدی",
							"is_active": True,
							"referral_code": "ABC123",
							"created_at": "2024-01-01T00:00:00Z"
						}
					}
				}
			}
		},
		401: {
			"description": "کاربر احراز هویت نشده است"
		},
		403: {
			"description": "دسترسی غیرمجاز - نیاز به مجوز usermanager",
			"content": {
				"application/json": {
					"example": {
						"success": False,
						"message": "Missing app permission: user_management",
						"error_code": "FORBIDDEN"
					}
				}
			}
		},
		404: {
			"description": "کاربر یافت نشد",
			"content": {
				"application/json": {
					"example": {
						"success": False,
						"message": "کاربر یافت نشد",
						"error_code": "USER_NOT_FOUND"
					}
				}
			}
		}
	}
)
@require_user_management()
def get_user(
	user_id: int,
	request: Request,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db)
):
	"""دریافت اطلاعات یک کاربر بر اساس ID"""
	repo = UserRepository(db)
	user = repo.get_by_id(user_id)
	
	if not user:
		from fastapi import HTTPException
		raise HTTPException(status_code=404, detail="کاربر یافت نشد")
	
	user_dict = repo.to_dict(user)
	formatted_user = format_datetime_fields(user_dict, request)
	
	return success_response(formatted_user, request)


@router.get("/stats/summary", 
	summary="آمار کلی کاربران", 
	description="دریافت آمار کلی کاربران شامل تعداد کل، فعال و غیرفعال. نیاز به مجوز usermanager در سطح اپلیکیشن دارد.",
	response_model=SuccessResponse,
	responses={
		200: {
			"description": "آمار کاربران با موفقیت دریافت شد",
			"content": {
				"application/json": {
					"example": {
						"success": True,
						"message": "آمار کاربران دریافت شد",
						"data": {
							"total_users": 100,
							"active_users": 85,
							"inactive_users": 15,
							"active_percentage": 85.0
						}
					}
				}
			}
		},
		401: {
			"description": "کاربر احراز هویت نشده است"
		},
		403: {
			"description": "دسترسی غیرمجاز - نیاز به مجوز usermanager",
			"content": {
				"application/json": {
					"example": {
						"success": False,
						"message": "Missing app permission: user_management",
						"error_code": "FORBIDDEN"
					}
				}
			}
		}
	}
)
@require_user_management()
def get_users_summary(
	request: Request,
	ctx: AuthContext = Depends(get_current_user),
	db: Session = Depends(get_db)
):
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


